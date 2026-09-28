import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/plan_adjustment.dart';
import '../../../data/models/training_metrics.dart';
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
    bindFeatureController(ref, 'feature.training_plan', 'adjustment', this);
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
  Future<void> saveManualAdjustment({
    required WorkoutDay workout,
    required int adjustedMinutes,
    required String adjustedIntensity,
    required String reason,
    FeatureOperation? sourceOperation,
  }) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
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
    final PlanAdjustment adjustment = PlanAdjustment(
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
    );
    await _commitAdjustmentWrite(
      operation,
      () =>
          ref.read(planAdjustmentRepositoryProvider).saveAdjustment(adjustment),
      '已记录为本地学习信号：${canonicalWorkout.title} 调整为 '
      '$adjustedMinutes 分钟 · $intensity。',
    );
  }

  /// 保存恢复原始计划的本地学习信号。
  Future<void> restoreOriginalPlan(WorkoutDay workout,
      {FeatureOperation? sourceOperation}) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
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
    final PlanAdjustment adjustment = PlanAdjustment(
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
    );
    await _commitAdjustmentWrite(
      operation,
      () =>
          ref.read(planAdjustmentRepositoryProvider).saveAdjustment(adjustment),
      '已恢复原计划并记录为本地学习信号：${canonicalWorkout.title}。',
    );
  }

  /// 应用已经由用户确认的 ACWR 调整建议。
  ///
  /// 该入口只接受单个训练日的确定性差异；周总量建议不会在这里猜测分摊。
  Future<void> applyConfirmedProposal({
    required AdjustmentProposal proposal,
    required WorkoutDay currentWorkout,
    FeatureOperation? sourceOperation,
  }) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    if (proposal.status != AdjustmentProposalStatus.confirmed) {
      throw StateError('调整建议尚未确认，训练计划保持不变。');
    }
    if (proposal.workoutDayId == null ||
        proposal.workoutDayId != currentWorkout.id ||
        proposal.planId != currentWorkout.planId) {
      throw StateError('调整建议与当前训练日不匹配，未修改训练计划。');
    }
    if (proposal.originalMinutes != currentWorkout.estimatedMinutes ||
        proposal.originalIntensity != currentWorkout.intensity) {
      throw StateError('训练计划已变化，请重新生成调整预览后再确认。');
    }
    if (proposal.adjustedMinutes < 5 || proposal.adjustedMinutes > 180) {
      throw StateError('调整后的训练时长超出 5 到 180 分钟安全范围。');
    }
    final String adjustedIntensity = proposal.adjustedIntensity.trim();
    if (adjustedIntensity.isEmpty || adjustedIntensity == '降低一级') {
      throw StateError('调整建议没有可执行的明确强度，未修改训练计划。');
    }

    final DateTime adjustedAt = proposal.confirmedAt ?? DateTime.now();
    final PlanAdjustment adjustment = PlanAdjustment(
      id: 'plan-proposal-${proposal.id}-${adjustedAt.microsecondsSinceEpoch}',
      planId: proposal.planId,
      workoutDayId: currentWorkout.id,
      workoutTitle: currentWorkout.title,
      originalEstimatedMinutes: proposal.originalMinutes,
      adjustedEstimatedMinutes: proposal.adjustedMinutes,
      originalIntensity: proposal.originalIntensity,
      adjustedIntensity: adjustedIntensity,
      reason: proposal.explanation,
      kind: PlanAdjustmentKind.adjusted,
      adjustedAt: adjustedAt,
      sourceProposalId: proposal.id,
    );
    await _commitAdjustmentWrite(
      operation,
      () =>
          ref.read(planAdjustmentRepositoryProvider).saveAdjustment(adjustment),
      '已应用经确认的负荷调整：${currentWorkout.title}。',
    );
  }

  /// 把周总量建议按预览快照一次性写入；任一训练日变化都会阻止整组应用。
  Future<void> applyConfirmedWeeklyProposal({
    required AdjustmentProposal proposal,
    required List<WorkoutDay> currentWorkouts,
    FeatureOperation? sourceOperation,
  }) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    if (proposal.status != AdjustmentProposalStatus.confirmed) {
      throw StateError('周总量调整建议尚未确认，训练计划保持不变。');
    }
    if (proposal.workoutDayId != null || proposal.workoutChanges.isEmpty) {
      throw StateError('周总量建议缺少完整训练日差异，未修改训练计划。');
    }
    final Map<String, WorkoutDay> currentById = <String, WorkoutDay>{
      for (final WorkoutDay workout in currentWorkouts) workout.id: workout,
    };
    if (currentById.length != proposal.workoutChanges.length) {
      throw StateError('周总量建议与当前计划不完整匹配，未修改训练计划。');
    }
    int originalTotal = 0;
    int adjustedTotal = 0;
    for (final AdjustmentProposalWorkoutChange change
        in proposal.workoutChanges) {
      final WorkoutDay? workout = currentById[change.workoutDayId];
      if (workout == null || workout.planId != proposal.planId) {
        throw StateError('周总量建议包含不存在的训练日，未修改训练计划。');
      }
      if (workout.estimatedMinutes != change.originalMinutes ||
          workout.intensity != change.originalIntensity) {
        throw StateError('训练计划已变化，请重新生成周总量预览后再确认。');
      }
      if (change.adjustedMinutes < 5 ||
          change.adjustedMinutes > change.originalMinutes ||
          change.adjustedIntensity != change.originalIntensity) {
        throw StateError('周总量建议包含不安全或越界的训练日差异，未修改训练计划。');
      }
      originalTotal += change.originalMinutes;
      adjustedTotal += change.adjustedMinutes;
    }
    if (originalTotal != proposal.originalMinutes ||
        adjustedTotal != proposal.adjustedMinutes ||
        adjustedTotal >= originalTotal) {
      throw StateError('周总量建议汇总与差异快照不一致，未修改训练计划。');
    }

    final DateTime adjustedAt = proposal.confirmedAt ?? DateTime.now();
    final List<PlanAdjustment> adjustments = proposal.workoutChanges
        .map(
          (AdjustmentProposalWorkoutChange change) => PlanAdjustment(
            id: 'plan-proposal-${proposal.id}-${change.workoutDayId}-'
                '${adjustedAt.microsecondsSinceEpoch}',
            planId: proposal.planId,
            workoutDayId: change.workoutDayId,
            workoutTitle: change.workoutTitle,
            originalEstimatedMinutes: change.originalMinutes,
            adjustedEstimatedMinutes: change.adjustedMinutes,
            originalIntensity: change.originalIntensity,
            adjustedIntensity: change.adjustedIntensity,
            reason: proposal.explanation,
            kind: PlanAdjustmentKind.adjusted,
            adjustedAt: adjustedAt,
            sourceProposalId: proposal.id,
          ),
        )
        .toList(growable: false);
    await _commitAdjustmentWrite(
      operation,
      () => ref
          .read(planAdjustmentRepositoryProvider)
          .saveAdjustmentsAtomically(adjustments),
      '已应用经确认的周总量调整，共 ${adjustments.length} 个训练日。',
    );
  }

  /// 撤销指定建议产生的调整；若用户随后又手动修改计划，则拒绝覆盖新修改。
  Future<void> undoConfirmedProposal(AdjustmentProposal proposal,
      {FeatureOperation? sourceOperation}) async {
    final FeatureOperation operation = sourceOperation ??
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    if (proposal.status != AdjustmentProposalStatus.confirmed &&
        proposal.status != AdjustmentProposalStatus.undone) {
      throw StateError('只有已确认的调整建议可以撤销。');
    }
    if (proposal.workoutChanges.isNotEmpty) {
      await _undoConfirmedWeeklyProposal(proposal, operation);
      return;
    }
    final String? workoutDayId = proposal.workoutDayId;
    if (workoutDayId == null) {
      throw StateError('周总量预览未曾自动应用，无需撤销训练计划。');
    }
    final PlanAdjustment? latest = _latestFor(workoutDayId);
    if (latest == null ||
        !latest.isActive ||
        latest.sourceProposalId != proposal.id) {
      throw StateError('训练计划已有后续修改，为避免覆盖新计划，本次撤销已停止。');
    }

    final DateTime adjustedAt = proposal.undoneAt ?? DateTime.now();
    final PlanAdjustment adjustment = PlanAdjustment(
      id: 'plan-proposal-undo-${proposal.id}-${adjustedAt.microsecondsSinceEpoch}',
      planId: proposal.planId,
      workoutDayId: workoutDayId,
      workoutTitle: proposal.workoutTitle,
      originalEstimatedMinutes: proposal.originalMinutes,
      adjustedEstimatedMinutes: proposal.originalMinutes,
      originalIntensity: proposal.originalIntensity,
      adjustedIntensity: proposal.originalIntensity,
      reason: '用户撤销 ACWR 调整建议，恢复确认前快照。',
      kind: PlanAdjustmentKind.restored,
      adjustedAt: adjustedAt,
      sourceProposalId: proposal.id,
    );
    await _commitAdjustmentWrite(
      operation,
      () =>
          ref.read(planAdjustmentRepositoryProvider).saveAdjustment(adjustment),
      '已撤销负荷调整并恢复确认前计划：${proposal.workoutTitle}。',
    );
  }

  Future<void> _undoConfirmedWeeklyProposal(
      AdjustmentProposal proposal, FeatureOperation operation) async {
    final List<PlanAdjustment> active = <PlanAdjustment>[];
    for (final AdjustmentProposalWorkoutChange change
        in proposal.workoutChanges) {
      final PlanAdjustment? latest = _latestFor(change.workoutDayId);
      if (latest == null ||
          !latest.isActive ||
          latest.sourceProposalId != proposal.id ||
          latest.adjustedEstimatedMinutes != change.adjustedMinutes) {
        throw StateError('周计划已有后续修改，为避免覆盖新计划，本次整组撤销已停止。');
      }
      active.add(latest);
    }
    final DateTime adjustedAt = proposal.undoneAt ?? DateTime.now();
    final List<PlanAdjustment> restored = <PlanAdjustment>[
      for (int index = 0; index < proposal.workoutChanges.length; index += 1)
        PlanAdjustment(
          id: 'plan-proposal-undo-${proposal.id}-'
              '${proposal.workoutChanges[index].workoutDayId}-'
              '${adjustedAt.microsecondsSinceEpoch}',
          planId: proposal.planId,
          workoutDayId: proposal.workoutChanges[index].workoutDayId,
          workoutTitle: active[index].workoutTitle,
          originalEstimatedMinutes:
              proposal.workoutChanges[index].originalMinutes,
          adjustedEstimatedMinutes:
              proposal.workoutChanges[index].originalMinutes,
          originalIntensity: proposal.workoutChanges[index].originalIntensity,
          adjustedIntensity: proposal.workoutChanges[index].originalIntensity,
          reason: '用户撤销 ACWR 周总量调整建议，恢复确认前快照。',
          kind: PlanAdjustmentKind.restored,
          adjustedAt: adjustedAt,
          sourceProposalId: proposal.id,
        ),
    ];
    await _commitAdjustmentWrite(
      operation,
      () => ref
          .read(planAdjustmentRepositoryProvider)
          .saveAdjustmentsAtomically(restored),
      '已整组撤销周总量调整并恢复确认前计划。',
    );
  }

  /// 删除由健康指标建议产生的计划投影，保留用户手动调整记录。
  void clearHealthDerivedAdjustments() {
    final int removed = ref
        .read(planAdjustmentRepositoryProvider)
        .clearHealthDerivedAdjustments();
    _refresh(
      removed == 0 ? '当前没有需要清理的健康派生计划调整。' : '已清理 $removed 条健康派生计划调整，手动调整保持不变。',
    );
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

  Future<void> _commitAdjustmentWrite(
    FeatureOperation operation,
    void Function() write,
    String statusMessage,
  ) {
    return operation.commit(() async {
      write();
      await ref.read(localStorageServiceProvider).flush();
      _refresh(statusMessage);
    });
  }

  /// 每日提案经审核后以原调整文档作为唯一权威写入，失败恢复文档和缓存。
  Future<void> commitCourseAdjustment(PlanAdjustment adjustment,
      {required FeatureOperation operation, required void Function() recheck}) {
    return operation.commit(() async {
      recheck();
      final storage = ref.read(localStorageServiceProvider);
      final before = storage.readJson(PersistedPlanAdjustmentRepository.storageKey);
      try {
        ref.read(planAdjustmentRepositoryProvider).saveAdjustment(adjustment);
        await storage.flush();
      } catch (_) {
        if (before == null) {
          storage.remove(PersistedPlanAdjustmentRepository.storageKey);
        } else {
          storage.saveJson(PersistedPlanAdjustmentRepository.storageKey, before);
        }
        try { await storage.flush(); } finally {
          ref.invalidate(planAdjustmentRepositoryProvider);
        }
        rethrow;
      }
      _refresh('已应用经确认的每日课程调整：${adjustment.workoutTitle}。');
    });
  }

  void _setStatus(String statusMessage) {
    state = PlanAdjustmentState(
      adjustments: state.adjustments,
      statusMessage: statusMessage,
    );
  }
}
