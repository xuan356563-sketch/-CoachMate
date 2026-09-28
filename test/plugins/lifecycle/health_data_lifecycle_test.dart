import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_rhythm.dart';
import 'package:trainflow_ai/data/models/meal_guide.dart';
import 'package:trainflow_ai/data/local/rhythm_database_gateway.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/data/seed/seed_body_metrics.dart';
import 'package:trainflow_ai/features/daily_adjustment/application/daily_adjustment_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_export_controller.dart';
import 'package:trainflow_ai/features/meal_guide/application/meal_preference_controller.dart';
import 'package:trainflow_ai/features/profile/application/achievement_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_stub.dart';
import 'package:trainflow_ai/features/rhythm/application/body_rhythm_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实服务按功能绑定，停用后拒绝直接写入但保留数据清理', () async {
    final PluginRuntime runtime = await _runtime();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    PersistedBodyMetricRepository(storage).saveMetric(
      seedBodyMetrics.first,
      reason: '测试基线',
    );
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    final BodyMetricController body =
        container.read(bodyMetricControllerProvider.notifier);
    final BodyMetricExportController exports =
        container.read(bodyMetricExportControllerProvider.notifier);
    final DailyAdjustmentController daily =
        container.read(dailyAdjustmentControllerProvider.notifier);
    final MealPreferenceController meals =
        container.read(mealPreferenceControllerProvider.notifier);
    final AchievementController achievements =
        container.read(achievementControllerProvider.notifier);
    expect(
      runtime.service('feature.data_center')!.read<BodyMetricController>(
            'bodyMetric',
          ),
      same(body),
    );
    expect(
      runtime.service('feature.daily_check_in')!.read<BodyMetricController>(
            'checkIn',
          ),
      same(body),
    );
    expect(
      runtime
          .service('feature.daily_adjustment')!
          .read<DailyAdjustmentController>('controller'),
      same(daily),
    );
    expect(
      runtime
          .service('feature.meal_guide')!
          .read<MealPreferenceController>('controller'),
      same(meals),
    );
    expect(
      runtime
          .service('feature.growth')!
          .read<AchievementController>('achievement'),
      same(achievements),
    );
    expect(
      runtime
          .service('core.data_rights')!
          .read<BodyMetricExportController>('bodyMetricExport'),
      same(exports),
    );

    await body.saveManualMetric(
      weightKg: 70,
      restingHeartRate: 58,
      hrvMs: 55,
      sleepHours: 7.5,
      fatigueLevel: 3,
      measuredAt: seedBodyMetrics.first.measuredAt,
    );
    await runtime.disable('feature.data_center');
    expect(
      () => body.saveManualMetric(
        weightKg: 71,
        restingHeartRate: 59,
        hrvMs: 54,
        sleepHours: 7,
        fatigueLevel: 4,
      ),
      throwsStateError,
    );
    expect(container.read(bodyMetricControllerProvider).metrics, hasLength(1));
    await body.clear();
    expect(container.read(bodyMetricControllerProvider).metrics, isEmpty);

    await runtime.disable('feature.daily_check_in');
    expect(body.recordTiredDailyCheckIn, throwsStateError);

    await runtime.disable('feature.daily_adjustment');
    expect(() => daily.setDailyAvailableMinutes(20), throwsStateError);

    await meals.saveScenario(MealScenario.homeCooking);
    await runtime.disable('feature.meal_guide');
    expect(
      () => meals.saveScenario(MealScenario.canteen),
      throwsStateError,
    );
    await meals.clear();
    expect(
      container.read(mealPreferenceControllerProvider).scenario,
      MealScenario.takeaway,
    );

    await runtime.disable('feature.growth');
    expect(
      () => achievements.sync(const []),
      throwsStateError,
    );
  });

  test('身体数据停用后导出和清除导出记录仍可用', () async {
    final PluginRuntime runtime = await _runtime();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
    ]);
    addTearDown(container.dispose);
    final BodyMetricExportController exports =
        container.read(bodyMetricExportControllerProvider.notifier);
    await runtime.disable('feature.data_center');

    await exports.recordJsonExport('{}');
    expect(container.read(bodyMetricExportControllerProvider).records,
        hasLength(1));
    await exports.clear();
    expect(container.read(bodyMetricExportControllerProvider).records, isEmpty);
  });

  test('身体节奏停用时 build 不补建快照，直接饮食写入拒绝但撤销保留', () async {
    final PluginRuntime runtime = await _runtime();
    await runtime.disable('feature.rhythm');
    final _RecordingRhythmDatabase database = _RecordingRhythmDatabase();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      rhythmDatabaseGatewayProvider.overrideWithValue(database),
      healthDataGatewayProvider.overrideWithValue(
        const UnsupportedHealthDataGateway(),
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(healthSyncControllerProvider.future);
    final BodyRhythmState state =
        await container.read(bodyRhythmControllerProvider.future);

    expect(database.insertCalls, 0);
    expect(state.canPersist, isFalse);
    expect(state.statusMessage, contains('已停用'));
    await expectLater(
      container.read(bodyRhythmControllerProvider.notifier).saveMeal(
            mealType: MealType.lunch,
            summary: '测试午餐',
          ),
      throwsStateError,
    );
    await container
        .read(bodyRhythmControllerProvider.notifier)
        .revokeMeal('history-meal');
    expect(database.revokedIds, <String>['history-meal']);
  });
}

Future<PluginRuntime> _runtime() async {
  final PluginRuntime runtime =
      PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
  await runtime.initialize();
  return runtime;
}

class _RecordingRhythmDatabase implements RhythmDatabaseGateway {
  int insertCalls = 0;
  final List<String> revokedIds = <String>[];

  @override
  Future<Map<String, Object?>?> readRhythmSnapshot({
    required String athleteProfileId,
    required String weekStart,
  }) async =>
      null;

  @override
  Future<Map<String, Object?>> insertRhythmSnapshotIfAbsent(
    Map<String, Object?> row,
  ) async {
    insertCalls += 1;
    return row;
  }

  @override
  Future<List<Map<String, Object?>>> listMealRecords({
    required String athleteProfileId,
    required String localDateOnOrAfter,
    required String localDateOnOrBefore,
  }) async =>
      const <Map<String, Object?>>[];

  @override
  Future<void> saveMealRecord(Map<String, Object?> row) async {}

  @override
  Future<void> revokeMealRecord({
    required String athleteProfileId,
    required String recordId,
    required String revokedAt,
  }) async {
    revokedIds.add(recordId);
  }
}
