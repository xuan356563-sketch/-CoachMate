import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/daily_adjustment.dart';
import '../../../data/repositories/daily_context_repository.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/local_storage_service.dart';
import '../../profile/application/user_profile_controller.dart';

/// 提供当前本地存储对应的每日调整上下文仓库。
final dailyContextRepositoryProvider = Provider<DailyContextRepository>(
  (Ref ref) => PersistedDailyContextRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

/// 管理独立的每日调整状态。
final dailyAdjustmentControllerProvider =
    NotifierProvider<DailyAdjustmentController, DailyAdjustmentState>(
  DailyAdjustmentController.new,
);

/// 每日调整上下文及其用户可见状态文案。
class DailyAdjustmentState {
  final DailyAdjustmentContext context;

  const DailyAdjustmentState({required this.context});

  String get statusMessage => context.statusMessage;
}

/// 负责读取、保存和恢复每日现实约束。
class DailyAdjustmentController extends Notifier<DailyAdjustmentState> {
  @override
  DailyAdjustmentState build() {
    bindFeatureController(
      ref,
      'feature.daily_adjustment',
      'controller',
      this,
    );
    final int defaultAvailableMinutes =
        ref.watch(userProfileControllerProvider).profile.dailyAvailableMinutes;
    final DailyAdjustmentContext context =
        ref.watch(dailyContextRepositoryProvider).getContext(
              defaultAvailableMinutes: defaultAvailableMinutes,
            );
    return DailyAdjustmentState(context: context);
  }

  /// 更新今日可训练时间。
  Future<void> setDailyAvailableMinutes(int minutes) {
    return _saveContext(
      DailyAdjustmentContext(
        availableMinutes: minutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已更新今日可训练时间为 $minutes 分钟。',
        appliedDecisions: state.context.appliedDecisions,
        statusConfirmedAt: state.context.statusConfirmedAt,
      ),
    );
  }

  /// 更新今日工作压力。
  Future<void> setDailyWorkStress(WorkStressLevel value) {
    return _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: value,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已更新今日工作压力为${value.label}。',
        appliedDecisions: state.context.appliedDecisions,
        statusConfirmedAt: state.context.statusConfirmedAt,
      ),
    );
  }

  /// 更新今日训练场地。
  Future<void> setDailyTrainingEnvironment(TrainingEnvironment value) {
    return _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: value,
        weather: state.context.weather,
        statusMessage: '已更新今日训练场地为${value.label}。',
        appliedDecisions: state.context.appliedDecisions,
        statusConfirmedAt: state.context.statusConfirmedAt,
      ),
    );
  }

  /// 更新今日天气状态。
  Future<void> setDailyWeather(WeatherCondition value) {
    return _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: value,
        statusMessage: '已更新今日天气状态为${value.label}。',
        appliedDecisions: state.context.appliedDecisions,
        statusConfirmedAt: state.context.statusConfirmedAt,
      ),
    );
  }

  /// 仅记录建议，实际课程变化必须经过预览、审核和确认。
  Future<void> applyDailyAdjustmentDecision(DailyAdjustmentDecision decision) {
    final DateTime confirmedAt = DateTime.now();
    return _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage:
            '建议已记录，计划未改变：${decision.decisionLabel}，${decision.planChangeSummary}',
        statusConfirmedAt: state.context.statusConfirmedAt,
        appliedDecisions: <AppliedDailyDecisionFact>[
          ...state.context.appliedDecisions,
          AppliedDailyDecisionFact(
            localDate: _localDateKey(confirmedAt),
            decisionType: decision.decisionType,
            confirmedAt: confirmedAt,
          ),
        ],
      ),
    );
  }

  /// 记录用户确认的 AI 恢复提示，不改变本地疼痛和准备度决策优先级。
  Future<void> applyAiRecoveryRecommendation(String recommendation) {
    final String normalized = recommendation.trim();
    if (normalized.isEmpty) return Future<void>.value();
    return _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已确认 AI 恢复建议：$normalized 本地安全规则仍优先。',
        appliedDecisions: state.context.appliedDecisions,
        statusConfirmedAt: state.context.statusConfirmedAt,
      ),
    );
  }

  /// 无身体设备或身体基线时仍可记录主观偏累，但不补造任何健康字段。
  Future<void> recordTiredCheckIn() {
    return _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已记录今日偏累；请查看调整建议，计划未改变，未生成身体指标。',
        appliedDecisions: state.context.appliedDecisions,
        statusConfirmedAt: state.context.statusConfirmedAt,
      ),
    );
  }

  Future<void> confirmTodayStatus() => _saveContext(DailyAdjustmentContext(
      availableMinutes: state.context.availableMinutes,
      workStress: state.context.workStress, environment: state.context.environment,
      weather: state.context.weather, appliedDecisions: state.context.appliedDecisions,
      statusConfirmedAt: DateTime.now(),
      statusMessage: '已确认今日状态记录；缺少的身体指标仍显示为未记录。'));

  Future<void> _saveContext(DailyAdjustmentContext context) {
    final FeatureOperation operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.daily_adjustment');
    return operation.commit(() async {
      final storage = ref.read(localStorageServiceProvider);
      final repository = ref.read(dailyContextRepositoryProvider);
      final previous = state.context;
      final previousJson = storage.readJson(PersistedDailyContextRepository.storageKey);
      try {
        final savedContext = repository.saveContext(context);
        await storage.flush();
        state = DailyAdjustmentState(context: savedContext);
      } catch (_) {
        repository.saveContext(previous);
        if (previousJson == null) {
          storage.remove(PersistedDailyContextRepository.storageKey);
        } else {
          storage.saveJson(PersistedDailyContextRepository.storageKey, previousJson);
        }
        await storage.flush();
        throw StateError('每日状态保存失败，已保留原状态，请重试。');
      }
    });
  }
}

String _localDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
