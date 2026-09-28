import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/plan_adjustment.dart';
import '../../../data/models/training_plan.dart';
import '../../../data/models/workout_day.dart';
import '../../../data/models/daily_adjustment.dart';
import '../../../data/models/training_schedule.dart';
import '../../../data/models/workout_player_step.dart';
import '../../../data/seed/seed_exercises.dart';
import '../../../data/repositories/generated_training_plan_repository.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/plan_context_digest_service.dart';
import '../../../services/training_rule_audit_service.dart';
import '../../../services/training_prescription_safety_audit_service.dart';
import '../../../services/resource_workout_binding_service.dart';
import '../../../services/exercise_substitution_service.dart';
import '../../../data/models/training_rule_audit.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../profile/application/user_profile_controller.dart';
import '../../profile/application/training_schedule_controller.dart';
import '../../training_plan/application/four_week_plan_controller.dart';
import '../../training_plan/application/plan_adjustment_controller.dart';
import '../../training_plan/application/pre_exercise_clearance_controller.dart';
import '../../first_run_onboarding/application/membership_controller.dart';
import '../../first_run_onboarding/application/first_run_onboarding_controller.dart';
import 'daily_adjustment_controller.dart';

final dailyCourseAdjustmentProvider =
    Provider((ref) => DailyCourseAdjustment(ref));
final dailyCourseClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
/// 发行回滚只关闭新提交入口，保留既有课程调整历史。
const dailyCourseApplyEnabled = bool.fromEnvironment(
    'TRAINMATE_DAILY_COURSE_APPLY', defaultValue: true);

/// 只承认已经通过基础版本校验并投影到当前计划的确认快照。
PlanAdjustment? appliedDailyCourseFor(TrainingMvpState state, String workoutId) {
  final adjustment = state.latestPlanAdjustmentFor(workoutId);
  final snapshot = adjustment?.workoutSnapshot;
  final current = state.findWorkoutDay(workoutId);
  if (adjustment?.isActive != true || snapshot == null || current == null) {
    return null;
  }
  const digest = PlanContextDigestService();
  return digest.buildCanonicalDigest(current.toJson()) ==
          digest.buildCanonicalDigest(snapshot.toJson())
      ? adjustment
      : null;
}

/// 日程界面和本地复盘读取同一确认结果；原排期文档继续保留其原始安排。
final effectiveTrainingScheduleProvider = Provider<TrainingScheduleState>((ref) {
  final schedule = ref.watch(trainingScheduleControllerProvider);
  ref.watch(trainingMvpProvider.select((state) => (state.plans, state.planAdjustments)));
  final state = ref.read(trainingMvpProvider);
  var changed = false;
  final workouts = schedule.workouts.map((workout) {
    final snapshot = appliedDailyCourseFor(state, workout.workoutDayId)?.workoutSnapshot;
    if (snapshot == null) return workout;
    changed = true;
    return ScheduledWorkout(
      id: workout.id,
      workoutDayId: workout.workoutDayId,
      scheduledDate: workout.scheduledDate,
      startMinute: workout.startMinute,
      allocatedMinutes: snapshot.estimatedMinutes,
      period: workout.period,
      version: ScheduledWorkoutVersion.full,
      discipline: workout.discipline,
      primaryTargetKind: workout.primaryTargetKind,
      targetMinutes: snapshot.estimatedMinutes,
    );
  }).toList();
  return changed
      ? TrainingScheduleState(availability: schedule.availability,
          workouts: workouts, statusMessage: schedule.statusMessage)
      : schedule;
});

class DailyCoursePreview {
  const DailyCoursePreview(
      {required this.id,
      required this.original,
      required this.candidate,
      required this.reason,
      required this.fingerprint,
      required this.operation,
      required this.baseVersionId,
      required this.basePlanFingerprint});
  final String id, reason, fingerprint, basePlanFingerprint;
  final String? baseVersionId;
  final WorkoutDay original;
  final WorkoutDay? candidate;
  final FeatureOperation operation;
}

/// 仅编译已有“缩短版”：保留准备/冷身与第一个主训练，移除辅助内容。
/// 没有可明确执行的处方或完整审核失败时，仅允许记录建议。
WorkoutDay? compileShortDailyCourse(
    WorkoutDay workout, DailyAdjustmentDecision decision) {
  if (decision.decisionLabel != '缩短版' ||
      workout.mainSets.isEmpty ||
      decision.adjustedMinutes >= workout.estimatedMinutes ||
      decision.adjustedMinutes < 15) {
    return null;
  }
  // 有固定持续时间/间歇恢复的课程，不能只改总时长就声称已经缩短。
  if (workout.trainingType != TrainingType.strength ||
      workout.mainSets.any((s) => s.contains('分钟') || s.contains('秒'))) {
    return null;
  }
  final main = workout.workoutExercises
      .where((l) => l.module == WorkoutExerciseModule.mainTraining)
      .toList();
  if (main.isEmpty || workout.mainSets.first.contains('蹲、推、拉')) return null;
  final kept = workout.workoutExercises
      .where((l) =>
          l.module != WorkoutExerciseModule.accessory &&
          (l.module != WorkoutExerciseModule.mainTraining ||
              l.id == main.first.id))
      .toList();
  return workout.copyWith(
      estimatedMinutes: decision.adjustedMinutes,
      mainSets: [workout.mainSets.first],
      accessoryWork: const [],
      workoutExercises: kept);
}

class DailyCourseAdjustment {
  DailyCourseAdjustment(this.ref);
  final Ref ref;
  bool _busy = false;
  String _digest(Object? value) =>
      const PlanContextDigestService().buildCanonicalDigest(value);
  String? get _version =>
      GeneratedTrainingPlanRepository(ref.read(localStorageServiceProvider))
          .getHistory()
          .activeVersionId;
  String _fingerprint() {
    final state = ref.read(trainingMvpProvider);
    final now = ref.read(dailyCourseClockProvider)();
    return _digest({
      'plan': state.activePlan.toJson(),
      'version': _version,
      'profile': state.profile.toJson(),
      'workout': state.todayWorkout.toJson(),
      'body': state.latestBodyMetric?.toJson(),
      'pain': state.latestPainLog?.toJson(),
      'motion': state.latestMotionAnalysisResult?.toJson(),
      'context': ref.read(dailyAdjustmentControllerProvider).context.toJson(),
      'day': '${now.year}-${now.month}-${now.day}'
    });
  }

  DailyCoursePreview preview() {
    if (!dailyCourseApplyEnabled) throw StateError('当前发行已暂停课程调整，请查看原计划。');
    final state = ref.read(trainingMvpProvider);
    final runtime = ref.read(pluginRuntimeProvider);
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.daily_adjustment', dependencies: [
      'feature.training_plan',
      ...state.profile.mainSports
          .map((s) => runtime.sportDirectory.require(s).definition.pluginRef.id)
    ]);
    final decision = state.dailyAdjustmentDecision;
    final candidate = compileShortDailyCourse(state.todayWorkout, decision);
    final failures = candidate == null ? <String>[] : _audit(candidate);
    final fingerprint = _fingerprint();
    return DailyCoursePreview(
        id: 'daily-course-$fingerprint',
        original: state.todayWorkout,
        candidate: failures.isEmpty ? candidate : null,
        operation: operation,
        fingerprint: fingerprint,
        baseVersionId: _version,
        basePlanFingerprint: _digest(
            ref.read(fourWeekPlanControllerProvider).activePlan.toJson()),
        reason: candidate == null
            ? '当前建议没有明确且可审核的课程差异，记录建议不会改变计划。'
            : failures.isNotEmpty
                ? failures.join('\n')
                : decision.reason);
  }

  List<String> _audit(WorkoutDay candidate) {
    final state = ref.read(trainingMvpProvider);
    final executionSeconds = buildWorkoutPlayerSteps(candidate,
            deloaded: false, matchDeclaredDuration: true)
        .fold<int>(0, (total, step) => total + step.estimatedSeconds);
    if (executionSeconds > candidate.estimatedMinutes * 60) {
      return ['既有跟练步骤至少需要 ${(executionSeconds / 60).ceil()} 分钟，无法在 ${candidate.estimatedMinutes} 分钟内保留准备、主训练和冷身；请增加可用时间或仅记录建议。'];
    }
    // 今日展示可能已应用既有无器械替代；缩短流程不能顺带持久化这些动作变化。
    // 继续允许阅读和使用原有替代入口，只阻止本流程产生未经确认的课程快照。
    if (state.noEquipmentConstraint) {
      final equipment = ExerciseSubstitutionService().applyNoEquipment(
          workout: state.baseTodayWorkout, exercises: state.exercises);
      if (equipment.substitutions.isNotEmpty ||
          equipment.unresolvedExerciseNames.isNotEmpty) {
        return ['当前器械条件需要调整动作；本流程仅支持缩短原课程，请先进入计划核对动作与器械。'];
      }
    }
    final TrainingPlan plan = state.activePlan.copyWith(workoutDays: [
      for (final day in state.activePlan.workoutDays)
        day.id == candidate.id ? candidate : day
    ]);
    final rule = TrainingRuleAuditService().buildReport(plan,
        exercises: seedExercises,
        availableMinutes: state.profile.dailyAvailableMinutes);
    final race = ref.read(fourWeekPlanControllerProvider).activeRace;
    final safety = TrainingPrescriptionSafetyAuditService().auditCompiledPlan(
        plan: plan,
        profile: state.profile,
        enforceFourWeekDeload: race == null,
        racePhaseOverride: race != null);
    return [
      for (final item in rule.items)
        if (item.severity == TrainingRuleAuditSeverity.fail) item.description,
      ...safety.failures,
      if (GeneratedTrainingPlanRepository(ref.read(localStorageServiceProvider))
              .getHistory()
              .activeVersion
              ?.resourceRef !=
          null)
        ...const ResourceWorkoutBindingService().issues(plan, state.profile)
    ];
  }

  void _check(DailyCoursePreview preview) {
    preview.operation.checkActive();
    if (!ref.read(userProfileControllerProvider).isCompleted) {
      throw StateError('请先确认个人档案');
    }
    if (preview.candidate == null) throw StateError('当前只有文字建议，计划未改变');
    if (_version != preview.baseVersionId ||
        _fingerprint() != preview.fingerprint) {
      throw StateError('训练上下文已变化，请重新查看调整预览');
    }
    final locks = ref
        .read(pluginRuntimeProvider)
        .activeUseReasons('feature.training_plan');
    if (locks.isNotEmpty) throw StateError(locks.join('\n'));
    final clearance = ref.read(preExerciseClearanceControllerProvider).value;
    if (clearance == null ||
        clearance.isSaving ||
        !clearance.canActivateAt(
            ref.read(preExerciseClearanceRealtimeClockProvider)())) {
      throw StateError('训练前检查暂不可用或已失效');
    }
    if (paidPlanGenerationGateEnabled &&
        ref
                .read(membershipControllerProvider)
                .value
                ?.entitlement
                .canGeneratePlan !=
            true) {
      throw StateError('当前会员权益不支持应用新的训练课程');
    }
    final current = ref.read(trainingMvpProvider);
    final expected = compileShortDailyCourse(
        current.todayWorkout, current.dailyAdjustmentDecision);
    if (expected == null ||
        _digest(expected.toJson()) != _digest(preview.candidate!.toJson())) {
      throw StateError('课程差异已变化，请重新查看预览');
    }
    final failures = _audit(preview.candidate!);
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
  }

  Future<void> confirm(DailyCoursePreview preview) async {
    if (!dailyCourseApplyEnabled) throw StateError('当前发行已暂停课程调整，计划未改变。');
    if (_busy) throw StateError('课程调整正在保存，请勿重复确认');
    _busy = true;
    try {
      preview.operation.checkActive();
      if (ref
          .read(planAdjustmentControllerProvider)
          .adjustments
          .any((a) => a.id == preview.id)) {
        final current =
            ref.read(trainingMvpProvider).findWorkoutDay(preview.original.id);
        if (_version != preview.baseVersionId ||
            current == null ||
            _digest(current.toJson()) != _digest(preview.candidate?.toJson())) {
          throw StateError('已保存的调整不再是当前课程，请重新查看计划');
        }
        return;
      }
      await ref.read(preExerciseClearanceControllerProvider.future);
      if (paidPlanGenerationGateEnabled) {
        await ref.read(membershipControllerProvider.future);
      }
      _check(preview);
      final candidate = preview.candidate!;
      final adjustment = PlanAdjustment(
          id: preview.id,
          planId: candidate.planId,
          workoutDayId: candidate.id,
          workoutTitle: candidate.title,
          originalEstimatedMinutes: preview.original.estimatedMinutes,
          adjustedEstimatedMinutes: candidate.estimatedMinutes,
          originalIntensity: preview.original.intensity,
          adjustedIntensity: candidate.intensity,
          reason: preview.reason,
          kind: PlanAdjustmentKind.adjusted,
          adjustedAt: ref.read(dailyCourseClockProvider)(),
          sourceProposalId: preview.id,
          workoutSnapshot: candidate,
          basePlanFingerprint: preview.basePlanFingerprint,
          baseVersionId: preview.baseVersionId,
          evidenceFingerprint: preview.fingerprint);
      await ref
          .read(planAdjustmentControllerProvider.notifier)
          .commitCourseAdjustment(adjustment,
              operation: preview.operation, recheck: () => _check(preview));
      await Future<void>.delayed(Duration.zero);
      preview.operation.checkActive();
      final projected =
          ref.read(trainingMvpProvider).findWorkoutDay(candidate.id);
      if (projected == null ||
          _digest(projected.toJson()) != _digest(candidate.toJson())) {
        throw StateError('调整已保存，当前课程显示尚未刷新，请重新打开计划确认');
      }
    } finally {
      _busy = false;
    }
  }
}
