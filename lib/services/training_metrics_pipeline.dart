import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import '../data/local/trainmate_structured_database_gateway.dart';
import '../data/models/training_metrics.dart';
import '../data/repositories/training_metrics_repository.dart';
import '../features/profile/application/health_data_gateway_contract.dart';
import 'training_metrics_engine.dart';

/// 将结构化健康事实送入纯 Dart 指标引擎，并保存可追溯结果。
///
/// 原始心率和 GPS 仅在本方法调用期间存在于内存；分析运行只保存质量摘要、
/// 段级结果、负荷口径和输入指纹。
class TrainingMetricsPipeline {
  TrainingMetricsPipeline({
    required TrainMateStructuredDatabaseGateway database,
    required TrainingMetricsRepository repository,
    required HealthDataGateway healthDataGateway,
    TrainingMetricsEngine? engine,
    DateTime Function()? clock,
  })  : _database = database,
        _repository = repository,
        _healthDataGateway = healthDataGateway,
        _engine = engine ?? TrainingMetricsEngine(),
        _clock = clock ?? DateTime.now;

  static const String workoutAlgorithmVersion = 'trainmate-workout-analysis-v2';
  static const String aggregateAlgorithmVersion =
      'trainmate-period-aggregate-v1';
  static const String strengthAlgorithmVersion =
      'trainmate-l2-strength-epley-v1';
  static const String badmintonAlgorithmVersion =
      'trainmate-l2-badminton-descriptive-v1';
  static const int rawSampleIsolateThreshold = 1000;

  final TrainMateStructuredDatabaseGateway _database;
  final TrainingMetricsRepository _repository;
  final HealthDataGateway _healthDataGateway;
  final TrainingMetricsEngine _engine;
  final DateTime Function() _clock;

  Future<WorkoutAnalysisOutcome> analyzeWorkout({
    required String athleteProfileId,
    required String workoutId,
  }) async {
    final Map<String, Object?>? row = await _database.readWorkoutFactRow(
      athleteProfileId: athleteProfileId,
      workoutId: workoutId,
    );
    if (row == null) {
      throw StateError('找不到待分析的训练事实。');
    }
    if (row['source_deleted_at'] != null) {
      await invalidateBySource(
        athleteProfileId: athleteProfileId,
        sourceId: workoutId,
      );
      throw StateError('训练事实已删除，不能继续分析。');
    }

    final DateTime startedAt = _requiredDate(row['started_at_utc'], '训练开始时间');
    final DateTime endedAt = _requiredDate(row['ended_at_utc'], '训练结束时间');
    final String externalUuid = row['external_uuid'] as String? ?? '';
    final Map<String, Object?> payload = _decodeObject(
      row['payload_json'],
      label: '训练事实载荷',
    );
    Map<String, Object?> details = const <String, Object?>{};
    if (externalUuid.isNotEmpty && _healthDataGateway.isSupported) {
      details = await _healthDataGateway.fetchWorkoutDetails(externalUuid) ??
          const <String, Object?>{};
    }

    final Future<_BanisterContext> banisterContextFuture = _readBanisterContext(
      athleteProfileId: athleteProfileId,
      workoutStartedAt: startedAt,
    );
    final _ProcessedRawWorkout rawAnalysis = await _processRawWorkoutDetails(
      details: details,
      workoutId: workoutId,
      startedAt: startedAt,
      endedAt: endedAt,
      isAerobicConfirmed: payload['isAerobic'] == true,
    );
    final bool hasExplicitHeartRateDetails =
        details['heartRateSamples'] is List;
    final double? averageHeartRate = rawAnalysis.averageHeartRate ??
        _finiteNumber(row['average_heart_rate']);
    final double heartRateCoverage = rawAnalysis.hasHeartRateSamples
        ? rawAnalysis.heartRateCoverage
        : (_finiteNumber(row['heart_rate_coverage']) ?? 0)
            .clamp(0, 1)
            .toDouble();
    final int durationSeconds = _positiveInt(row['active_duration_seconds']) ??
        _positiveInt(row['elapsed_duration_seconds']) ??
        math.max(0, endedAt.difference(startedAt).inSeconds);
    final WorkoutDiscipline discipline = _discipline(
      row['discipline'] as String?,
      runContext: row['run_context'] as String?,
      sourceKind: row['source_kind'] as String?,
    );
    final _BanisterContext banisterContext = await banisterContextFuture;
    final List<TrainingLoadValue> loads = _engine.calculateLoadSeries(
      input: TrainingLoadInput(
        workoutId: workoutId,
        occurredOn: _localDate(row, startedAt),
        discipline: discipline,
        durationMinutes: durationSeconds / 60,
        rpe: _finiteNumber(payload['rpe']),
        averageHeartRate: averageHeartRate,
        restingHeartRate: banisterContext.restingHeartRate,
        maxHeartRate: banisterContext.maxHeartRate,
        heartRateCoverage: heartRateCoverage,
        biologicalSex: banisterContext.biologicalSex,
      ),
    );
    final _RouteSummary route = rawAnalysis.route;
    final List<SteadyPaceSegment> steadySegments = rawAnalysis.steadySegments;
    final VamResult vam = _engine.calculateVam(
      grade: route.grade,
      elevationGainMeters: route.elevationGainMeters,
      duration: Duration(seconds: route.durationSeconds),
    );
    final DeviceBestSegment? deviceBest =
        route.distanceMeters > 0 && route.durationSeconds > 0
            ? _engine.buildDeviceBestSegment(
                sourceId: workoutId,
                distanceMeters: route.distanceMeters,
                durationSeconds: route.durationSeconds,
              )
            : null;
    final _FingerprintBuilder fingerprintBuilder = _FingerprintBuilder()
      ..add(workoutId)
      ..add(row['payload_json'])
      ..add(banisterContext.biologicalSex.name)
      ..add(banisterContext.maxHeartRate)
      ..add(banisterContext.restingHeartRate)
      ..add(rawAnalysis.rawSampleFingerprint);
    final String inputFingerprint = fingerprintBuilder.finish();
    final DateTime analyzedAt = _clock().toUtc();
    final Map<String, Object?> result = <String, Object?>{
      'schemaVersion': 1,
      'workoutId': workoutId,
      'occurredOn': _dateKey(_localDate(row, startedAt)),
      'timeZoneName': row['time_zone_name'] as String? ?? 'UTC',
      'discipline': discipline.name,
      'durationSeconds': durationSeconds,
      'loads': loads
          .map(
            (TrainingLoadValue item) => <String, Object?>{
              'method': item.method.code,
              'value': item.value,
              'durationMinutes': item.durationMinutes,
              'estimated': item.estimated,
              'coverage': item.coverage,
              'reason': item.reason,
            },
          )
          .toList(growable: false),
      'steadySegments': steadySegments
          .map(
            (SteadyPaceSegment item) => <String, Object?>{
              'sourceWorkoutId': item.sourceWorkoutId,
              'occurredAt': item.occurredAt.toUtc().toIso8601String(),
              'durationSeconds': item.durationSeconds,
              'paceSecondsPerKm': item.paceSecondsPerKm,
              'grade': item.grade,
              'paceCoefficientOfVariation': item.paceCoefficientOfVariation,
              'averageHeartRate': item.averageHeartRate,
              'heartRateCoverage': item.heartRateCoverage,
              'warmupExcluded': item.warmupExcluded,
              'isAerobic': payload['isAerobic'] == true,
            },
          )
          .toList(growable: false),
      'vam': <String, Object?>{
        'status': vam.status.name,
        'metersPerHour': vam.metersPerHour,
        'label': vam.label,
      },
      'deviceBestSegment': deviceBest == null
          ? null
          : <String, Object?>{
              'sourceId': deviceBest.sourceId,
              'distanceMeters': deviceBest.distanceMeters,
              'durationSeconds': deviceBest.durationSeconds,
              'displayName': deviceBest.displayName,
              'isOfficialRaceResult': false,
            },
    };
    await _database.saveWorkoutAnalysisRunRow(<String, Object?>{
      'id': 'analysis:$workoutId:$workoutAlgorithmVersion:$inputFingerprint',
      'athlete_profile_id': athleteProfileId,
      'workout_id': workoutId,
      'algorithm_version': workoutAlgorithmVersion,
      'input_fingerprint': inputFingerprint,
      'status': 'completed',
      'quality_json': jsonEncode(<String, Object?>{
        'rawHeartRateSampleCount': rawAnalysis.rawHeartRateSampleCount,
        'rejectedHeartRateSampleCount':
            rawAnalysis.rejectedHeartRateSampleCount,
        'heartRateCoverage': heartRateCoverage,
        'rawGpsPointCount': rawAnalysis.rawGpsPointCount,
        'validGpsPointCount': rawAnalysis.validGpsPointCount,
        'processingMode':
            rawAnalysis.usedBackgroundIsolate ? 'backgroundIsolate' : 'inline',
      }),
      'result_json': jsonEncode(result),
      'started_at': analyzedAt.toIso8601String(),
      'completed_at': analyzedAt.toIso8601String(),
      'invalidated_at': null,
      if (hasExplicitHeartRateDetails)
        'workout_summary': <String, Object?>{
          'averageHeartRate': rawAnalysis.averageHeartRate,
          'maximumHeartRate': rawAnalysis.maximumHeartRate,
          'heartRateSampleCount': rawAnalysis.rawHeartRateSampleCount,
          'heartRateCoverage': rawAnalysis.heartRateCoverage,
        },
    }, markRouteAvailable: rawAnalysis.validGpsPointCount >= 2);
    return WorkoutAnalysisOutcome(
      athleteProfileId: athleteProfileId,
      workoutId: workoutId,
      occurredOn: _localDate(row, startedAt),
      inputFingerprint: inputFingerprint,
      loads: List<TrainingLoadValue>.unmodifiable(loads),
      steadySegments: List<SteadyPaceSegment>.unmodifiable(steadySegments),
      vam: vam,
      deviceBestSegment: deviceBest,
    );
  }

  Future<_ProcessedRawWorkout> _processRawWorkoutDetails({
    required Map<String, Object?> details,
    required String workoutId,
    required DateTime startedAt,
    required DateTime endedAt,
    required bool isAerobicConfirmed,
  }) async {
    if (_rawSampleCount(details) >= rawSampleIsolateThreshold) {
      try {
        final _ProcessedRawWorkout processed = await Isolate.run(
          () => _processRawWorkoutInBackground(
            details: details,
            workoutId: workoutId,
            startedAt: startedAt,
            endedAt: endedAt,
            isAerobicConfirmed: isAerobicConfirmed,
          ),
          debugName: 'TrainMate原始训练分析',
        );
        return processed.withBackgroundIsolate();
      } on UnsupportedError {
        // 不支持 isolate 的平台（例如 Web）没有 HealthKit；保留确定性的同线程降级。
      }
    }
    final List<HeartRateSample> heartRateSamples =
        _heartRateSamples(details['heartRateSamples']);
    final HeartRateProcessingResult? processedHeartRate =
        heartRateSamples.isEmpty
            ? null
            : _engine.processHeartRateSamples(
                samples: heartRateSamples,
                start: startedAt,
                end: endedAt,
              );
    final List<double> validHeartRates = _validHeartRateValues(
      heartRateSamples,
      start: startedAt,
      end: endedAt,
    );
    final List<GpsSample> rawGps = _gpsSamples(details['routes']);
    final List<GpsSample> validGps = _engine.filterGpsSamples(rawGps);
    return _ProcessedRawWorkout(
      hasHeartRateSamples: heartRateSamples.isNotEmpty,
      rawHeartRateSampleCount: processedHeartRate?.rawSampleCount ?? 0,
      rejectedHeartRateSampleCount:
          processedHeartRate?.rejectedSampleCount ?? 0,
      heartRateCoverage: processedHeartRate?.rawCoverage ?? 0,
      averageHeartRate: validHeartRates.isEmpty
          ? null
          : validHeartRates.reduce((double a, double b) => a + b) /
              validHeartRates.length,
      maximumHeartRate:
          validHeartRates.isEmpty ? null : validHeartRates.reduce(math.max),
      rawGpsPointCount: rawGps.length,
      validGpsPointCount: validGps.length,
      route: _routeSummary(validGps),
      steadySegments: _steadySegments(
        workoutId: workoutId,
        startedAt: startedAt,
        endedAt: endedAt,
        heartRateSamples: heartRateSamples,
        gpsSamples: validGps,
        isAerobicConfirmed: isAerobicConfirmed,
      ),
      rawSampleFingerprint: _rawSampleFingerprint(heartRateSamples, validGps),
      usedBackgroundIsolate: false,
    );
  }

  Future<_BanisterContext> _readBanisterContext({
    required String athleteProfileId,
    required DateTime workoutStartedAt,
  }) async {
    final Map<String, Object?>? profile =
        await _database.readAthleteProfileRow(athleteProfileId);
    if (profile == null) return const _BanisterContext.unavailable();

    final BiologicalSex biologicalSex =
        switch ((profile['biological_sex'] as String? ?? '').toLowerCase()) {
      'male' => BiologicalSex.male,
      'female' => BiologicalSex.female,
      _ => BiologicalSex.unknown,
    };
    final Object? rawPayload = profile['payload_json'];
    final Map<String, Object?> payload = rawPayload == null
        ? const <String, Object?>{}
        : _decodeObject(rawPayload, label: '运动员资料载荷');
    final double? storedMaxHeartRate = _finiteNumber(payload['maxHeartRate']);
    final double? maxHeartRate = storedMaxHeartRate != null &&
            storedMaxHeartRate >= 80 &&
            storedMaxHeartRate <= 240
        ? storedMaxHeartRate
        : null;
    if (biologicalSex == BiologicalSex.unknown || maxHeartRate == null) {
      return _BanisterContext(
        biologicalSex: biologicalSex,
        maxHeartRate: maxHeartRate,
        restingHeartRate: null,
      );
    }

    final DateTime before = workoutStartedAt.toUtc();
    final List<Map<String, Object?>> observations =
        await _database.listHealthObservationFactRows(
      athleteProfileId: athleteProfileId,
      observedAtOrAfter:
          before.subtract(const Duration(days: 30)).toIso8601String(),
      observedBefore: before.toIso8601String(),
    );
    DateTime? latestAt;
    double? restingHeartRate;
    for (final Map<String, Object?> observation in observations) {
      final String kind =
          (observation['observation_kind'] as String? ?? '').toLowerCase();
      if (!kind.contains('restingheartrate')) continue;
      final DateTime? observedAt = _optionalDate(
        observation['observed_at_utc'],
      )?.toUtc();
      final double? value = _finiteNumber(observation['value']);
      if (observedAt == null ||
          !observedAt.isBefore(before) ||
          value == null ||
          value < 20 ||
          value > 150) {
        continue;
      }
      if (latestAt == null || observedAt.isAfter(latestAt)) {
        latestAt = observedAt;
        restingHeartRate = value;
      }
    }
    return _BanisterContext(
      biologicalSex: biologicalSex,
      maxHeartRate: maxHeartRate,
      restingHeartRate: restingHeartRate,
    );
  }

  Future<List<MetricAggregate>> aggregatePeriod({
    required String athleteProfileId,
    required MetricPeriod period,
    required DateTime periodStart,
  }) async {
    if (athleteProfileId.isEmpty) {
      throw ArgumentError.value(
        athleteProfileId,
        'athleteProfileId',
        '运动员标识不能为空',
      );
    }
    if (period != MetricPeriod.week && period != MetricPeriod.month) {
      throw ArgumentError.value(period, 'period', '当前仅支持周和月聚合');
    }
    final DateTime normalizedStart = _periodStart(period, periodStart);
    final DateTime endExclusive = _periodEndExclusive(period, normalizedStart);
    final DateTime historyStart =
        endExclusive.subtract(const Duration(days: 56));
    final List<Map<String, Object?>> runRows =
        await _database.listWorkoutAnalysisRunRows(
      athleteProfileId: athleteProfileId,
      // UTC 查询窗口向两侧扩展，再用事实的 local_date 精确筛选，避免跨时区
      // 和夏令时周边界把本地日期训练漏掉。
      workoutStartedAtOrAfter: historyStart
          .subtract(const Duration(days: 2))
          .toUtc()
          .toIso8601String(),
      workoutStartedBefore:
          endExclusive.add(const Duration(days: 2)).toUtc().toIso8601String(),
    );
    final List<_StoredWorkoutAnalysis> runs =
        _latestCurrentAnalysisRows(runRows)
            .map(_storedAnalysis)
            .whereType<_StoredWorkoutAnalysis>()
            .toList(growable: false);
    final DateTime now = _clock();
    final DateTime computedAt = now.toUtc();
    final List<MetricAggregate> saved = <MetricAggregate>[];
    final DateTime periodLastInstant =
        endExclusive.subtract(const Duration(microseconds: 1));
    final DateTime acwrAsOf =
        now.isBefore(periodLastInstant) ? now : periodLastInstant;
    final DateTime asOfLocalDate =
        DateTime(acwrAsOf.year, acwrAsOf.month, acwrAsOf.day);
    final List<_StoredWorkoutAnalysis> periodRuns = runs
        .where(
          (_StoredWorkoutAnalysis item) =>
              !item.occurredOn.isBefore(normalizedStart) &&
              item.occurredOn.isBefore(endExclusive) &&
              !item.occurredOn.isAfter(asOfLocalDate),
        )
        .toList(growable: false);
    final DateTime acwrWindowStart =
        asOfLocalDate.subtract(const Duration(days: 27));
    final List<_StoredWorkoutAnalysis> acwrRuns = runs
        .where(
          (_StoredWorkoutAnalysis item) =>
              !item.occurredOn.isBefore(acwrWindowStart) &&
              !item.occurredOn.isAfter(asOfLocalDate),
        )
        .toList(growable: false);
    final List<TrainingLoadValue> loadValues = acwrRuns
        .expand((_StoredWorkoutAnalysis item) => item.loads)
        .toList(growable: false);
    final bool hasCompleteAcwrWindow = await _hasCompleteWorkoutSyncWindow(
      athleteProfileId: athleteProfileId,
      asOf: acwrAsOf,
    );
    final AcwrResult acwr = _engine.calculateAcwr(
      values: loadValues,
      asOf: acwrAsOf,
      hasComplete28DayWindow: hasCompleteAcwrWindow,
    );
    final MetricAggregate acwrMetric = MetricAggregate(
      id: _metricId(
        athleteProfileId,
        'acwr',
        'selected',
        period,
        normalizedStart,
      ),
      athleteProfileId: athleteProfileId,
      metricCode: acwr.method == null ? 'acwr' : 'acwr.${acwr.method!.code}',
      period: period,
      periodStart: normalizedStart,
      value: acwr.ratio,
      unit: 'ratio',
      sampleCount: loadValues.length,
      sampleDurationSeconds: 28 * 24 * 60 * 60,
      coverage: acwr.coverage,
      status: acwr.status,
      algorithmVersion: TrainingMetricsEngine.acwrAlgorithmVersion,
      inputFingerprint: _fingerprint(
        acwrRuns.map((_StoredWorkoutAnalysis item) => item.inputFingerprint),
      ),
      computedAt: computedAt,
      loadMethod: acwr.method,
      metadata: <String, Object?>{
        'reason': acwr.reason,
        'acuteTotal': acwr.acuteTotal,
        'chronicTotal': acwr.chronicTotal,
        'windowCoverageVerified': hasCompleteAcwrWindow,
        'timeZoneName': _periodTimeZone(periodRuns),
      },
    );
    await _saveMetric(acwrMetric, acwrRuns);
    saved.add(acwrMetric);

    if (period == MetricPeriod.week) {
      saved.addAll(
        await _aggregateWeeklyRunningMetrics(
          athleteProfileId: athleteProfileId,
          periodStart: normalizedStart,
          periodEndExclusive: endExclusive,
          runs: runs,
          periodRuns: periodRuns,
          computedAt: computedAt,
          asOf: acwrAsOf,
        ),
      );
      saved.addAll(
        await _aggregateWeeklyDisciplineMetrics(
          athleteProfileId: athleteProfileId,
          periodStart: normalizedStart,
          periodEndExclusive: endExclusive,
          runs: runs,
          periodRuns: periodRuns,
          computedAt: computedAt,
        ),
      );
    } else {
      saved.addAll(
        await _aggregateMonthlyBodyMetrics(
          athleteProfileId: athleteProfileId,
          periodStart: normalizedStart,
          periodEndExclusive: endExclusive,
          computedAt: computedAt,
        ),
      );
    }
    return List<MetricAggregate>.unmodifiable(saved);
  }

  Future<bool> _hasCompleteWorkoutSyncWindow({
    required String athleteProfileId,
    required DateTime asOf,
  }) async {
    final DateTime requiredStart =
        asOf.toUtc().subtract(const Duration(days: 28));
    final DateTime requiredEnd = asOf.toUtc();
    for (final String objectType in const <String>[
      'coverage:foreground.workout',
      'coverage:foreground.analysis',
    ]) {
      final Map<String, Object?>? row = await _database.readHealthSyncAnchor(
        athleteId: athleteProfileId,
        objectType: objectType,
        queryVersion: 1,
      );
      if (_coverageContains(
        row?['anchor_payload'],
        requiredStart: requiredStart,
        requiredEnd: requiredEnd,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _coverageContains(
    Object? payload, {
    required DateTime requiredStart,
    required DateTime requiredEnd,
  }) {
    try {
      final Object? decoded = payload is String ? jsonDecode(payload) : payload;
      if (decoded is! Map) return false;
      final Map<String, Object?> value = Map<String, Object?>.from(decoded);
      final DateTime? start =
          DateTime.tryParse(value['start'] as String? ?? '')?.toUtc();
      final DateTime? end =
          DateTime.tryParse(value['end'] as String? ?? '')?.toUtc();
      if (start == null || end == null || !start.isBefore(end)) return false;
      return !start.isAfter(requiredStart) &&
          !end.add(const Duration(minutes: 5)).isBefore(requiredEnd);
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> invalidateBySource({
    required String athleteProfileId,
    required String sourceId,
    String sourceType = 'workouts',
  }) {
    return _repository.invalidateBySource(
      athleteProfileId: athleteProfileId,
      sourceType: sourceType,
      sourceId: sourceId,
      invalidatedAt: _clock().toUtc(),
    );
  }

  /// 在健康批次事实事务成功后分析受影响训练，并刷新对应周/月指标。
  Future<HealthBatchMetricsResult> processCommittedHealthBatch(
    HealthSyncBatch batch,
    HealthSyncApplyResult applyResult,
  ) async {
    final Set<DateTime> affectedDays = <DateTime>{};
    final Set<String> analyzedWorkoutIds = <String>{};
    for (final Map<String, Object?> raw in batch.upserts) {
      if ((raw['kind'] as String? ?? '').toLowerCase() != 'workout') continue;
      final String externalUuid = raw['uuid'] as String? ?? '';
      if (externalUuid.isEmpty) continue;
      final Map<String, Object?>? workout =
          await _database.findWorkoutFactRowByExternalId(
        athleteProfileId: batch.athleteId,
        sourceBundleId: raw['sourceBundleId'] as String? ?? '',
        externalUuid: externalUuid,
      );
      final String? workoutId = workout?['id'] as String?;
      if (workoutId == null || !analyzedWorkoutIds.add(workoutId)) continue;
      final WorkoutAnalysisOutcome outcome = await analyzeWorkout(
        athleteProfileId: batch.athleteId,
        workoutId: workoutId,
      );
      affectedDays.add(outcome.occurredOn);
    }
    final List<StructuredSourceReference> invalidatedSources =
        applyResult.invalidatedSources.isNotEmpty
            ? applyResult.invalidatedSources
            : applyResult.invalidatedSourceIds
                .map(
                  (String sourceId) =>
                      StructuredSourceReference('workouts', sourceId),
                )
                .toList(growable: false);
    for (final StructuredSourceReference source in invalidatedSources) {
      final String sourceId = source.sourceId;
      if (source.sourceType != 'workouts') {
        final DateTime? localDate = _optionalDate(source.localDate);
        if (localDate != null) affectedDays.add(localDate);
        continue;
      }
      final Map<String, Object?>? workout = await _database.readWorkoutFactRow(
        athleteProfileId: batch.athleteId,
        workoutId: sourceId,
      );
      if (workout != null) {
        if (workout['source_deleted_at'] == null &&
            analyzedWorkoutIds.add(sourceId)) {
          final WorkoutAnalysisOutcome outcome = await analyzeWorkout(
            athleteProfileId: batch.athleteId,
            workoutId: sourceId,
          );
          affectedDays.add(outcome.occurredOn);
        } else {
          affectedDays.add(
            _localDate(
              workout,
              _requiredDate(workout['started_at_utc'], '训练开始时间'),
            ),
          );
        }
      }
    }
    for (final Map<String, Object?> raw in batch.upserts) {
      if ((raw['kind'] as String? ?? '').toLowerCase() == 'workout') continue;
      final DateTime? observedAt = _optionalDate(raw['startTime']);
      if (observedAt != null) affectedDays.add(observedAt.toLocal());
    }
    if (affectedDays.isEmpty) affectedDays.add(batch.createdAt.toLocal());

    final Set<String> completed = <String>{};
    final Set<MetricPeriodWindow> affectedPeriods = <MetricPeriodWindow>{};
    for (final DateTime day in affectedDays) {
      final DateTime week = _periodStart(MetricPeriod.week, day);
      affectedPeriods.add(
        MetricPeriodWindow(period: MetricPeriod.week, periodStart: week),
      );
      final String weekKey = 'week:${_dateKey(week)}';
      if (completed.add(weekKey)) {
        await aggregatePeriod(
          athleteProfileId: batch.athleteId,
          period: MetricPeriod.week,
          periodStart: week,
        );
      }
      final DateTime month = _periodStart(MetricPeriod.month, day);
      affectedPeriods.add(
        MetricPeriodWindow(period: MetricPeriod.month, periodStart: month),
      );
      final String monthKey = 'month:${_dateKey(month)}';
      if (completed.add(monthKey)) {
        await aggregatePeriod(
          athleteProfileId: batch.athleteId,
          period: MetricPeriod.month,
          periodStart: month,
        );
      }
    }
    return HealthBatchMetricsResult(
      affectedPeriods: List<MetricPeriodWindow>.unmodifiable(affectedPeriods),
      analyzedWorkoutIds:
          List<String>.unmodifiable(analyzedWorkoutIds.toList()..sort()),
    );
  }

  Future<List<MetricAggregate>> _aggregateWeeklyRunningMetrics({
    required String athleteProfileId,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required List<_StoredWorkoutAnalysis> runs,
    required List<_StoredWorkoutAnalysis> periodRuns,
    required DateTime computedAt,
    required DateTime asOf,
  }) async {
    final List<SteadyPaceSegment> historicalSegments = runs
        .expand((_StoredWorkoutAnalysis item) => item.steadySegments)
        .toList(growable: false);
    final List<PaceObservation> paceObservations = historicalSegments
        .where((SteadyPaceSegment item) => !item.occurredAt.isAfter(asOf))
        .map(
          (SteadyPaceSegment item) => PaceObservation(
            sourceWorkoutId: item.sourceWorkoutId,
            occurredAt: item.occurredAt,
            paceSecondsPerKm: item.paceSecondsPerKm,
            durationSeconds: item.durationSeconds,
            isAerobic: item.isAerobic,
          ),
        )
        .toList(growable: false);
    final List<MetricAggregate> historicalMetrics =
        await _repository.listAggregates(
      athleteProfileId: athleteProfileId,
      includeInvalidated: false,
    );
    final List<MetricAggregate> previousBands = historicalMetrics
        .where((MetricAggregate item) =>
            item.metricCode == 'pace_reference_band' &&
            item.status == MetricStatus.ready)
        .toList()
      ..sort((MetricAggregate first, MetricAggregate second) =>
          second.computedAt.compareTo(first.computedAt));
    final List<PaceReferenceBand> validPreviousBands = previousBands
        .map(_bandFromMetric)
        .whereType<PaceReferenceBand>()
        .where(
          (PaceReferenceBand band) =>
              !band.frozenAt.isAfter(asOf) && asOf.isBefore(band.expiresAt),
        )
        .toList()
      ..sort(
        (PaceReferenceBand first, PaceReferenceBand second) =>
            second.frozenAt.compareTo(first.frozenAt),
      );
    final PaceReferenceBand? existingBand =
        validPreviousBands.isEmpty ? null : validPreviousBands.first;
    final PaceReferenceBand band = _engine.buildPaceReferenceBand(
      observations: paceObservations,
      now: asOf,
      existing: existingBand,
    );
    final List<MetricAggregate> saved = <MetricAggregate>[];
    final MetricAggregate bandMetric = MetricAggregate(
      id: _metricId(
        athleteProfileId,
        'pace_reference_band',
        'none',
        MetricPeriod.week,
        periodStart,
      ),
      athleteProfileId: athleteProfileId,
      metricCode: 'pace_reference_band',
      period: MetricPeriod.week,
      periodStart: periodStart,
      value: band.centerSecondsPerKm,
      unit: 's/km',
      sampleCount: band.sampleCount,
      sampleDurationSeconds: paceObservations.fold<int>(
        0,
        (int value, PaceObservation item) => value + item.durationSeconds,
      ),
      coverage: band.status == MetricStatus.ready ? 1 : 0,
      status: band.status,
      algorithmVersion: 'trainmate-pace-band-v1',
      inputFingerprint: _fingerprint(
        paceObservations.map(
          (PaceObservation item) =>
              '${item.sourceWorkoutId}:${item.occurredAt.toUtc().microsecondsSinceEpoch}:${item.paceSecondsPerKm}:${item.durationSeconds}:${item.isAerobic}',
        ),
      ),
      computedAt: computedAt,
      metadata: <String, Object?>{
        'lowerSecondsPerKm': band.lowerSecondsPerKm,
        'upperSecondsPerKm': band.upperSecondsPerKm,
        'frozenAt': band.frozenAt.toUtc().toIso8601String(),
        'expiresAt': band.expiresAt.toUtc().toIso8601String(),
        'bandVersion': band.version,
        'remainingSamples': band.remainingSamples,
        'timeZoneName': _periodTimeZone(periodRuns),
      },
    );
    await _saveMetric(bandMetric, runs);
    saved.add(bandMetric);

    final List<SteadyPaceSegment> currentSegments = periodRuns
        .expand((_StoredWorkoutAnalysis item) => item.steadySegments)
        .toList(growable: false);
    final L2MetricResult samePace = _engine.calculateSamePaceHeartRate(
      segments: currentSegments,
      band: band,
    );
    final L2MetricResult efficiency =
        _engine.calculateRunningEfficiencyFactor(segments: currentSegments);
    final AerobicDecouplingResult aerobicDecoupling =
        _engine.calculateAerobicDecoupling(segments: currentSegments);
    for (final ({String code, L2MetricResult result}) item in <({
      String code,
      L2MetricResult result,
    })>[
      (code: 'same_pace_heart_rate', result: samePace),
      (code: 'running_efficiency_factor', result: efficiency),
    ]) {
      final double? baselineValue = item.code == 'same_pace_heart_rate'
          ? _latestComparableBaseline(
              metrics: historicalMetrics,
              metricCode: item.code,
              beforePeriodStart: periodStart,
              bandVersion: band.version,
            )
          : null;
      final MetricAggregate metric = MetricAggregate(
        id: _metricId(
          athleteProfileId,
          item.code,
          'none',
          MetricPeriod.week,
          periodStart,
        ),
        athleteProfileId: athleteProfileId,
        metricCode: item.code,
        period: MetricPeriod.week,
        periodStart: periodStart,
        value: item.result.value,
        unit: item.result.unit,
        sampleCount: currentSegments.length,
        sampleDurationSeconds: item.result.validDurationSeconds,
        coverage: item.result.validDurationSeconds <= 0
            ? 0
            : (item.result.validDurationSeconds / 1200).clamp(0, 1).toDouble(),
        status: item.result.status,
        baselineValue: baselineValue,
        algorithmVersion: 'trainmate-l2-running-v1',
        inputFingerprint: _fingerprint(
          currentSegments.map(
            (SteadyPaceSegment segment) =>
                '${segment.sourceWorkoutId}:${segment.occurredAt.toUtc().microsecondsSinceEpoch}:${segment.durationSeconds}:${segment.paceSecondsPerKm}:${segment.averageHeartRate}:${segment.heartRateCoverage}',
          ),
        ),
        computedAt: computedAt,
        metadata: <String, Object?>{
          'reason': item.result.reason,
          'remainingDurationSeconds': item.result.remainingDurationSeconds,
          'bandVersion': band.version,
          if (item.code == 'same_pace_heart_rate')
            'interpretationThresholdBpm': 2,
          if (item.code == 'same_pace_heart_rate')
            'interpretation': 'product_threshold_not_physiological',
          'timeZoneName': _periodTimeZone(periodRuns),
        },
      );
      await _saveMetric(metric, periodRuns);
      saved.add(metric);
    }

    final MetricAggregate aerobicDecouplingMetric = MetricAggregate(
      id: _metricId(
        athleteProfileId,
        'aerobic_decoupling',
        'none',
        MetricPeriod.week,
        periodStart,
      ),
      athleteProfileId: athleteProfileId,
      metricCode: 'aerobic_decoupling',
      period: MetricPeriod.week,
      periodStart: periodStart,
      value: aerobicDecoupling.value,
      unit: '%',
      sampleCount: aerobicDecoupling.validSegmentCount,
      sampleDurationSeconds: aerobicDecoupling.validDurationSeconds,
      coverage: aerobicDecoupling.heartRateCoverage,
      status: aerobicDecoupling.status,
      algorithmVersion: TrainingMetricsEngine.aerobicDecouplingAlgorithmVersion,
      inputFingerprint: _fingerprint(
        currentSegments.map(
          (SteadyPaceSegment segment) =>
              '${segment.sourceWorkoutId}:${segment.occurredAt.toUtc().microsecondsSinceEpoch}:${segment.durationSeconds}:${segment.paceSecondsPerKm}:${segment.averageHeartRate}:${segment.heartRateCoverage}:${segment.grade}:${segment.paceCoefficientOfVariation}:${segment.isAerobic}',
        ),
      ),
      computedAt: computedAt,
      metadata: <String, Object?>{
        'reason': aerobicDecoupling.reason,
        'remainingDurationSeconds': aerobicDecoupling.remainingDurationSeconds,
        'comparableDurationSeconds':
            aerobicDecoupling.comparableDurationSeconds,
        'comparableWorkoutCount': aerobicDecoupling.workouts.length,
        'aggregation': 'duration_weighted_within_workout_comparisons',
        'interpretationThresholdPercent':
            TrainingMetricsEngine.aerobicDecouplingInterpretationThresholds,
        'interpretation': 'product_threshold_not_physiological',
        'workouts': aerobicDecoupling.workouts
            .map(
              (AerobicDecouplingWorkoutResult item) => <String, Object?>{
                'sourceWorkoutId': item.sourceWorkoutId,
                'firstHalfEfficiencyFactor': item.firstHalfEfficiencyFactor,
                'secondHalfEfficiencyFactor': item.secondHalfEfficiencyFactor,
                'decouplingPercent': item.decouplingPercent,
                'validDurationSeconds': item.validDurationSeconds,
                'heartRateCoverage': item.heartRateCoverage,
              },
            )
            .toList(growable: false),
        'timeZoneName': _periodTimeZone(periodRuns),
      },
    );
    await _saveMetric(aerobicDecouplingMetric, periodRuns);
    saved.add(aerobicDecouplingMetric);

    final List<VamResult> readyVam = periodRuns
        .map((_StoredWorkoutAnalysis item) => item.vam)
        .whereType<VamResult>()
        .where((VamResult item) => item.status == MetricStatus.ready)
        .toList(growable: false);
    final double? bestVam = readyVam.isEmpty
        ? null
        : readyVam
            .map((VamResult item) => item.metersPerHour!)
            .reduce(math.max);
    final MetricAggregate vamMetric = MetricAggregate(
      id: _metricId(
        athleteProfileId,
        'vam',
        'none',
        MetricPeriod.week,
        periodStart,
      ),
      athleteProfileId: athleteProfileId,
      metricCode: 'vam',
      period: MetricPeriod.week,
      periodStart: periodStart,
      value: bestVam,
      unit: 'm/h',
      sampleCount: readyVam.length,
      sampleDurationSeconds: 0,
      coverage: readyVam.isEmpty ? 0 : 1,
      status: readyVam.isEmpty ? MetricStatus.accumulating : MetricStatus.ready,
      algorithmVersion: 'trainmate-vam-v1',
      inputFingerprint: _fingerprint(
        periodRuns.map((_StoredWorkoutAnalysis item) => item.inputFingerprint),
      ),
      computedAt: computedAt,
      metadata: <String, Object?>{
        'label': readyVam.isEmpty ? '本周无有效爬升段' : '设备记录有效爬升段',
        'timeZoneName': _periodTimeZone(periodRuns),
      },
    );
    await _saveMetric(vamMetric, periodRuns);
    saved.add(vamMetric);

    final List<DeviceBestSegment> deviceSegments = periodRuns
        .map((_StoredWorkoutAnalysis item) => item.deviceBestSegment)
        .whereType<DeviceBestSegment>()
        .toList(growable: false);
    if (deviceSegments.isNotEmpty) {
      deviceSegments.sort(
        (DeviceBestSegment first, DeviceBestSegment second) =>
            (first.durationSeconds / first.distanceMeters).compareTo(
          second.durationSeconds / second.distanceMeters,
        ),
      );
      final DeviceBestSegment best = deviceSegments.first;
      final MetricAggregate bestMetric = MetricAggregate(
        id: _metricId(
          athleteProfileId,
          'device_best_segment',
          'none',
          MetricPeriod.week,
          periodStart,
        ),
        athleteProfileId: athleteProfileId,
        metricCode: 'device_best_segment',
        period: MetricPeriod.week,
        periodStart: periodStart,
        value: best.durationSeconds.toDouble(),
        unit: 's',
        sampleCount: deviceSegments.length,
        sampleDurationSeconds: best.durationSeconds,
        coverage: 1,
        status: MetricStatus.ready,
        algorithmVersion: 'trainmate-device-segment-v1',
        inputFingerprint: _fingerprint(
          deviceSegments.map(
            (DeviceBestSegment item) =>
                '${item.sourceId}:${item.distanceMeters}:${item.durationSeconds}',
          ),
        ),
        computedAt: computedAt,
        metadata: <String, Object?>{
          'displayName': '设备记录最佳分段',
          'distanceMeters': best.distanceMeters,
          'sourceId': best.sourceId,
          'officialRaceConfirmed': false,
          'timeZoneName': _periodTimeZone(periodRuns),
        },
      );
      await _saveMetric(bestMetric, periodRuns);
      saved.add(bestMetric);
    }
    return saved;
  }

  Future<List<MetricAggregate>> _aggregateWeeklyDisciplineMetrics({
    required String athleteProfileId,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required List<_StoredWorkoutAnalysis> runs,
    required List<_StoredWorkoutAnalysis> periodRuns,
    required DateTime computedAt,
  }) async {
    final DateTime historyStart =
        periodStart.subtract(const Duration(days: 56));
    final List<_StoredStrengthSet> strengthSets =
        (await _database.listStrengthSetRows(
      athleteProfileId: athleteProfileId,
      localDateOnOrAfter: _dateKey(historyStart),
      localDateBefore: _dateKey(periodEndExclusive),
    ))
            .map(_storedStrengthSet)
            .whereType<_StoredStrengthSet>()
            .toList(growable: false);
    final List<_PrimaryExercise> primaryExercises =
        (await _database.listAthletePrimaryExerciseRows(
      athleteProfileId: athleteProfileId,
    ))
            .map(_primaryExercise)
            .whereType<_PrimaryExercise>()
            .where((_PrimaryExercise item) => item.isActive)
            .toList(growable: false);
    final List<MetricAggregate> saved = <MetricAggregate>[];

    for (final _PrimaryExercise primary in primaryExercises) {
      final List<_StoredStrengthSet> exerciseSets = strengthSets
          .where((_StoredStrengthSet item) =>
              item.exerciseKey == primary.exerciseKey)
          .toList(growable: false);
      final List<_StoredStrengthSet> currentSets = exerciseSets
          .where((_StoredStrengthSet item) =>
              !item.localDate.isBefore(periodStart) &&
              item.localDate.isBefore(periodEndExclusive))
          .toList(growable: false);
      final List<_StoredStrengthSet> validCurrentSets = currentSets
          .where((_StoredStrengthSet item) => item.e1Rm != null)
          .toList(growable: false);
      final _StoredStrengthSet? bestCurrent =
          _bestStrengthSet(validCurrentSets);
      final List<_StoredWorkoutAnalysis> strengthRuns =
          _runsForStrengthSets(runs, exerciseSets);
      final double? averageRpe = _averageValidRpe(currentSets);
      final String rpeExplanation = averageRpe == null
          ? 'RPE 未记录，不做 RPE 进步结论'
          : '当周有效组次平均 RPE ${averageRpe.toStringAsFixed(1)}';

      final MetricAggregate e1RmMetric = MetricAggregate(
        id: _metricId(
          athleteProfileId,
          'strength_e1rm',
          primary.exerciseKey,
          MetricPeriod.week,
          periodStart,
        ),
        athleteProfileId: athleteProfileId,
        metricCode: 'strength_e1rm',
        period: MetricPeriod.week,
        periodStart: periodStart,
        value: bestCurrent?.e1Rm,
        unit: 'kg',
        sampleCount: validCurrentSets.length,
        sampleDurationSeconds: 0,
        coverage: currentSets.isEmpty
            ? 0
            : (validCurrentSets.length / currentSets.length)
                .clamp(0, 1)
                .toDouble(),
        status: bestCurrent == null
            ? MetricStatus.accumulating
            : MetricStatus.ready,
        algorithmVersion: strengthAlgorithmVersion,
        inputFingerprint: _fingerprint(
          currentSets.map((_StoredStrengthSet item) => item.fingerprint),
        ),
        computedAt: computedAt,
        metadata: <String, Object?>{
          'exerciseKey': primary.exerciseKey,
          'exerciseName': primary.displayName,
          'formula': 'epley_weight_x_1_plus_reps_div_30',
          'validRepetitionRange': '1-12',
          'volumeUsedForProgressConclusion': false,
          'averageRpe': averageRpe,
          'rpeExplanation': rpeExplanation,
          'remainingSamples': bestCurrent == null ? 1 : 0,
          'reason': bestCurrent == null
              ? '本周还需 1 次包含重量和 1–12 次重复的 ${primary.displayName} 有效组次。'
              : '仅按 ${primary.displayName} 同动作解释；全身总容量只作训练量背景。',
          if (bestCurrent != null)
            'displayValue': '${primary.displayName} · '
                '${bestCurrent.e1Rm!.toStringAsFixed(1)} kg e1RM'
                '（${bestCurrent.weightKg!.toStringAsFixed(1)} kg × '
                '${bestCurrent.repetitions!.toStringAsFixed(0)}）；$rpeExplanation',
          'timeZoneName': _periodTimeZone(periodRuns),
        },
      );
      await _savePrimaryExerciseMetric(
        e1RmMetric,
        strengthRuns,
        athleteProfileId: athleteProfileId,
        exerciseKey: primary.exerciseKey,
      );
      saved.add(e1RmMetric);

      final double? referenceWeight = bestCurrent?.weightKg;
      final double? lowerWeight =
          referenceWeight == null ? null : referenceWeight * 0.95;
      final double? upperWeight =
          referenceWeight == null ? null : referenceWeight * 1.05;
      final List<_StoredStrengthSet> comparableHistory = referenceWeight == null
          ? const <_StoredStrengthSet>[]
          : exerciseSets
              .where((_StoredStrengthSet item) =>
                  item.localDate.isBefore(periodStart) &&
                  item.e1Rm != null &&
                  item.weightKg! >= lowerWeight! &&
                  item.weightKg! <= upperWeight!)
              .toList(growable: false);
      final _StoredStrengthSet? bestHistory =
          _bestStrengthSet(comparableHistory);
      final double? progressPercent = bestCurrent == null || bestHistory == null
          ? null
          : (bestCurrent.e1Rm! / bestHistory.e1Rm! - 1) * 100;
      final MetricAggregate progressMetric = MetricAggregate(
        id: _metricId(
          athleteProfileId,
          'strength_progress',
          primary.exerciseKey,
          MetricPeriod.week,
          periodStart,
        ),
        athleteProfileId: athleteProfileId,
        metricCode: 'strength_progress',
        period: MetricPeriod.week,
        periodStart: periodStart,
        value: progressPercent,
        unit: '%',
        sampleCount: validCurrentSets.length + comparableHistory.length,
        sampleDurationSeconds: 0,
        coverage: progressPercent == null ? 0 : 1,
        status: progressPercent == null
            ? MetricStatus.accumulating
            : MetricStatus.ready,
        algorithmVersion: strengthAlgorithmVersion,
        inputFingerprint: _fingerprint(
          <String>[
            ...currentSets.map((_StoredStrengthSet item) => item.fingerprint),
            ...comparableHistory
                .map((_StoredStrengthSet item) => item.fingerprint),
          ],
        ),
        computedAt: computedAt,
        metadata: <String, Object?>{
          'exerciseKey': primary.exerciseKey,
          'exerciseName': primary.displayName,
          'weightBandLowerKg': lowerWeight,
          'weightBandUpperKg': upperWeight,
          'baselineE1RmKg': bestHistory?.e1Rm,
          'currentE1RmKg': bestCurrent?.e1Rm,
          'averageRpe': averageRpe,
          'rpeExplanation': rpeExplanation,
          'volumeUsedForProgressConclusion': false,
          'remainingSamples': progressPercent == null ? 1 : 0,
          'reason': bestCurrent == null
              ? '本周还没有可计算的 ${primary.displayName} e1RM 组次。'
              : bestHistory == null
                  ? '同动作、同重量区间还需 1 次历史对照；不使用全身总容量代替。'
                  : '只比较 ${primary.displayName} 在同重量区间的 e1RM；$rpeExplanation。',
          if (progressPercent != null)
            'displayValue': '${primary.displayName} · 同重量区间 '
                '${lowerWeight!.toStringAsFixed(1)}–${upperWeight!.toStringAsFixed(1)} kg · '
                '${progressPercent >= 0 ? '+' : ''}${progressPercent.toStringAsFixed(1)}%；'
                '$rpeExplanation',
          'timeZoneName': _periodTimeZone(periodRuns),
        },
      );
      await _savePrimaryExerciseMetric(
        progressMetric,
        strengthRuns,
        athleteProfileId: athleteProfileId,
        exerciseKey: primary.exerciseKey,
      );
      saved.add(progressMetric);
    }

    final List<_StoredWorkoutAnalysis> badmintonHistory = runs
        .where((_StoredWorkoutAnalysis item) =>
            item.discipline == WorkoutDiscipline.badminton)
        .toList(growable: false);
    if (badmintonHistory.isNotEmpty) {
      final List<_StoredWorkoutAnalysis> badmintonRuns = periodRuns
          .where((_StoredWorkoutAnalysis item) =>
              item.discipline == WorkoutDiscipline.badminton)
          .toList(growable: false);
      final Map<String, double> loadByMethod = <String, double>{};
      for (final TrainingLoadValue load in badmintonRuns
          .expand((_StoredWorkoutAnalysis item) => item.loads)) {
        loadByMethod.update(
          load.method.code,
          (double value) => value + load.value,
          ifAbsent: () => load.value,
        );
      }
      final int courtDurationSeconds = badmintonRuns.fold<int>(
        0,
        (int total, _StoredWorkoutAnalysis item) =>
            total + item.durationSeconds,
      );
      final String loadSummary = loadByMethod.isEmpty
          ? '负荷口径尚不可用'
          : loadByMethod.entries
              .map((MapEntry<String, double> item) =>
                  '${_loadMethodLabel(item.key)} ${item.value.toStringAsFixed(1)}')
              .join('；');
      final MetricAggregate badmintonMetric = MetricAggregate(
        id: _metricId(
          athleteProfileId,
          'badminton_consistency',
          'descriptive',
          MetricPeriod.week,
          periodStart,
        ),
        athleteProfileId: athleteProfileId,
        metricCode: 'badminton_consistency',
        period: MetricPeriod.week,
        periodStart: periodStart,
        value: badmintonRuns.isEmpty ? null : badmintonRuns.length.toDouble(),
        unit: '次',
        sampleCount: badmintonRuns.length,
        sampleDurationSeconds: courtDurationSeconds,
        coverage: badmintonRuns.isEmpty ? 0 : 1,
        status: badmintonRuns.isEmpty
            ? MetricStatus.accumulating
            : MetricStatus.ready,
        algorithmVersion: badmintonAlgorithmVersion,
        inputFingerprint: _fingerprint(
          badmintonRuns.map(
            (_StoredWorkoutAnalysis item) => item.inputFingerprint,
          ),
        ),
        computedAt: computedAt,
        metadata: <String, Object?>{
          'courtDurationMinutes': courtDurationSeconds / 60,
          'loadByMethod': loadByMethod,
          'remainingSamples': badmintonRuns.isEmpty ? 1 : 0,
          'interpretation': 'descriptive_not_skill_progress',
          'reason': badmintonRuns.isEmpty
              ? '本周还需 1 次羽毛球训练，才能展示一致性、负荷和场上时长。'
              : '羽毛球 v1 只提供训练次数、分口径负荷和场上时长，不生成技术进步结论。',
          if (badmintonRuns.isNotEmpty)
            'displayValue': '本周 ${badmintonRuns.length} 次 · '
                '场上 ${(courtDurationSeconds / 60).round()} 分钟 · '
                '$loadSummary',
          'timeZoneName': _periodTimeZone(periodRuns),
        },
      );
      await _saveMetric(
        badmintonMetric,
        badmintonRuns.isEmpty ? badmintonHistory : badmintonRuns,
      );
      saved.add(badmintonMetric);
    }
    return List<MetricAggregate>.unmodifiable(saved);
  }

  Future<List<MetricAggregate>> _aggregateMonthlyBodyMetrics({
    required String athleteProfileId,
    required DateTime periodStart,
    required DateTime periodEndExclusive,
    required DateTime computedAt,
  }) async {
    final DateTime asOf = periodEndExclusive.isAfter(_clock())
        ? _clock()
        : periodEndExclusive.subtract(const Duration(microseconds: 1));
    final DateTime start = DateTime(asOf.year, asOf.month, asOf.day)
        .subtract(const Duration(days: 6));
    final DateTime asOfDate = DateTime(asOf.year, asOf.month, asOf.day);
    final DateTime queryStart =
        periodStart.isBefore(start) ? periodStart : start;
    final List<Map<String, Object?>> rows =
        await _database.listHealthObservationFactRows(
      athleteProfileId: athleteProfileId,
      observedAtOrAfter: queryStart
          .subtract(const Duration(days: 2))
          .toUtc()
          .toIso8601String(),
      observedBefore:
          asOfDate.add(const Duration(days: 3)).toUtc().toIso8601String(),
    );
    final List<MetricAggregate> saved = <MetricAggregate>[];
    for (final ({
      String code,
      bool Function(String kind) matches,
      String unit
    }) definition in <({
      String code,
      bool Function(String kind) matches,
      String unit,
    })>[
      (
        code: 'body_weight_7d',
        matches: (String kind) => kind.toLowerCase().contains('bodymass'),
        unit: 'kg',
      ),
      (
        code: 'body_fat_7d',
        matches: (String kind) =>
            kind.toLowerCase().contains('bodyfatpercentage'),
        unit: '%',
      ),
    ]) {
      final List<Map<String, Object?>> matching =
          rows.where((Map<String, Object?> row) {
        if (!definition.matches(
          row['observation_kind'] as String? ?? '',
        )) {
          return false;
        }
        final DateTime? localDate = _optionalDate(row['local_date']);
        return localDate != null &&
            !localDate.isBefore(start) &&
            !localDate.isAfter(asOfDate);
      }).toList(growable: false);
      final SevenDayBodyAverageResult average =
          _engine.calculateSevenDayBodyAverage(
        observations: matching.map((Map<String, Object?> row) {
          double value = _finiteNumber(row['value']) ?? 0;
          if (definition.code == 'body_fat_7d' && value > 0 && value <= 1) {
            value *= 100;
          }
          return BodyObservation(
            measuredAt: _requiredDate(row['local_date'], '身体样本本地日期'),
            value: value,
          );
        }).toList(growable: false),
        asOf: asOf,
      );
      final MetricAggregate metric = MetricAggregate(
        id: _metricId(
          athleteProfileId,
          definition.code,
          'none',
          MetricPeriod.month,
          periodStart,
        ),
        athleteProfileId: athleteProfileId,
        metricCode: definition.code,
        period: MetricPeriod.month,
        periodStart: periodStart,
        value: average.average,
        unit: definition.unit,
        sampleCount: matching.length,
        sampleDurationSeconds: 7 * 24 * 60 * 60,
        coverage: (average.validDayCount / 7).clamp(0, 1).toDouble(),
        status: average.status,
        algorithmVersion: 'trainmate-body-7d-v1',
        inputFingerprint: _fingerprint(
          matching.map(
            (Map<String, Object?> row) =>
                '${row['id']}:${row['updated_at']}:${row['value']}',
          ),
        ),
        computedAt: computedAt,
        metadata: <String, Object?>{
          'validDayCount': average.validDayCount,
          'remainingDays': average.remainingDays,
          'visibleSurface': 'monthly_or_explicit',
          'timeZoneName': _rowTimeZone(matching),
        },
      );
      await _repository.saveAggregate(metric);
      for (final Map<String, Object?> row in matching) {
        await _repository.saveLineage(MetricLineage(
          metricId: metric.id,
          sourceType: 'health_observations',
          sourceId: row['id']! as String,
          relationship: 'input',
          createdAt: computedAt,
        ));
      }
      saved.add(metric);
    }

    // HealthKit 的 VO2max 通常是设备估算且采样稀疏。月报只展示本月最新一个
    // 有效日的日中位数，并明确标为观察值，不把单次变化解释为生理进步。
    final List<Map<String, Object?>> vo2Rows = rows.where(
      (Map<String, Object?> row) {
        final String kind =
            (row['observation_kind'] as String? ?? '').toLowerCase();
        final DateTime? localDate = _optionalDate(row['local_date']);
        final double? value = _finiteNumber(row['value']);
        return kind.contains('vo2max') &&
            localDate != null &&
            !localDate.isBefore(periodStart) &&
            !localDate.isAfter(asOfDate) &&
            value != null &&
            value > 0;
      },
    ).toList(growable: false);
    final Map<DateTime, List<double>> vo2ByDay = <DateTime, List<double>>{};
    for (final Map<String, Object?> row in vo2Rows) {
      final DateTime date = _requiredDate(row['local_date'], 'VO2max 本地日期');
      final DateTime day = DateTime(date.year, date.month, date.day);
      vo2ByDay.putIfAbsent(day, () => <double>[]).add(
            _finiteNumber(row['value'])!,
          );
    }
    final List<DateTime> vo2Days = vo2ByDay.keys.toList()..sort();
    final double? latestVo2 = vo2Days.isEmpty
        ? null
        : _median(vo2ByDay[vo2Days.last] ?? const <double>[]);
    final MetricAggregate vo2Metric = MetricAggregate(
      id: _metricId(
        athleteProfileId,
        'vo2max_monthly',
        'none',
        MetricPeriod.month,
        periodStart,
      ),
      athleteProfileId: athleteProfileId,
      metricCode: 'vo2max_monthly',
      period: MetricPeriod.month,
      periodStart: periodStart,
      value: latestVo2,
      unit: 'ml/kg/min',
      sampleCount: vo2Rows.length,
      sampleDurationSeconds: 0,
      coverage: vo2Days.isEmpty ? 0 : 1,
      status: vo2Days.isEmpty ? MetricStatus.accumulating : MetricStatus.ready,
      algorithmVersion: 'trainmate-vo2max-observation-v1',
      inputFingerprint: _fingerprint(
        vo2Rows.map(
          (Map<String, Object?> row) =>
              '${row['id']}:${row['updated_at']}:${row['value']}',
        ),
      ),
      computedAt: computedAt,
      metadata: <String, Object?>{
        'validDayCount': vo2Days.length,
        'remainingSamples': vo2Days.isEmpty ? 1 : 0,
        'aggregation': 'latest_daily_median',
        'interpretation': 'observation_only',
        'visibleSurface': 'monthly_or_explicit',
        'timeZoneName': _rowTimeZone(vo2Rows),
      },
    );
    await _repository.saveAggregate(vo2Metric);
    for (final Map<String, Object?> row in vo2Rows) {
      await _repository.saveLineage(MetricLineage(
        metricId: vo2Metric.id,
        sourceType: 'health_observations',
        sourceId: row['id']! as String,
        relationship: 'input',
        createdAt: computedAt,
      ));
    }
    saved.add(vo2Metric);
    return saved;
  }

  Future<void> _saveMetric(
    MetricAggregate metric,
    List<_StoredWorkoutAnalysis> runs,
  ) async {
    await _repository.saveAggregate(metric);
    for (final _StoredWorkoutAnalysis run in runs) {
      await _repository.saveLineage(MetricLineage(
        metricId: metric.id,
        sourceType: 'workouts',
        sourceId: run.workoutId,
        relationship: 'input',
        createdAt: metric.computedAt,
      ));
    }
  }

  Future<void> _savePrimaryExerciseMetric(
    MetricAggregate metric,
    List<_StoredWorkoutAnalysis> runs, {
    required String athleteProfileId,
    required String exerciseKey,
  }) async {
    await _saveMetric(metric, runs);
    await _repository.saveLineage(MetricLineage(
      metricId: metric.id,
      sourceType: 'athlete_primary_exercises',
      sourceId: '$athleteProfileId:$exerciseKey',
      relationship: 'configuration',
      createdAt: metric.computedAt,
    ));
  }

  _StoredWorkoutAnalysis? _storedAnalysis(Map<String, Object?> row) {
    try {
      final Map<String, Object?> result =
          _decodeObject(row['result_json'], label: '训练分析结果');
      final String workoutId = result['workoutId'] as String? ?? '';
      if (workoutId.isEmpty) return null;
      final DateTime occurredOn =
          DateTime.parse(result['occurredOn']! as String);
      final List<TrainingLoadValue> loads =
          (result['loads'] as List<Object?>? ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map((Map<Object?, Object?> raw) {
        final Map<String, Object?> item = raw.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        );
        return TrainingLoadValue(
          workoutId: workoutId,
          occurredOn: occurredOn,
          method: _loadMethod(item['method'] as String? ?? ''),
          value: _finiteNumber(item['value']) ?? 0,
          durationMinutes: _finiteNumber(item['durationMinutes']) ?? 0,
          estimated: item['estimated'] == true,
          coverage:
              (_finiteNumber(item['coverage']) ?? 0).clamp(0, 1).toDouble(),
          reason: item['reason'] as String? ?? '',
        );
      }).toList(growable: false);
      final List<SteadyPaceSegment> segments =
          (result['steadySegments'] as List<Object?>? ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map((Map<Object?, Object?> raw) {
        final Map<String, Object?> item = raw.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        );
        return SteadyPaceSegment(
          sourceWorkoutId: workoutId,
          occurredAt: _requiredDate(item['occurredAt'], '稳态段时间'),
          durationSeconds: _positiveInt(item['durationSeconds']) ?? 0,
          paceSecondsPerKm: _finiteNumber(item['paceSecondsPerKm']) ?? 0,
          grade: _finiteNumber(item['grade']) ?? 0,
          paceCoefficientOfVariation:
              _finiteNumber(item['paceCoefficientOfVariation']) ?? 1,
          averageHeartRate: _finiteNumber(item['averageHeartRate']) ?? 0,
          heartRateCoverage: _finiteNumber(item['heartRateCoverage']) ?? 0,
          warmupExcluded: item['warmupExcluded'] == true,
          isAerobic: item['isAerobic'] == true,
        );
      }).toList(growable: false);
      final Map<String, Object?> vamJson =
          result['vam'] is Map ? _objectMap(result['vam']! as Map) : const {};
      final VamResult? vam = vamJson.isEmpty
          ? null
          : VamResult(
              status: _metricStatus(vamJson['status'] as String? ?? ''),
              metersPerHour: _finiteNumber(vamJson['metersPerHour']),
              label: vamJson['label'] as String? ?? '',
            );
      final Map<String, Object?> bestJson = result['deviceBestSegment'] is Map
          ? _objectMap(result['deviceBestSegment']! as Map)
          : const {};
      final DeviceBestSegment? best = bestJson.isEmpty
          ? null
          : DeviceBestSegment(
              sourceId: bestJson['sourceId'] as String? ?? workoutId,
              distanceMeters: _finiteNumber(bestJson['distanceMeters']) ?? 0,
              durationSeconds: _positiveInt(bestJson['durationSeconds']) ?? 0,
              isOfficialRaceResult: bestJson['isOfficialRaceResult'] == true,
            );
      return _StoredWorkoutAnalysis(
        workoutId: workoutId,
        occurredOn: occurredOn,
        timeZoneName: result['timeZoneName'] as String? ?? 'UTC',
        inputFingerprint: row['input_fingerprint'] as String? ?? '',
        discipline: _storedDiscipline(result['discipline']),
        durationSeconds: _positiveInt(result['durationSeconds']) ?? 0,
        loads: loads,
        steadySegments: segments,
        vam: vam,
        deviceBestSegment: best,
      );
    } catch (_) {
      return null;
    }
  }

  List<Map<String, Object?>> _latestCurrentAnalysisRows(
    List<Map<String, Object?>> rows,
  ) {
    final Map<String, Map<String, Object?>> latest =
        <String, Map<String, Object?>>{};
    for (final Map<String, Object?> row in rows) {
      if (row['algorithm_version'] != workoutAlgorithmVersion) continue;
      final String workoutId = row['workout_id'] as String? ?? '';
      if (workoutId.isEmpty) continue;
      final Map<String, Object?>? existing = latest[workoutId];
      if (existing == null ||
          _requiredDate(row['completed_at'], '训练分析完成时间').isAfter(
            _requiredDate(existing['completed_at'], '训练分析完成时间'),
          )) {
        latest[workoutId] = row;
      }
    }
    final List<Map<String, Object?>> result = latest.values.toList()
      ..sort(
        (Map<String, Object?> first, Map<String, Object?> second) =>
            (first['workout_id'] as String).compareTo(
          second['workout_id'] as String,
        ),
      );
    return result;
  }

  List<SteadyPaceSegment> _steadySegments({
    required String workoutId,
    required DateTime startedAt,
    required DateTime endedAt,
    required List<HeartRateSample> heartRateSamples,
    required List<GpsSample> gpsSamples,
    required bool isAerobicConfirmed,
  }) =>
      _buildSteadySegments(
        engine: _engine,
        workoutId: workoutId,
        startedAt: startedAt,
        endedAt: endedAt,
        heartRateSamples: heartRateSamples,
        gpsSamples: gpsSamples,
        isAerobicConfirmed: isAerobicConfirmed,
      );

  List<HeartRateSample> _heartRateSamples(Object? value) {
    if (value is! List) return const <HeartRateSample>[];
    final List<HeartRateSample> result = <HeartRateSample>[];
    for (final Object? raw in value) {
      if (raw is! Map) continue;
      final Map<String, Object?> item = _objectMap(raw);
      final DateTime? timestamp = _optionalDate(item['startTime']);
      final double? bpm = _finiteNumber(item['value']);
      if (timestamp != null && bpm != null) {
        result.add(HeartRateSample(timestamp: timestamp, bpm: bpm));
      }
    }
    return result;
  }

  List<GpsSample> _gpsSamples(Object? value) {
    if (value is! List) return const <GpsSample>[];
    final List<GpsSample> result = <GpsSample>[];
    for (final Object? rawRoute in value) {
      if (rawRoute is! Map) continue;
      final Object? locations = rawRoute['locations'];
      if (locations is! List) continue;
      for (final Object? rawLocation in locations) {
        if (rawLocation is! Map) continue;
        final Map<String, Object?> item = _objectMap(rawLocation);
        final DateTime? timestamp = _optionalDate(item['timestamp']);
        final double? latitude = _finiteNumber(item['latitude']);
        final double? longitude = _finiteNumber(item['longitude']);
        final double? horizontal = _finiteNumber(item['horizontalAccuracy']);
        if (timestamp == null ||
            latitude == null ||
            longitude == null ||
            horizontal == null) {
          continue;
        }
        result.add(GpsSample(
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
          horizontalAccuracyMeters: horizontal,
          altitudeMeters: _finiteNumber(item['altitude']),
          verticalAccuracyMeters: _finiteNumber(item['verticalAccuracy']),
        ));
      }
    }
    return result;
  }

  List<double> _validHeartRateValues(
    List<HeartRateSample> samples, {
    required DateTime start,
    required DateTime end,
  }) {
    final List<HeartRateSample> sorted = samples
        .where((HeartRateSample item) =>
            !item.timestamp.isBefore(start) &&
            !item.timestamp.isAfter(end) &&
            item.bpm >= 30 &&
            item.bpm <= 220)
        .toList()
      ..sort((HeartRateSample first, HeartRateSample second) =>
          first.timestamp.compareTo(second.timestamp));
    final List<HeartRateSample> valid = <HeartRateSample>[];
    for (final HeartRateSample item in sorted) {
      if (valid.isNotEmpty) {
        final double seconds =
            item.timestamp.difference(valid.last.timestamp).inMilliseconds /
                1000;
        if (seconds <= 0 || (item.bpm - valid.last.bpm).abs() / seconds > 10) {
          continue;
        }
      }
      valid.add(item);
    }
    return valid
        .map((HeartRateSample item) => item.bpm)
        .toList(growable: false);
  }

  _RouteSummary _routeSummary(List<GpsSample> samples) {
    if (samples.length < 2) return const _RouteSummary.empty();
    double distance = 0;
    double elevationGain = 0;
    double supportedSeconds = 0;
    for (int index = 1; index < samples.length; index += 1) {
      final GpsSample previous = samples[index - 1];
      final GpsSample current = samples[index];
      final double seconds =
          current.timestamp.difference(previous.timestamp).inMilliseconds /
              1000;
      if (seconds <= 0 || seconds > 10) continue;
      final double meters = _haversine(previous, current);
      final double speed = meters / seconds;
      if (meters <= 0 || speed > 12.5) continue;
      distance += meters;
      supportedSeconds += seconds;
      final bool validPreviousAltitude = previous.altitudeMeters != null &&
          previous.verticalAccuracyMeters != null &&
          previous.verticalAccuracyMeters! > 0 &&
          previous.verticalAccuracyMeters! <= 10;
      final bool validCurrentAltitude = current.altitudeMeters != null &&
          current.verticalAccuracyMeters != null &&
          current.verticalAccuracyMeters! > 0 &&
          current.verticalAccuracyMeters! <= 10;
      if (validPreviousAltitude && validCurrentAltitude) {
        final double delta = current.altitudeMeters! - previous.altitudeMeters!;
        if (delta > 0) elevationGain += delta;
      }
    }
    return _RouteSummary(
      distanceMeters: distance,
      elevationGainMeters: elevationGain,
      durationSeconds: supportedSeconds.round(),
      grade: distance <= 0 ? 0 : elevationGain / distance,
    );
  }

  double _haversine(GpsSample first, GpsSample second) {
    const double radius = 6371000;
    final double lat1 = first.latitude * math.pi / 180;
    final double lat2 = second.latitude * math.pi / 180;
    final double dLat = (second.latitude - first.latitude) * math.pi / 180;
    final double dLon = (second.longitude - first.longitude) * math.pi / 180;
    final double value = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return radius *
        2 *
        math.atan2(math.sqrt(value), math.sqrt(math.max(0, 1 - value)));
  }

  PaceReferenceBand? _bandFromMetric(MetricAggregate metric) {
    final DateTime? frozenAt =
        _optionalDate(metric.metadata['frozenAt'] as String?);
    final DateTime? expiresAt =
        _optionalDate(metric.metadata['expiresAt'] as String?);
    final double? lower = _finiteNumber(metric.metadata['lowerSecondsPerKm']);
    final double? upper = _finiteNumber(metric.metadata['upperSecondsPerKm']);
    if (metric.value == null ||
        frozenAt == null ||
        expiresAt == null ||
        lower == null ||
        upper == null) {
      return null;
    }
    return PaceReferenceBand(
      status: metric.status,
      centerSecondsPerKm: metric.value,
      lowerSecondsPerKm: lower,
      upperSecondsPerKm: upper,
      frozenAt: frozenAt,
      expiresAt: expiresAt,
      version: metric.metadata['bandVersion'] as String? ?? '',
      sampleCount: metric.sampleCount,
      remainingSamples: _positiveInt(metric.metadata['remainingSamples']) ?? 0,
    );
  }

  DateTime _localDate(Map<String, Object?> row, DateTime fallback) {
    final String? localDate = row['local_date'] as String?;
    return localDate == null ? fallback.toLocal() : DateTime.parse(localDate);
  }

  String _periodTimeZone(List<_StoredWorkoutAnalysis> runs) {
    final Set<String> names = runs
        .map((_StoredWorkoutAnalysis item) => item.timeZoneName.trim())
        .where((String value) => value.isNotEmpty)
        .toSet();
    if (names.isEmpty) return 'UTC';
    if (names.length == 1) return names.single;
    return 'multiple';
  }

  String _rowTimeZone(List<Map<String, Object?>> rows) {
    final Set<String> names = rows
        .map((Map<String, Object?> row) =>
            (row['time_zone_name'] as String? ?? '').trim())
        .where((String value) => value.isNotEmpty)
        .toSet();
    if (names.isEmpty) return 'UTC';
    if (names.length == 1) return names.single;
    return 'multiple';
  }

  DateTime _periodStart(MetricPeriod period, DateTime value) {
    final DateTime day = DateTime(value.year, value.month, value.day);
    return switch (period) {
      MetricPeriod.week => day.subtract(Duration(days: day.weekday - 1)),
      MetricPeriod.month => DateTime(day.year, day.month),
      _ => day,
    };
  }

  DateTime _periodEndExclusive(MetricPeriod period, DateTime start) =>
      switch (period) {
        MetricPeriod.week => start.add(const Duration(days: 7)),
        MetricPeriod.month => DateTime(start.year, start.month + 1),
        _ => start.add(const Duration(days: 1)),
      };

  String _metricId(
    String athleteProfileId,
    String code,
    String method,
    MetricPeriod period,
    DateTime start,
  ) =>
      'metric:$athleteProfileId:$code:$method:${period.name}:${_dateKey(start)}';
}

class WorkoutAnalysisOutcome {
  const WorkoutAnalysisOutcome({
    required this.athleteProfileId,
    required this.workoutId,
    required this.occurredOn,
    required this.inputFingerprint,
    required this.loads,
    required this.steadySegments,
    required this.vam,
    required this.deviceBestSegment,
  });

  final String athleteProfileId;
  final String workoutId;
  final DateTime occurredOn;
  final String inputFingerprint;
  final List<TrainingLoadValue> loads;
  final List<SteadyPaceSegment> steadySegments;
  final VamResult vam;
  final DeviceBestSegment? deviceBestSegment;
}

class MetricPeriodWindow {
  const MetricPeriodWindow({required this.period, required this.periodStart});

  final MetricPeriod period;
  final DateTime periodStart;

  @override
  bool operator ==(Object other) =>
      other is MetricPeriodWindow &&
      other.period == period &&
      other.periodStart.year == periodStart.year &&
      other.periodStart.month == periodStart.month &&
      other.periodStart.day == periodStart.day;

  @override
  int get hashCode => Object.hash(
        period,
        periodStart.year,
        periodStart.month,
        periodStart.day,
      );
}

class HealthBatchMetricsResult {
  const HealthBatchMetricsResult({
    required this.affectedPeriods,
    required this.analyzedWorkoutIds,
  });

  final List<MetricPeriodWindow> affectedPeriods;
  final List<String> analyzedWorkoutIds;
}

_PrimaryExercise? _primaryExercise(Map<String, Object?> row) {
  final String exerciseKey = (row['exercise_key'] as String? ?? '').trim();
  final String displayName = (row['display_name'] as String? ?? '').trim();
  if (exerciseKey.isEmpty || displayName.isEmpty) return null;
  final Object? rawActive = row['is_active'];
  return _PrimaryExercise(
    exerciseKey: exerciseKey,
    displayName: displayName,
    isActive: rawActive == true || rawActive == 1,
  );
}

_StoredStrengthSet? _storedStrengthSet(Map<String, Object?> row) {
  final String id = (row['id'] as String? ?? '').trim();
  final String workoutId = (row['workout_id'] as String? ?? '').trim();
  final String exerciseKey = (row['exercise_key'] as String? ?? '').trim();
  final String exerciseName = (row['exercise_name'] as String? ?? '').trim();
  final DateTime? localDate = _optionalDate(row['local_date']);
  if (id.isEmpty ||
      workoutId.isEmpty ||
      exerciseKey.isEmpty ||
      exerciseName.isEmpty ||
      localDate == null) {
    return null;
  }
  return _StoredStrengthSet(
    id: id,
    workoutId: workoutId,
    exerciseKey: exerciseKey,
    exerciseName: exerciseName,
    localDate: DateTime(localDate.year, localDate.month, localDate.day),
    repetitions: _finiteNumber(row['repetitions']),
    weightKg: _finiteNumber(row['weight_kg']),
    rpe: _finiteNumber(row['rpe']),
  );
}

_StoredStrengthSet? _bestStrengthSet(List<_StoredStrengthSet> values) {
  _StoredStrengthSet? best;
  for (final _StoredStrengthSet value in values) {
    final double? estimate = value.e1Rm;
    if (estimate == null) continue;
    final double? bestEstimate = best?.e1Rm;
    if (bestEstimate == null ||
        estimate > bestEstimate ||
        (estimate == bestEstimate &&
            value.localDate.isAfter(best!.localDate))) {
      best = value;
    }
  }
  return best;
}

double? _averageValidRpe(List<_StoredStrengthSet> values) {
  final List<double> rpes = values
      .map((_StoredStrengthSet item) => item.rpe)
      .whereType<double>()
      .where((double value) => value >= 1 && value <= 10)
      .toList(growable: false);
  if (rpes.isEmpty) return null;
  return rpes.reduce((double first, double second) => first + second) /
      rpes.length;
}

List<_StoredWorkoutAnalysis> _runsForStrengthSets(
  List<_StoredWorkoutAnalysis> runs,
  List<_StoredStrengthSet> sets,
) {
  final Set<String> workoutIds =
      sets.map((_StoredStrengthSet item) => item.workoutId).toSet();
  return runs
      .where(
          (_StoredWorkoutAnalysis item) => workoutIds.contains(item.workoutId))
      .toList(growable: false);
}

WorkoutDiscipline _storedDiscipline(Object? value) {
  final String name = value as String? ?? '';
  for (final WorkoutDiscipline discipline in WorkoutDiscipline.values) {
    if (discipline.name == name) return discipline;
  }
  return WorkoutDiscipline.other;
}

String _loadMethodLabel(String code) => switch (code) {
      'banister_trimp' => 'Banister TRIMP',
      'session_rpe' => 'session-RPE',
      'duration_estimate' => '时长估算',
      _ => code,
    };

class _PrimaryExercise {
  const _PrimaryExercise({
    required this.exerciseKey,
    required this.displayName,
    required this.isActive,
  });

  final String exerciseKey;
  final String displayName;
  final bool isActive;
}

class _StoredStrengthSet {
  const _StoredStrengthSet({
    required this.id,
    required this.workoutId,
    required this.exerciseKey,
    required this.exerciseName,
    required this.localDate,
    required this.repetitions,
    required this.weightKg,
    required this.rpe,
  });

  final String id;
  final String workoutId;
  final String exerciseKey;
  final String exerciseName;
  final DateTime localDate;
  final double? repetitions;
  final double? weightKg;
  final double? rpe;

  double? get e1Rm {
    final double? weight = weightKg;
    final double? reps = repetitions;
    if (weight == null ||
        reps == null ||
        !weight.isFinite ||
        !reps.isFinite ||
        weight <= 0 ||
        reps < 1 ||
        reps > 12) {
      return null;
    }
    return weight * (1 + reps / 30);
  }

  String get fingerprint =>
      '$id:$workoutId:$exerciseKey:${_dateKey(localDate)}:'
      '$weightKg:$repetitions:$rpe';
}

class _StoredWorkoutAnalysis {
  const _StoredWorkoutAnalysis({
    required this.workoutId,
    required this.occurredOn,
    required this.timeZoneName,
    required this.inputFingerprint,
    required this.discipline,
    required this.durationSeconds,
    required this.loads,
    required this.steadySegments,
    required this.vam,
    required this.deviceBestSegment,
  });

  final String workoutId;
  final DateTime occurredOn;
  final String timeZoneName;
  final String inputFingerprint;
  final WorkoutDiscipline discipline;
  final int durationSeconds;
  final List<TrainingLoadValue> loads;
  final List<SteadyPaceSegment> steadySegments;
  final VamResult? vam;
  final DeviceBestSegment? deviceBestSegment;
}

class _RouteSummary {
  const _RouteSummary({
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.durationSeconds,
    required this.grade,
  });

  const _RouteSummary.empty()
      : distanceMeters = 0,
        elevationGainMeters = 0,
        durationSeconds = 0,
        grade = 0;

  final double distanceMeters;
  final double elevationGainMeters;
  final int durationSeconds;
  final double grade;
}

class _ProcessedRawWorkout {
  const _ProcessedRawWorkout({
    required this.hasHeartRateSamples,
    required this.rawHeartRateSampleCount,
    required this.rejectedHeartRateSampleCount,
    required this.heartRateCoverage,
    required this.averageHeartRate,
    required this.maximumHeartRate,
    required this.rawGpsPointCount,
    required this.validGpsPointCount,
    required this.route,
    required this.steadySegments,
    required this.rawSampleFingerprint,
    required this.usedBackgroundIsolate,
  });

  final bool hasHeartRateSamples;
  final int rawHeartRateSampleCount;
  final int rejectedHeartRateSampleCount;
  final double heartRateCoverage;
  final double? averageHeartRate;
  final double? maximumHeartRate;
  final int rawGpsPointCount;
  final int validGpsPointCount;
  final _RouteSummary route;
  final List<SteadyPaceSegment> steadySegments;
  final String rawSampleFingerprint;
  final bool usedBackgroundIsolate;

  _ProcessedRawWorkout withBackgroundIsolate() => _ProcessedRawWorkout(
        hasHeartRateSamples: hasHeartRateSamples,
        rawHeartRateSampleCount: rawHeartRateSampleCount,
        rejectedHeartRateSampleCount: rejectedHeartRateSampleCount,
        heartRateCoverage: heartRateCoverage,
        averageHeartRate: averageHeartRate,
        maximumHeartRate: maximumHeartRate,
        rawGpsPointCount: rawGpsPointCount,
        validGpsPointCount: validGpsPointCount,
        route: route,
        steadySegments: steadySegments,
        rawSampleFingerprint: rawSampleFingerprint,
        usedBackgroundIsolate: true,
      );
}

int _rawSampleCount(Map<String, Object?> details) {
  int count = details['heartRateSamples'] is List
      ? (details['heartRateSamples']! as List).length
      : 0;
  final Object? routes = details['routes'];
  if (routes is List) {
    for (final Object? route in routes) {
      if (route is Map && route['locations'] is List) {
        count += (route['locations']! as List).length;
      }
    }
  }
  return count;
}

_ProcessedRawWorkout _processRawWorkoutInBackground({
  required Map<String, Object?> details,
  required String workoutId,
  required DateTime startedAt,
  required DateTime endedAt,
  required bool isAerobicConfirmed,
}) {
  final TrainingMetricsEngine engine = TrainingMetricsEngine();
  final List<HeartRateSample> heartRateSamples =
      _backgroundHeartRateSamples(details['heartRateSamples']);
  final HeartRateProcessingResult? processedHeartRate = heartRateSamples.isEmpty
      ? null
      : engine.processHeartRateSamples(
          samples: heartRateSamples,
          start: startedAt,
          end: endedAt,
        );
  final List<double> validHeartRates = _backgroundValidHeartRateValues(
    heartRateSamples,
    start: startedAt,
    end: endedAt,
  );
  final List<GpsSample> rawGps = _backgroundGpsSamples(details['routes']);
  final List<GpsSample> validGps = engine.filterGpsSamples(rawGps);
  return _ProcessedRawWorkout(
    hasHeartRateSamples: heartRateSamples.isNotEmpty,
    rawHeartRateSampleCount: processedHeartRate?.rawSampleCount ?? 0,
    rejectedHeartRateSampleCount: processedHeartRate?.rejectedSampleCount ?? 0,
    heartRateCoverage: processedHeartRate?.rawCoverage ?? 0,
    averageHeartRate: validHeartRates.isEmpty
        ? null
        : validHeartRates.reduce((double a, double b) => a + b) /
            validHeartRates.length,
    maximumHeartRate:
        validHeartRates.isEmpty ? null : validHeartRates.reduce(math.max),
    rawGpsPointCount: rawGps.length,
    validGpsPointCount: validGps.length,
    route: _backgroundRouteSummary(validGps),
    steadySegments: _backgroundSteadySegments(
      engine: engine,
      workoutId: workoutId,
      startedAt: startedAt,
      endedAt: endedAt,
      heartRateSamples: heartRateSamples,
      gpsSamples: validGps,
      isAerobicConfirmed: isAerobicConfirmed,
    ),
    rawSampleFingerprint: _rawSampleFingerprint(heartRateSamples, validGps),
    usedBackgroundIsolate: false,
  );
}

List<HeartRateSample> _backgroundHeartRateSamples(Object? value) {
  if (value is! List) return const <HeartRateSample>[];
  final List<HeartRateSample> result = <HeartRateSample>[];
  for (final Object? raw in value) {
    if (raw is! Map) continue;
    final Map<String, Object?> item = _objectMap(raw);
    final DateTime? timestamp = _optionalDate(item['startTime']);
    final double? bpm = _finiteNumber(item['value']);
    if (timestamp != null && bpm != null) {
      result.add(HeartRateSample(timestamp: timestamp, bpm: bpm));
    }
  }
  return result;
}

List<GpsSample> _backgroundGpsSamples(Object? value) {
  if (value is! List) return const <GpsSample>[];
  final List<GpsSample> result = <GpsSample>[];
  for (final Object? rawRoute in value) {
    if (rawRoute is! Map || rawRoute['locations'] is! List) continue;
    for (final Object? rawLocation in rawRoute['locations']! as List) {
      if (rawLocation is! Map) continue;
      final Map<String, Object?> item = _objectMap(rawLocation);
      final DateTime? timestamp = _optionalDate(item['timestamp']);
      final double? latitude = _finiteNumber(item['latitude']);
      final double? longitude = _finiteNumber(item['longitude']);
      final double? horizontal = _finiteNumber(item['horizontalAccuracy']);
      if (timestamp == null ||
          latitude == null ||
          longitude == null ||
          horizontal == null) {
        continue;
      }
      result.add(GpsSample(
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        horizontalAccuracyMeters: horizontal,
        altitudeMeters: _finiteNumber(item['altitude']),
        verticalAccuracyMeters: _finiteNumber(item['verticalAccuracy']),
      ));
    }
  }
  return result;
}

List<double> _backgroundValidHeartRateValues(
  List<HeartRateSample> samples, {
  required DateTime start,
  required DateTime end,
}) {
  final List<HeartRateSample> sorted = samples
      .where((HeartRateSample item) =>
          !item.timestamp.isBefore(start) &&
          !item.timestamp.isAfter(end) &&
          item.bpm >= 30 &&
          item.bpm <= 220)
      .toList()
    ..sort((HeartRateSample first, HeartRateSample second) =>
        first.timestamp.compareTo(second.timestamp));
  final List<HeartRateSample> valid = <HeartRateSample>[];
  for (final HeartRateSample item in sorted) {
    if (valid.isNotEmpty) {
      final double seconds =
          item.timestamp.difference(valid.last.timestamp).inMilliseconds / 1000;
      if (seconds <= 0 || (item.bpm - valid.last.bpm).abs() / seconds > 10) {
        continue;
      }
    }
    valid.add(item);
  }
  return valid.map((HeartRateSample item) => item.bpm).toList(growable: false);
}

List<SteadyPaceSegment> _backgroundSteadySegments({
  required TrainingMetricsEngine engine,
  required String workoutId,
  required DateTime startedAt,
  required DateTime endedAt,
  required List<HeartRateSample> heartRateSamples,
  required List<GpsSample> gpsSamples,
  required bool isAerobicConfirmed,
}) =>
    _buildSteadySegments(
      engine: engine,
      workoutId: workoutId,
      startedAt: startedAt,
      endedAt: endedAt,
      heartRateSamples: heartRateSamples,
      gpsSamples: gpsSamples,
      isAerobicConfirmed: isAerobicConfirmed,
    );

List<SteadyPaceSegment> _buildSteadySegments({
  required TrainingMetricsEngine engine,
  required String workoutId,
  required DateTime startedAt,
  required DateTime endedAt,
  required List<HeartRateSample> heartRateSamples,
  required List<GpsSample> gpsSamples,
  required bool isAerobicConfirmed,
}) {
  if (endedAt.difference(startedAt).inSeconds < 14 * 60 ||
      gpsSamples.length < 2) {
    return const <SteadyPaceSegment>[];
  }
  final DateTime steadyStart = startedAt.add(const Duration(minutes: 10));
  final List<GpsSample> afterWarmup = gpsSamples
      .where((GpsSample item) => !item.timestamp.isBefore(steadyStart))
      .toList(growable: false);
  if (afterWarmup.length < 2) return const <SteadyPaceSegment>[];

  final List<List<GpsSample>> continuousGroups = <List<GpsSample>>[];
  List<GpsSample> currentGroup = <GpsSample>[];
  for (final GpsSample sample in afterWarmup) {
    if (currentGroup.isNotEmpty &&
        sample.timestamp.difference(currentGroup.last.timestamp).inSeconds >
            30) {
      if (currentGroup.length >= 2) continuousGroups.add(currentGroup);
      currentGroup = <GpsSample>[];
    }
    currentGroup.add(sample);
  }
  if (currentGroup.length >= 2) continuousGroups.add(currentGroup);

  final List<SteadyPaceSegment> result = <SteadyPaceSegment>[];
  for (final List<GpsSample> group in continuousGroups) {
    // 五分钟窗口保留边界点，既不重复计算区间，也能比较同一训练前后变化。
    List<GpsSample> chunk = <GpsSample>[group.first];
    DateTime chunkStart = group.first.timestamp;
    for (int index = 1; index < group.length; index += 1) {
      final GpsSample sample = group[index];
      chunk.add(sample);
      if (sample.timestamp.difference(chunkStart).inSeconds >= 300) {
        result.addAll(
          _buildSteadySegmentChunk(
            engine: engine,
            workoutId: workoutId,
            gpsSamples: chunk,
            heartRateSamples: heartRateSamples,
            isAerobicConfirmed: isAerobicConfirmed,
          ),
        );
        chunk = <GpsSample>[sample];
        chunkStart = sample.timestamp;
      }
    }
    if (chunk.length >= 2) {
      result.addAll(
        _buildSteadySegmentChunk(
          engine: engine,
          workoutId: workoutId,
          gpsSamples: chunk,
          heartRateSamples: heartRateSamples,
          isAerobicConfirmed: isAerobicConfirmed,
        ),
      );
    }
  }
  return List<SteadyPaceSegment>.unmodifiable(result);
}

List<SteadyPaceSegment> _buildSteadySegmentChunk({
  required TrainingMetricsEngine engine,
  required String workoutId,
  required List<GpsSample> gpsSamples,
  required List<HeartRateSample> heartRateSamples,
  required bool isAerobicConfirmed,
}) {
  final List<double> speeds = <double>[];
  double distance = 0;
  double supportedSeconds = 0;
  for (int index = 1; index < gpsSamples.length; index += 1) {
    final double seconds = gpsSamples[index]
            .timestamp
            .difference(gpsSamples[index - 1].timestamp)
            .inMilliseconds /
        1000;
    // 10–30 秒保持缺失；超过 30 秒已在上层切段。
    if (seconds <= 0 || seconds > 10) continue;
    final double meters =
        _backgroundHaversine(gpsSamples[index - 1], gpsSamples[index]);
    if (meters <= 0) continue;
    final double speed = meters / seconds;
    if (speed > 0 && speed <= 12.5) {
      speeds.add(speed);
      distance += meters;
      supportedSeconds += seconds;
    }
  }
  if (speeds.isEmpty || distance <= 0 || supportedSeconds <= 0) {
    return const <SteadyPaceSegment>[];
  }
  final double meanSpeed = distance / supportedSeconds;
  final double variance = speeds.fold<double>(
        0,
        (double sum, double value) =>
            sum + math.pow(value - meanSpeed, 2).toDouble(),
      ) /
      speeds.length;
  final double coefficientOfVariation =
      meanSpeed <= 0 ? 1 : math.sqrt(variance) / meanSpeed;
  final int duration = supportedSeconds.round();
  if (duration < 240) return const <SteadyPaceSegment>[];
  final HeartRateProcessingResult heartRate = engine.processHeartRateSamples(
    samples: heartRateSamples,
    start: gpsSamples.first.timestamp,
    end: gpsSamples.last.timestamp,
  );
  final List<double> heartRates = heartRate.points
      .map((HeartRateGridPoint item) => item.bpm)
      .whereType<double>()
      .toList(growable: false);
  if (heartRates.isEmpty) return const <SteadyPaceSegment>[];
  return <SteadyPaceSegment>[
    SteadyPaceSegment(
      sourceWorkoutId: workoutId,
      occurredAt: gpsSamples.first.timestamp,
      durationSeconds: duration,
      paceSecondsPerKm: 1000 / meanSpeed,
      grade: _backgroundRouteSummary(gpsSamples).grade,
      paceCoefficientOfVariation: coefficientOfVariation,
      averageHeartRate:
          heartRates.reduce((double a, double b) => a + b) / heartRates.length,
      heartRateCoverage: heartRate.rawCoverage,
      warmupExcluded: true,
      isAerobic: isAerobicConfirmed,
    ),
  ];
}

_RouteSummary _backgroundRouteSummary(List<GpsSample> samples) {
  if (samples.length < 2) return const _RouteSummary.empty();
  double distance = 0;
  double elevationGain = 0;
  double supportedSeconds = 0;
  for (int index = 1; index < samples.length; index += 1) {
    final GpsSample previous = samples[index - 1];
    final GpsSample current = samples[index];
    final double seconds =
        current.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (seconds <= 0 || seconds > 10) continue;
    final double meters = _backgroundHaversine(previous, current);
    if (meters <= 0 || meters / seconds > 12.5) continue;
    distance += meters;
    supportedSeconds += seconds;
    final bool validPreviousAltitude = previous.altitudeMeters != null &&
        previous.verticalAccuracyMeters != null &&
        previous.verticalAccuracyMeters! > 0 &&
        previous.verticalAccuracyMeters! <= 10;
    final bool validCurrentAltitude = current.altitudeMeters != null &&
        current.verticalAccuracyMeters != null &&
        current.verticalAccuracyMeters! > 0 &&
        current.verticalAccuracyMeters! <= 10;
    if (validPreviousAltitude && validCurrentAltitude) {
      final double delta = current.altitudeMeters! - previous.altitudeMeters!;
      if (delta > 0) elevationGain += delta;
    }
  }
  return _RouteSummary(
    distanceMeters: distance,
    elevationGainMeters: elevationGain,
    durationSeconds: supportedSeconds.round(),
    grade: distance <= 0 ? 0 : elevationGain / distance,
  );
}

double _backgroundHaversine(GpsSample first, GpsSample second) {
  const double radius = 6371000;
  final double lat1 = first.latitude * math.pi / 180;
  final double lat2 = second.latitude * math.pi / 180;
  final double dLat = (second.latitude - first.latitude) * math.pi / 180;
  final double dLon = (second.longitude - first.longitude) * math.pi / 180;
  final double value = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return radius *
      2 *
      math.atan2(math.sqrt(value), math.sqrt(math.max(0, 1 - value)));
}

String _rawSampleFingerprint(
  List<HeartRateSample> heartRateSamples,
  List<GpsSample> validGps,
) {
  final _FingerprintBuilder builder = _FingerprintBuilder();
  for (final HeartRateSample item in heartRateSamples) {
    builder
      ..add(item.timestamp.toUtc().microsecondsSinceEpoch)
      ..add(item.bpm);
  }
  for (final GpsSample item in validGps) {
    builder
      ..add(item.timestamp.toUtc().microsecondsSinceEpoch)
      ..add(item.latitude)
      ..add(item.longitude)
      ..add(item.horizontalAccuracyMeters)
      ..add(item.altitudeMeters)
      ..add(item.verticalAccuracyMeters);
  }
  return builder.finish();
}

class _BanisterContext {
  const _BanisterContext({
    required this.biologicalSex,
    required this.maxHeartRate,
    required this.restingHeartRate,
  });

  const _BanisterContext.unavailable()
      : biologicalSex = BiologicalSex.unknown,
        maxHeartRate = null,
        restingHeartRate = null;

  final BiologicalSex biologicalSex;
  final double? maxHeartRate;
  final double? restingHeartRate;
}

Map<String, Object?> _decodeObject(Object? value, {required String label}) {
  final Object? decoded = switch (value) {
    String text => jsonDecode(text),
    Map map => map,
    _ => null,
  };
  if (decoded is! Map) throw FormatException('$label不是有效对象。');
  return _objectMap(decoded);
}

Map<String, Object?> _objectMap(Map value) => value.map(
      (Object? key, Object? item) => MapEntry(key.toString(), item),
    );

DateTime _requiredDate(Object? value, String label) {
  final DateTime? parsed = _optionalDate(value);
  if (parsed == null) throw FormatException('$label无效。');
  return parsed;
}

DateTime? _optionalDate(Object? value) => switch (value) {
      DateTime date => date,
      num milliseconds => DateTime.fromMillisecondsSinceEpoch(
          milliseconds.round(),
          isUtc: true,
        ),
      String text => DateTime.tryParse(text),
      _ => null,
    };

double? _finiteNumber(Object? value) {
  if (value is! num) return null;
  final double result = value.toDouble();
  return result.isFinite ? result : null;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final List<double> sorted = values
      .where((double value) => value.isFinite)
      .toList(growable: false)
    ..sort();
  if (sorted.isEmpty) return null;
  final int middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

int? _positiveInt(Object? value) {
  if (value is! num) return null;
  final int result = value.round();
  return result >= 0 ? result : null;
}

WorkoutDiscipline _discipline(
  String? value, {
  String? runContext,
  String? sourceKind,
}) {
  if (runContext?.toLowerCase() == 'trail') return WorkoutDiscipline.trailRun;
  if (runContext?.toLowerCase() == 'road') return WorkoutDiscipline.roadRun;
  final bool isHealthKit =
      sourceKind?.replaceAll('_', '').toLowerCase() == 'healthkit';
  if (isHealthKit &&
      (value?.replaceAll('_', '').toLowerCase() == 'roadrun' ||
          value?.replaceAll('_', '').toLowerCase() == 'running')) {
    // HealthKit 只有 `.running`。在路线、元数据或用户确认前，不把它猜成公路跑。
    return WorkoutDiscipline.other;
  }
  return switch (value?.replaceAll('_', '').toLowerCase()) {
    'roadrun' || 'running' => WorkoutDiscipline.roadRun,
    'trailrun' => WorkoutDiscipline.trailRun,
    'strength' => WorkoutDiscipline.strength,
    'badminton' => WorkoutDiscipline.badminton,
    'hyrox' => WorkoutDiscipline.hyrox,
    _ => WorkoutDiscipline.other,
  };
}

LoadMethod _loadMethod(String value) => switch (value) {
      'banister_trimp' => LoadMethod.banisterTrimp,
      'session_rpe' => LoadMethod.sessionRpe,
      _ => LoadMethod.durationEstimate,
    };

MetricStatus _metricStatus(String value) => MetricStatus.values.firstWhere(
      (MetricStatus item) => item.name == value,
      orElse: () => MetricStatus.failed,
    );

double? _latestComparableBaseline({
  required List<MetricAggregate> metrics,
  required String metricCode,
  required DateTime beforePeriodStart,
  required String bandVersion,
}) {
  final List<MetricAggregate> comparable = metrics
      .where(
        (MetricAggregate item) =>
            item.metricCode == metricCode &&
            item.status == MetricStatus.ready &&
            item.value != null &&
            item.periodStart.isBefore(beforePeriodStart) &&
            item.metadata['bandVersion'] == bandVersion,
      )
      .toList()
    ..sort(
      (MetricAggregate first, MetricAggregate second) =>
          second.periodStart.compareTo(first.periodStart),
    );
  return comparable.isEmpty ? null : comparable.first.value;
}

String _fingerprint(Iterable<Object?> values) {
  final _FingerprintBuilder builder = _FingerprintBuilder();
  for (final Object? value in values) {
    builder.add(value);
  }
  return builder.finish();
}

/// 逐值计算指纹，避免为百万级采样点构造展开后的巨大临时列表或字符串。
class _FingerprintBuilder {
  // 采用 JS 可精确表示的 31 位滚动指纹；每步最大乘积远小于 2^53，
  // 因而 Dart VM 与 Web 会得到同一结果。
  static const int _offset = 5381;
  static const int _prime = 31;
  static const int _mask = 0x7fffffff;

  int _hash = _offset;
  bool _hasValue = false;

  void add(Object? value) {
    if (_hasValue) _addByte(0x7c);
    for (final int byte in utf8.encode(_stableValue(value))) {
      _addByte(byte);
    }
    _hasValue = true;
  }

  String finish() => _hash.toRadixString(16).padLeft(8, '0');

  void _addByte(int byte) {
    _hash = ((_hash * _prime) + byte) & _mask;
  }
}

String _stableValue(Object? value) => switch (value) {
      null => 'null',
      double number => number.toStringAsPrecision(15),
      DateTime date => date.toUtc().microsecondsSinceEpoch.toString(),
      _ => value.toString(),
    };

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
