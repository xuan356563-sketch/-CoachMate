import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/plan_adjustment.dart';
import '../../../data/models/workout_day.dart';
import '../../../data/repositories/plan_adjustment_repository.dart';
import '../../../data/repositories/training_plan_repository.dart';
import '../../../services/local_storage_service.dart';

/// 提供当前本地存储对应的计划调整仓库。
final planAdjustmentRepositoryProvider = Provider<PlanAdjustmentRepository>(
  (Ref ref) => PersistedPlanAdjustmentRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

/// 管理独立的训练计划调整状态。
final planAdjustmentControllerProvider =
    NotifierProvider<PlanAdjustmentController, PlanAdjustmentState>(
  PlanAdjustmentController.new,
);

/// 计划调整记录及其用户可见状态文案。
class PlanAdjustmentState {
  final List<PlanAdjustment> adjustments;
  final String statusMessage;

  const PlanAdjustmentState({
    required this.adjustments,
    required this.statusMessage,
  });
}

/// 负责读取、校验、保存和恢复训练计划调整记录。
class PlanAdjustmentController extends Notifier<PlanAdjustmentState> {
  final TrainingPlanRepository _planRepository =
      InMemoryTrainingPlanRepository();

  @override
  PlanAdjustmentState build() {
    final List<PlanAdjustment> adjustments =
        ref.watch(planAdjustmentRepositoryProvider).listAdjustments();
    return PlanAdjustmentState(
      adjustments: adjustments,
      statusMessage: adjustments.isEmpty
          ? '尚未手动调整训练日；可按当天时间和状态微调时长与强度。'
          : '已读取 ${adjustments.length} 条本地计划调整记录。',
    );
  }

  /// 保存用户手动调整后的训练日记录。
  void saveManualAdjustment({
    required WorkoutDay workout,
    required int adjustedMinutes,
    required String adjustedIntensity,
    required String reason,
  }) {
    final String intensity = adjustedIntensity.trim();
    final String normalizedReason = reason.trim();
    if (adjustedMinutes < 5 || adjustedMinutes > 180) {
      _setStatus('调整时长需在 5 到 180 分钟之间。');
      return;
    }
    if (intensity.isEmpty || normalizedReason.isEmpty) {
      _setStatus('请补充调整后的强度和原因。');
      return;
    }

    final WorkoutDay? canonicalWorkout =
        _planRepository.findWorkoutDayById(workout.id);
    if (canonicalWorkout == null) {
      _setStatus('无法保存调整：没有找到对应训练日。');
      return;
    }

    final PlanAdjustment? previous = _latestFor(canonicalWorkout.id);
    final int originalMinutes =
        previous?.originalEstimatedMinutes ?? canonicalWorkout.estimatedMinutes;
    final String originalIntensity =
        previous?.originalIntensity ?? canonicalWorkout.intensity;
    final DateTime now = DateTime.now();
    ref.read(planAdjustmentRepositoryProvider).saveAdjustment(
          PlanAdjustment(
            id: 'plan-adjustment-${canonicalWorkout.id}-${now.millisecondsSinceEpoch}',
            planId: canonicalWorkout.planId,
            workoutDayId: canonicalWorkout.id,
            workoutTitle: canonicalWorkout.title,
            originalEstimatedMinutes: originalMinutes,
            adjustedEstimatedMinutes: adjustedMinutes,
            originalIntensity: originalIntensity,
            adjustedIntensity: intensity,
            reason: normalizedReason,
            kind: PlanAdjustmentKind.adjusted,
            adjustedAt: now,
          ),
        );
    _refresh(
      '已记录为本地学习信号：${canonicalWorkout.title} 调整为 '
      '$adjustedMinutes 分钟 · $intensity。',
    );
  }

  /// 保存恢复原始计划的本地学习信号。
  void restoreOriginalPlan(WorkoutDay workout) {
    final WorkoutDay? canonicalWorkout =
        _planRepository.findWorkoutDayById(workout.id);
    if (canonicalWorkout == null) {
      _setStatus('无法恢复原计划：没有找到对应训练日。');
      return;
    }

    final PlanAdjustment? previous = _latestFor(canonicalWorkout.id);
    final int originalMinutes =
        previous?.originalEstimatedMinutes ?? canonicalWorkout.estimatedMinutes;
    final String originalIntensity =
        previous?.originalIntensity ?? canonicalWorkout.intensity;
    final DateTime now = DateTime.now();
    ref.read(planAdjustmentRepositoryProvider).saveAdjustment(
          PlanAdjustment(
            id: 'plan-restored-${canonicalWorkout.id}-${now.millisecondsSinceEpoch}',
            planId: canonicalWorkout.planId,
            workoutDayId: canonicalWorkout.id,
            workoutTitle: canonicalWorkout.title,
            originalEstimatedMinutes: originalMinutes,
            adjustedEstimatedMinutes: originalMinutes,
            originalIntensity: originalIntensity,
            adjustedIntensity: originalIntensity,
            reason: '用户恢复原计划。',
            kind: PlanAdjustmentKind.restored,
            adjustedAt: now,
          ),
        );
    _refresh('已恢复原计划并记录为本地学习信号：${canonicalWorkout.title}。');
  }

  PlanAdjustment? _latestFor(String workoutDayId) {
    for (final PlanAdjustment adjustment in state.adjustments) {
      if (adjustment.workoutDayId == workoutDayId) {
        return adjustment;
      }
    }
    return null;
  }

  void _refresh(String statusMessage) {
    final List<PlanAdjustment> adjustments =
        ref.read(planAdjustmentRepositoryProvider).listAdjustments();
    state = PlanAdjustmentState(
      adjustments: adjustments,
      statusMessage: statusMessage,
    );
  }

  void _setStatus(String statusMessage) {
    state = PlanAdjustmentState(
      adjustments: state.adjustments,
      statusMessage: statusMessage,
    );
  }
}
