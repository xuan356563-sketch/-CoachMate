import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/rhythm_database_gateway.dart';
import '../../../data/local/trainmate_structured_database_gateway.dart';
import '../../../data/models/body_metric.dart';
import '../../../data/models/body_rhythm.dart';
import '../../../data/models/health_snapshot.dart';
import '../../../data/models/training_log.dart';
import '../../../services/rhythm_engine.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../profile/application/health_sync_controller.dart';

final rhythmDatabaseGatewayProvider =
    Provider<RhythmDatabaseGateway?>((Ref ref) => null);

final bodyRhythmControllerProvider =
    AsyncNotifierProvider<BodyRhythmController, BodyRhythmState>(
  BodyRhythmController.new,
  retry: (int _, Object __) => null,
);

class BodyRhythmState {
  const BodyRhythmState({
    required this.snapshot,
    required this.reviewStatus,
    required this.mealRecords,
    required this.weightDates,
    required this.trainingDates,
    required this.statusMessage,
    required this.canPersist,
  });

  final RhythmSnapshot snapshot;
  final ReviewUnlockStatus reviewStatus;
  final List<MealRecord> mealRecords;
  final List<DateTime> weightDates;
  final List<DateTime> trainingDates;
  final String statusMessage;
  final bool canPersist;
}

class BodyRhythmController extends AsyncNotifier<BodyRhythmState> {
  static const RhythmEngine _engine = RhythmEngine();
  static const ReviewEligibilityEngine _reviewEngine =
      ReviewEligibilityEngine();

  late RhythmDatabaseGateway? _rhythmDatabase;
  late TrainMateStructuredDatabaseGateway? _structuredDatabase;

  @override
  Future<BodyRhythmState> build() async {
    _rhythmDatabase = ref.watch(rhythmDatabaseGatewayProvider);
    _structuredDatabase =
        ref.watch(healthSyncStructuredDatabaseGatewayProvider);
    final TrainingMvpState training = ref.watch(trainingMvpProvider);
    final List<HealthSnapshot> healthSnapshots =
        ref.watch(healthSyncControllerProvider).value?.snapshots ??
            const <HealthSnapshot>[];
    return _load(training: training, healthSnapshots: healthSnapshots);
  }

  Future<BodyRhythmState> _load({
    required TrainingMvpState training,
    required List<HealthSnapshot> healthSnapshots,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime weekStart = _weekStart(now);
    final DateTime windowStart = now.subtract(const Duration(days: 29));
    final String athleteId = training.profile.id;
    final String weekKey = _dateKey(weekStart);
    final RhythmDatabaseGateway? rhythmDatabase = _rhythmDatabase;
    if (rhythmDatabase != null) {
      final Map<String, Object?>? existing =
          await rhythmDatabase.readRhythmSnapshot(
        athleteProfileId: athleteId,
        weekStart: weekKey,
      );
      if (existing != null) {
        return _stateFor(
          training: training,
          healthSnapshots: healthSnapshots,
          snapshot: RhythmSnapshot.fromDatabaseRow(existing),
          now: now,
          statusMessage: '本周身体节奏已建立。',
        );
      }
    }

    final List<Map<String, Object?>> observations =
        await _healthObservations(athleteId, windowStart, now);
    final List<Map<String, Object?>> workouts =
        await _workouts(athleteId, windowStart, now);
    final RhythmInput input = _buildInput(
      training: training,
      healthSnapshots: healthSnapshots,
      observations: observations,
      workouts: workouts,
      calculatedOn: now,
    );
    final RhythmCalculation calculation = _engine.calculate(input: input);
    final RhythmSnapshot candidate = RhythmSnapshot(
      id: 'rhythm:$athleteId:$weekKey',
      athleteProfileId: athleteId,
      weekStart: weekStart,
      timeZoneName: now.timeZoneName,
      utcOffsetMinutes: now.timeZoneOffset.inMinutes,
      speed: calculation.speed,
      actualAge: calculation.actualAge,
      stateAge: calculation.stateAge,
      factors: calculation.factors,
      configVersion: _engine.config.version,
      createdAt: now,
    );
    final RhythmSnapshot snapshot;
    if (rhythmDatabase == null) {
      snapshot = candidate;
    } else {
      final Map<String, Object?> persisted =
          await rhythmDatabase.insertRhythmSnapshotIfAbsent(
        candidate.toDatabaseRow(),
      );
      snapshot = RhythmSnapshot.fromDatabaseRow(persisted);
    }
    return _stateFor(
      training: training,
      healthSnapshots: healthSnapshots,
      snapshot: snapshot,
      now: now,
      statusMessage: snapshot.hasBaseline
          ? '本周身体节奏已建立。'
          : '正在积累身体节奏基线。',
    );
  }

  Future<void> saveMeal({
    required MealType mealType,
    required String summary,
  }) async {
    final BodyRhythmState? current = state.value;
    final RhythmDatabaseGateway? database = _rhythmDatabase;
    if (current == null || database == null) {
      throw StateError('当前存储处于恢复模式，暂时无法保存饮食记录。');
    }
    final String normalized = summary.trim();
    if (normalized.isEmpty) {
      throw const FormatException('请填写这一餐实际吃了什么。');
    }
    final DateTime now = DateTime.now();
    final MealRecord record = MealRecord(
      id: 'meal:${current.snapshot.athleteProfileId}:'
          '${now.microsecondsSinceEpoch}',
      athleteProfileId: current.snapshot.athleteProfileId,
      localDate: now,
      mealType: mealType,
      summary: normalized,
      createdAt: now,
    );
    await database.saveMealRecord(record.toDatabaseRow());
    ref.invalidateSelf();
    await future;
  }

  Future<void> revokeMeal(String recordId) async {
    final BodyRhythmState? current = state.value;
    final RhythmDatabaseGateway? database = _rhythmDatabase;
    if (current == null || database == null) return;
    await database.revokeMealRecord(
      athleteProfileId: current.snapshot.athleteProfileId,
      recordId: recordId,
      revokedAt: DateTime.now().toUtc().toIso8601String(),
    );
    ref.invalidateSelf();
    await future;
  }

  Future<BodyRhythmState> _stateFor({
    required TrainingMvpState training,
    required List<HealthSnapshot> healthSnapshots,
    required RhythmSnapshot snapshot,
    required DateTime now,
    required String statusMessage,
  }) async {
    final DateTime start = now.subtract(const Duration(days: 14));
    final List<MealRecord> meals = await _mealRecords(
      snapshot.athleteProfileId,
      start,
      now,
    );
    final Map<String, DateTime> weightDates = <String, DateTime>{
      for (final BodyMetric metric in training.bodyMetrics)
        if (!_dateOnly(metric.measuredAt).isBefore(_dateOnly(start)) &&
            !_dateOnly(metric.measuredAt).isAfter(_dateOnly(now)))
          _dateKey(metric.measuredAt): _dateOnly(metric.measuredAt),
      for (final HealthSnapshot health in healthSnapshots)
        if (health.weightKg != null &&
            !_dateOnly(health.date).isBefore(_dateOnly(start)) &&
            !_dateOnly(health.date).isAfter(_dateOnly(now)))
          _dateKey(health.date): _dateOnly(health.date),
    };
    final Map<String, DateTime> trainingDates = <String, DateTime>{
      for (final TrainingLog log in training.logs)
        if (!_dateOnly(log.createdAt).isBefore(_dateOnly(start)) &&
            !_dateOnly(log.createdAt).isAfter(_dateOnly(now)))
          _dateKey(log.createdAt): _dateOnly(log.createdAt),
    };
    final ReviewUnlockStatus review = _reviewEngine.evaluate(
      input: ReviewEligibilityInput(
        windowEnd: now,
        mealDates: meals.map((MealRecord item) => item.localDate).toList(),
        weightDates: weightDates.values.toList(),
        trainingDates: trainingDates.values.toList(),
      ),
    );
    return BodyRhythmState(
      snapshot: snapshot,
      reviewStatus: review,
      mealRecords: List<MealRecord>.unmodifiable(meals),
      weightDates: List<DateTime>.unmodifiable(weightDates.values),
      trainingDates: List<DateTime>.unmodifiable(trainingDates.values),
      statusMessage: statusMessage,
      canPersist: _rhythmDatabase != null,
    );
  }

  RhythmInput _buildInput({
    required TrainingMvpState training,
    required List<HealthSnapshot> healthSnapshots,
    required List<Map<String, Object?>> observations,
    required List<Map<String, Object?>> workouts,
    required DateTime calculatedOn,
  }) {
    final Map<String, double> sleepByDay = <String, double>{};
    final Map<String, double> restingByDay = <String, double>{};
    for (final BodyMetric metric in training.bodyMetrics.reversed) {
      if (metric.sleepHours > 0) {
        sleepByDay[_dateKey(metric.measuredAt)] = metric.sleepHours;
      }
      if (metric.restingHeartRate > 0) {
        restingByDay[_dateKey(metric.measuredAt)] =
            metric.restingHeartRate.toDouble();
      }
    }
    for (final HealthSnapshot snapshot in healthSnapshots.reversed) {
      if (snapshot.sleepHours != null && snapshot.sleepHours! > 0) {
        sleepByDay[_dateKey(snapshot.date)] = snapshot.sleepHours!;
      }
      if (snapshot.restingHeartRate != null &&
          snapshot.restingHeartRate! > 0) {
        restingByDay[_dateKey(snapshot.date)] =
            snapshot.restingHeartRate!.toDouble();
      }
    }
    final Map<String, double> stepsByDay = <String, double>{};
    for (final Map<String, Object?> row in observations) {
      final String kind = row['observation_kind'] as String? ?? '';
      final String day = row['local_date'] as String? ?? '';
      final double value = (row['value'] as num?)?.toDouble() ?? 0;
      if (kind.contains('StepCount') || kind == 'stepCount') {
        stepsByDay[day] = value;
      } else if (kind.contains('RestingHeartRate') ||
          kind == 'restingHeartRate') {
        restingByDay[day] = value;
      }
    }
    final DateTime windowStart =
        _dateOnly(calculatedOn.subtract(const Duration(days: 29)));
    final List<RhythmTimedValue> restingSamples =
        restingByDay.entries.map((MapEntry<String, double> entry) {
      final DateTime date = DateTime.parse(entry.key);
      return RhythmTimedValue(
        dayOffset: date.difference(windowStart).inDays.toDouble(),
        value: entry.value,
      );
    }).toList();
    final Set<String> trainingDays = <String>{
      for (final Map<String, Object?> row in workouts)
        if ((row['local_date'] as String? ?? '').isNotEmpty)
          row['local_date']! as String,
      for (final TrainingLog log in training.logs)
        if (!log.createdAt.isBefore(windowStart)) _dateKey(log.createdAt),
    };
    int strengthMinutes = 0;
    for (final Map<String, Object?> row in workouts) {
      if (row['discipline'] == 'strength') {
        strengthMinutes +=
            ((row['active_duration_seconds'] as num?)?.toInt() ??
                    (row['elapsed_duration_seconds'] as num?)?.toInt() ??
                    0) ~/
                60;
      }
    }
    DateTime? latestTraining;
    for (final String day in trainingDays) {
      final DateTime date = DateTime.parse(day);
      if (latestTraining == null || date.isAfter(latestTraining)) {
        latestTraining = date;
      }
    }
    return RhythmInput(
      calculatedOn: calculatedOn,
      birthDate: training.profile.birthDate,
      averageSleepHours: _average(sleepByDay.values),
      sleepSampleDays: sleepByDay.length,
      averageDailySteps: _average(stepsByDay.values),
      activitySampleDays: stepsByDay.length,
      trainingDays: trainingDays.length,
      strengthMinutes: strengthMinutes,
      noTrainingDays: latestTraining == null
          ? 30
          : math.max(
              0,
              _dateOnly(calculatedOn).difference(latestTraining).inDays,
            ),
      restingHeartRateSamples: restingSamples,
    );
  }

  Future<List<Map<String, Object?>>> _healthObservations(
    String athleteId,
    DateTime start,
    DateTime end,
  ) async {
    final TrainMateStructuredDatabaseGateway? database = _structuredDatabase;
    if (database == null) return const <Map<String, Object?>>[];
    return database.listHealthObservationFactRows(
      athleteProfileId: athleteId,
      observedAtOrAfter: start.toUtc().toIso8601String(),
      observedBefore: end.add(const Duration(days: 1)).toUtc().toIso8601String(),
    );
  }

  Future<List<Map<String, Object?>>> _workouts(
    String athleteId,
    DateTime start,
    DateTime end,
  ) async {
    final TrainMateStructuredDatabaseGateway? database = _structuredDatabase;
    if (database == null) return const <Map<String, Object?>>[];
    return database.listWorkoutFactRows(
      athleteProfileId: athleteId,
      startedAtOrAfter: start.toUtc().toIso8601String(),
      startedBefore: end.add(const Duration(days: 1)).toUtc().toIso8601String(),
    );
  }

  Future<List<MealRecord>> _mealRecords(
    String athleteId,
    DateTime start,
    DateTime end,
  ) async {
    final RhythmDatabaseGateway? database = _rhythmDatabase;
    if (database == null) return const <MealRecord>[];
    final List<Map<String, Object?>> rows = await database.listMealRecords(
      athleteProfileId: athleteId,
      localDateOnOrAfter: _dateKey(start),
      localDateOnOrBefore: _dateKey(end),
    );
    return rows.map(MealRecord.fromDatabaseRow).toList(growable: false);
  }

  double? _average(Iterable<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((double a, double b) => a + b) / values.length;
  }

  DateTime _weekStart(DateTime value) {
    final DateTime day = _dateOnly(value);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  DateTime _dateOnly(DateTime value) {
    final DateTime local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _dateKey(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
