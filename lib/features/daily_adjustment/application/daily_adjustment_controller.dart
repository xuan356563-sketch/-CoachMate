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
      ),
    );
  }

  /// 记录已应用的每日调整决策。
  void applyDailyAdjustmentDecision(DailyAdjustmentDecision decision) {
    _saveContext(
      DailyAdjustmentContext(
        availableMinutes: state.context.availableMinutes,
        workStress: state.context.workStress,
        environment: state.context.environment,
        weather: state.context.weather,
        statusMessage:
            '已应用今日调整：${decision.decisionLabel}，${decision.planChangeSummary}',
      ),
    );
  }

  void _saveContext(DailyAdjustmentContext context) {
    final DailyAdjustmentContext savedContext =
        ref.read(dailyContextRepositoryProvider).saveContext(context);
    state = DailyAdjustmentState(context: savedContext);
  }
}
