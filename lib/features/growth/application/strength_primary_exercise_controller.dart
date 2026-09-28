import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/trainmate_structured_database_gateway.dart';
import '../../../data/models/training_metrics.dart';
import '../../../data/repositories/training_metrics_repository.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/training_metrics_pipeline.dart';
import '../../profile/application/health_sync_controller.dart';
import 'training_metrics_provider.dart';

class StrengthExerciseOption {
  const StrengthExerciseOption({
    required this.exerciseKey,
    required this.displayName,
    required this.isActive,
    required this.recordedSetCount,
  });

  final String exerciseKey;
  final String displayName;
  final bool isActive;
  final int recordedSetCount;
}

final strengthExerciseOptionsProvider =
    FutureProvider.family<List<StrengthExerciseOption>, String>(
  (Ref ref, String athleteProfileId) async {
    final TrainMateStructuredDatabaseGateway? database =
        ref.watch(healthSyncStructuredDatabaseGatewayProvider);
    if (database == null || athleteProfileId.trim().isEmpty) {
      return const <StrengthExerciseOption>[];
    }
    final DateTime now = DateTime.now();
    final List<Map<String, Object?>> setRows =
        await database.listStrengthSetRows(
      athleteProfileId: athleteProfileId,
      localDateOnOrAfter: _dateKey(
        DateTime(now.year - 5, now.month, now.day),
      ),
      localDateBefore: _dateKey(
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      ),
    );
    final List<Map<String, Object?>> primaryRows =
        await database.listAthletePrimaryExerciseRows(
      athleteProfileId: athleteProfileId,
    );
    final Map<String, _MutableExerciseOption> options =
        <String, _MutableExerciseOption>{};
    for (final Map<String, Object?> row in setRows) {
      final String key = (row['exercise_key'] as String? ?? '').trim();
      final String name = (row['exercise_name'] as String? ?? '').trim();
      if (key.isEmpty || name.isEmpty) continue;
      final _MutableExerciseOption option = options.putIfAbsent(
        key,
        () => _MutableExerciseOption(exerciseKey: key, displayName: name),
      );
      option
        ..displayName = name
        ..recordedSetCount += 1;
    }
    for (final Map<String, Object?> row in primaryRows) {
      final String key = (row['exercise_key'] as String? ?? '').trim();
      final String name = (row['display_name'] as String? ?? '').trim();
      if (key.isEmpty || name.isEmpty) continue;
      final _MutableExerciseOption option = options.putIfAbsent(
        key,
        () => _MutableExerciseOption(exerciseKey: key, displayName: name),
      );
      option
        ..displayName = name
        ..isActive = row['is_active'] == true || row['is_active'] == 1;
    }
    final List<StrengthExerciseOption> result = options.values
        .map(
          (_MutableExerciseOption item) => StrengthExerciseOption(
            exerciseKey: item.exerciseKey,
            displayName: item.displayName,
            isActive: item.isActive,
            recordedSetCount: item.recordedSetCount,
          ),
        )
        .toList(growable: false)
      ..sort((StrengthExerciseOption first, StrengthExerciseOption second) {
        final int byActive =
            (second.isActive ? 1 : 0).compareTo(first.isActive ? 1 : 0);
        if (byActive != 0) return byActive;
        return first.displayName.compareTo(second.displayName);
      });
    return List<StrengthExerciseOption>.unmodifiable(result);
  },
);

final strengthPrimaryExerciseServiceProvider =
    Provider<StrengthPrimaryExerciseService>(
  (Ref ref) {
    final StrengthPrimaryExerciseService service =
        StrengthPrimaryExerciseService(
      database: ref.watch(healthSyncStructuredDatabaseGatewayProvider),
      repository: ref.watch(trainingMetricsRepositoryProvider),
      metricsPipeline: ref.watch(healthSyncMetricsPipelineProvider),
      featureAccess: ref.watch(featureAccessProvider),
    );
    bindFeatureController(ref, 'feature.growth', 'strengthPrimary', service);
    return service;
  },
);

class StrengthPrimaryExerciseRecalculationException implements Exception {
  const StrengthPrimaryExerciseRecalculationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 保存用户主项，并让依赖该配置的力量指标失效后重算。
class StrengthPrimaryExerciseService {
  StrengthPrimaryExerciseService({
    required TrainMateStructuredDatabaseGateway? database,
    required TrainingMetricsRepository repository,
    required TrainingMetricsPipeline? metricsPipeline,
    FeatureAccess? featureAccess,
    DateTime Function()? clock,
  })  : _database = database,
        _repository = repository,
        _metricsPipeline = metricsPipeline,
        _featureAccess = featureAccess,
        _clock = clock ?? DateTime.now;

  final TrainMateStructuredDatabaseGateway? _database;
  final TrainingMetricsRepository _repository;
  final TrainingMetricsPipeline? _metricsPipeline;
  final FeatureAccess? _featureAccess;
  final DateTime Function() _clock;

  Future<void> setActive({
    required String athleteProfileId,
    required String exerciseKey,
    required String displayName,
    required bool isActive,
  }) async {
    final FeatureOperation? operation =
        _featureAccess?.beginOperation('feature.growth');
    final TrainMateStructuredDatabaseGateway? database = _database;
    if (database == null) {
      throw StateError('当前平台没有可用的结构化成长存储，不能保存力量主项。');
    }
    if (athleteProfileId.trim().isEmpty ||
        exerciseKey.trim().isEmpty ||
        displayName.trim().isEmpty) {
      throw const FormatException('力量主项缺少运动员、动作标识或动作名称。');
    }
    final DateTime now = _clock();
    Future<void> save() async {
      await database.setAthletePrimaryExercise(
        athleteProfileId: athleteProfileId,
        exerciseKey: exerciseKey,
        displayName: displayName,
        isActive: isActive,
        updatedAt: now,
      );
      await _repository.invalidateBySource(
        athleteProfileId: athleteProfileId,
        sourceType: 'athlete_primary_exercises',
        sourceId: '$athleteProfileId:$exerciseKey',
        invalidatedAt: now.toUtc(),
      );
    }

    if (operation == null) {
      await save();
    } else {
      await operation.commit(save);
    }
    final TrainingMetricsPipeline? pipeline = _metricsPipeline;
    if (pipeline == null) return;
    try {
      if (operation == null) {
        await pipeline.aggregatePeriod(
          athleteProfileId: athleteProfileId,
          period: MetricPeriod.week,
          periodStart: _weekStart(now),
        );
      } else {
        await operation.commit(() => pipeline.aggregatePeriod(
              athleteProfileId: athleteProfileId,
              period: MetricPeriod.week,
              periodStart: _weekStart(now),
            ));
      }
    } catch (error, stackTrace) {
      if (operation != null) {
        try {
          operation.checkActive();
        } catch (_) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
      throw const StrengthPrimaryExerciseRecalculationException(
        '力量主项已保存；相关指标保持失效，稍后可重新同步计算。',
      );
    }
  }
}

class _MutableExerciseOption {
  _MutableExerciseOption({
    required this.exerciseKey,
    required this.displayName,
  });

  final String exerciseKey;
  String displayName;
  bool isActive = false;
  int recordedSetCount = 0;
}

DateTime _weekStart(DateTime value) {
  final DateTime date = DateTime(value.year, value.month, value.day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
