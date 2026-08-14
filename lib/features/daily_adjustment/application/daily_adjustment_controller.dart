import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/daily_adjustment.dart';
import '../../../data/repositories/daily_context_repository.dart';
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
    final int defaultAvailableMinutes =
        ref.watch(userProfileControllerProvider).profile.dailyAvailableMinutes;
    final DailyAdjustmentContext context =
        ref.watch(dailyContextRepositoryProvider).getContext(
              defaultAvailableMinutes: defaultAvailableMinutes,
            );
    return DailyAdjustmentState(context: context);
  }

  /// 更新今日可训练时间。
  void setDailyAvailableMinutes(int minutes) {
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: minutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已更新今日可训练时间为 $minutes 分钟。',
        appliedDecisions: state.context.appliedDecisions,
      ),
    );
  }

  /// 更新今日工作压力。
  void setDailyWorkStress(WorkStressLevel value) {
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: value,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已更新今日工作压力为${value.label}。',
        appliedDecisions: state.context.appliedDecisions,
      ),
    );
  }

  /// 更新今日训练场地。
  void setDailyTrainingEnvironment(TrainingEnvironment value) {
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: value,
        weather: state.context.weather,
        statusMessage: '已更新今日训练场地为${value.label}。',
        appliedDecisions: state.context.appliedDecisions,
      ),
    );
  }

  /// 更新今日天气状态。
  void setDailyWeather(WeatherCondition value) {
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: value,
        statusMessage: '已更新今日天气状态为${value.label}。',
        appliedDecisions: state.context.appliedDecisions,
      ),
    );
  }

  /// 记录已应用的每日调整决策。
  void applyDailyAdjustmentDecision(DailyAdjustmentDecision decision) {
    final DateTime confirmedAt = DateTime.now();
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage:
            '已应用今日调整：${decision.decisionLabel}，${decision.planChangeSummary}',
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
  void applyAiRecoveryRecommendation(String recommendation) {
    final String normalized = recommendation.trim();
    if (normalized.isEmpty) return;
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已确认 AI 恢复建议：$normalized 本地安全规则仍优先。',
        appliedDecisions: state.context.appliedDecisions,
      ),
    );
  }

  /// 无身体设备或身体基线时仍可记录主观偏累，但不补造任何健康字段。
  void recordTiredCheckIn() {
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage: '已记录今日偏累；训练建议采用轻松版，未生成身体指标。',
        appliedDecisions: state.context.appliedDecisions,
      ),
    );
  }

  void _saveContext(DailyAdjustmentContext context) {
    final DailyAdjustmentContext savedContext =
        ref.read(dailyContextRepositoryProvider).saveContext(context);
    state = DailyAdjustmentState(context: savedContext);
  }
}

String _localDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
