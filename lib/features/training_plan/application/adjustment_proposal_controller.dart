import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/training_metrics.dart';
import '../../../data/models/training_plan.dart';
import '../../../data/models/workout_day.dart';
import '../../../data/repositories/training_metrics_repository.dart';
import '../../../services/training_metrics_engine.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../growth/application/training_metrics_provider.dart';
import '../../profile/application/user_profile_controller.dart';
import 'plan_adjustment_controller.dart';

final acwrAdjustmentNowProvider =
    Provider<DateTime>((Ref ref) => DateTime.now());

/// 从已落库 ACWR 指标生成预览，并协调确认、拒绝和撤销的生产入口。
final acwrAdjustmentProposalControllerProvider = AsyncNotifierProvider<
    AcwrAdjustmentProposalController, AdjustmentProposalState>(
  AcwrAdjustmentProposalController.new,
  retry: (int _, Object __) => null,
);

/// 由应用层注入的计划投影边界；控制器本身不依赖具体计划仓库。
abstract interface class AdjustmentPlanProjection {
  void confirm(AdjustmentProposal proposal);

  void undo(AdjustmentProposal proposal);
}

class AdjustmentProposalState {
  const AdjustmentProposalState({
    required this.proposals,
    required this.statusMessage,
  });

  const AdjustmentProposalState.empty()
      : proposals = const <AdjustmentProposal>[],
        statusMessage = '当前没有待确认的计划调整建议。';

  final List<AdjustmentProposal> proposals;
  final String statusMessage;

  AdjustmentProposalState copyWith({
    List<AdjustmentProposal>? proposals,
    String? statusMessage,
  }) {
    return AdjustmentProposalState(
      proposals: proposals ?? this.proposals,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

/// 管理建议的确认、拒绝和撤销状态；建议创建时绝不修改训练计划。
class AdjustmentProposalController {
  AdjustmentProposalController({required AdjustmentPlanProjection projection})
      : _projection = projection;

  final AdjustmentPlanProjection _projection;
  AdjustmentProposalState _state = const AdjustmentProposalState.empty();

  AdjustmentProposalState get state => _state;

  void propose(AdjustmentProposal proposal) {
    final List<AdjustmentProposal> next = List<AdjustmentProposal>.from(
      _state.proposals,
    )..removeWhere((AdjustmentProposal item) => item.id == proposal.id);
    next.insert(0, proposal);
    _state = AdjustmentProposalState(
      proposals: List<AdjustmentProposal>.unmodifiable(next),
      statusMessage: '已生成计划调整预览，确认前训练计划不会改变。',
    );
  }

  void confirm(String proposalId, {DateTime? at}) {
    final AdjustmentProposal proposal = _requireProposal(proposalId);
    if (proposal.status != AdjustmentProposalStatus.proposed) {
      throw StateError('只有待确认建议可以执行确认。');
    }
    final AdjustmentProposal confirmed = proposal.copyWith(
      status: AdjustmentProposalStatus.confirmed,
      confirmedAt: at ?? DateTime.now(),
    );
    _projection.confirm(confirmed);
    _replace(confirmed, '已确认建议，并通过注入的计划投影边界应用。');
  }

  void reject(String proposalId, {DateTime? at}) {
    final AdjustmentProposal proposal = _requireProposal(proposalId);
    if (proposal.status != AdjustmentProposalStatus.proposed) {
      throw StateError('只有待确认建议可以拒绝。');
    }
    _replace(
      proposal.copyWith(
        status: AdjustmentProposalStatus.rejected,
        rejectedAt: at ?? DateTime.now(),
      ),
      '已拒绝建议，训练计划未改变。',
    );
  }

  void undo(String proposalId, {DateTime? at}) {
    final AdjustmentProposal proposal = _requireProposal(proposalId);
    if (proposal.status != AdjustmentProposalStatus.confirmed) {
      throw StateError('只有已确认建议可以撤销。');
    }
    final AdjustmentProposal undone = proposal.copyWith(
      status: AdjustmentProposalStatus.undone,
      undoneAt: at ?? DateTime.now(),
    );
    _projection.undo(undone);
    _replace(undone, '已撤销计划调整并保留审计记录。');
  }

  AdjustmentProposal _requireProposal(String proposalId) {
    for (final AdjustmentProposal proposal in _state.proposals) {
      if (proposal.id == proposalId) return proposal;
    }
    throw StateError('没有找到对应的计划调整建议。');
  }

  void _replace(AdjustmentProposal nextProposal, String statusMessage) {
    final List<AdjustmentProposal> next = <AdjustmentProposal>[
      for (final AdjustmentProposal proposal in _state.proposals)
        if (proposal.id == nextProposal.id) nextProposal else proposal,
    ];
    _state = AdjustmentProposalState(
      proposals: List<AdjustmentProposal>.unmodifiable(next),
      statusMessage: statusMessage,
    );
  }
}

/// ACWR 建议的持久化生产控制器。
///
/// 生成建议只写建议表；只有用户明确确认后才调用现有计划调整控制器。
class AcwrAdjustmentProposalController
    extends AsyncNotifier<AdjustmentProposalState> {
  final AcwrAdjustmentProposalFactory _factory =
      const AcwrAdjustmentProposalFactory();

  late TrainingMetricsRepository _repository;
  late String _athleteProfileId;
  String? _currentApplicableProposalId;
  bool _operationInProgress = false;

  @override
  Future<AdjustmentProposalState> build() async {
    _repository = ref.watch(trainingMetricsRepositoryProvider);
    _athleteProfileId = ref.watch(
      userProfileControllerProvider.select(
        (UserProfileState value) => value.profile.id,
      ),
    );
    if (_athleteProfileId.trim().isEmpty) {
      return const AdjustmentProposalState.empty();
    }

    final List<AdjustmentProposal> proposals =
        await _repository.listAdjustmentProposals(
      athleteProfileId: _athleteProfileId,
    );
    final List<MetricAggregate> metrics = await _repository.listAggregates(
      athleteProfileId: _athleteProfileId,
      period: MetricPeriod.week,
    );
    final TrainingMvpState training = ref.read(trainingMvpProvider);
    final TrainingPlan? plan =
        training.plans.isEmpty ? null : training.plans.first;
    final AdjustmentProposal? generated = plan == null
        ? null
        : _factory.build(
            metrics: metrics,
            plan: plan,
            athleteProfileId: _athleteProfileId,
            now: ref.read(acwrAdjustmentNowProvider),
          );
    _currentApplicableProposalId = generated?.id;

    final List<AdjustmentProposal> next = List<AdjustmentProposal>.from(
      proposals,
    );
    if (generated != null &&
        !next.any((AdjustmentProposal item) => item.id == generated.id)) {
      await _repository.saveAdjustmentProposal(generated);
      next.insert(0, generated);
    }
    _sortProposals(next);
    return AdjustmentProposalState(
      proposals: List<AdjustmentProposal>.unmodifiable(next),
      statusMessage: next.isEmpty
          ? '当前没有待确认的计划调整建议。'
          : generated != null
              ? '已读取负荷建议；确认前训练计划不会改变。'
              : '已读取历史计划调整建议。',
    );
  }

  Future<void> confirm(String proposalId, {DateTime? at}) async {
    if (_operationInProgress) return;
    final AdjustmentProposalState? current = state.value;
    if (current == null) return;
    final AdjustmentProposal proposal = _requireProposal(current, proposalId);
    if (proposal.status != AdjustmentProposalStatus.proposed) {
      _setStatus('只有待确认建议可以执行确认。');
      return;
    }
    if (proposal.id != _currentApplicableProposalId) {
      _setStatus('触发指标或计划已更新，请按最新数据重新查看建议；训练计划未改变。');
      return;
    }
    final TrainingMvpState training = ref.read(trainingMvpProvider);
    final WorkoutDay? workout = proposal.workoutDayId == null
        ? null
        : training.findWorkoutDay(proposal.workoutDayId!);
    final List<WorkoutDay> weeklyWorkouts = proposal.workoutDayId == null
        ? proposal.workoutChanges
            .map(
              (AdjustmentProposalWorkoutChange change) =>
                  training.findWorkoutDay(change.workoutDayId),
            )
            .whereType<WorkoutDay>()
            .toList(growable: false)
        : const <WorkoutDay>[];
    if (proposal.workoutDayId != null && workout == null) {
      _setStatus('没有找到建议对应的训练日，计划未改变。');
      return;
    }
    if (proposal.workoutDayId == null &&
        (proposal.workoutChanges.isEmpty ||
            weeklyWorkouts.length != proposal.workoutChanges.length)) {
      _setStatus('周总量建议与当前训练日不完整匹配，计划未改变。');
      return;
    }

    _operationInProgress = true;
    final AdjustmentProposal confirmed = proposal.copyWith(
      status: AdjustmentProposalStatus.confirmed,
      confirmedAt: at ?? DateTime.now(),
    );
    try {
      await _repository.saveAdjustmentProposal(confirmed);
      try {
        final PlanAdjustmentController controller =
            ref.read(planAdjustmentControllerProvider.notifier);
        if (confirmed.workoutDayId == null) {
          controller.applyConfirmedWeeklyProposal(
            proposal: confirmed,
            currentWorkouts: weeklyWorkouts,
          );
        } else {
          controller.applyConfirmedProposal(
            proposal: confirmed,
            currentWorkout: workout!,
          );
        }
      } catch (_) {
        await _repository.saveAdjustmentProposal(proposal);
        rethrow;
      }
      _replace(
        confirmed,
        confirmed.workoutDayId == null
            ? '已确认并原子应用下周总量调整，可整组撤销。'
            : '已确认并应用单项训练调整，可随时撤销。',
      );
    } catch (error) {
      _setStatus('确认失败：${_errorText(error)}');
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> reject(String proposalId, {DateTime? at}) async {
    if (_operationInProgress) return;
    final AdjustmentProposalState? current = state.value;
    if (current == null) return;
    final AdjustmentProposal proposal = _requireProposal(current, proposalId);
    if (proposal.status != AdjustmentProposalStatus.proposed) {
      _setStatus('只有待确认建议可以拒绝。');
      return;
    }

    _operationInProgress = true;
    final AdjustmentProposal rejected = proposal.copyWith(
      status: AdjustmentProposalStatus.rejected,
      rejectedAt: at ?? DateTime.now(),
    );
    try {
      await _repository.saveAdjustmentProposal(rejected);
      _replace(rejected, '已拒绝建议，训练计划未改变。');
    } catch (error) {
      _setStatus('拒绝失败：${_errorText(error)}');
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> undo(String proposalId, {DateTime? at}) async {
    if (_operationInProgress) return;
    final AdjustmentProposalState? current = state.value;
    if (current == null) return;
    final AdjustmentProposal proposal = _requireProposal(current, proposalId);
    if (proposal.status != AdjustmentProposalStatus.confirmed) {
      _setStatus('只有已确认建议可以撤销。');
      return;
    }

    _operationInProgress = true;
    final AdjustmentProposal undone = proposal.copyWith(
      status: AdjustmentProposalStatus.undone,
      undoneAt: at ?? DateTime.now(),
    );
    try {
      await _repository.saveAdjustmentProposal(undone);
      try {
        ref
            .read(planAdjustmentControllerProvider.notifier)
            .undoConfirmedProposal(undone);
      } catch (_) {
        await _repository.saveAdjustmentProposal(proposal);
        rethrow;
      }
      _replace(
        undone,
        undone.workoutChanges.isNotEmpty
            ? '已整组撤销周总量调整并恢复确认前计划，审计记录保留。'
            : '已撤销调整并恢复确认前计划，审计记录保留。',
      );
    } catch (error) {
      _setStatus('撤销失败：${_errorText(error)}');
    } finally {
      _operationInProgress = false;
    }
  }

  AdjustmentProposal _requireProposal(
    AdjustmentProposalState current,
    String proposalId,
  ) {
    for (final AdjustmentProposal proposal in current.proposals) {
      if (proposal.id == proposalId) return proposal;
    }
    throw StateError('没有找到对应的计划调整建议。');
  }

  void _replace(AdjustmentProposal proposal, String statusMessage) {
    final AdjustmentProposalState? current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        proposals: List<AdjustmentProposal>.unmodifiable(
          <AdjustmentProposal>[
            for (final AdjustmentProposal item in current.proposals)
              if (item.id == proposal.id) proposal else item,
          ],
        ),
        statusMessage: statusMessage,
      ),
    );
  }

  void _setStatus(String statusMessage) {
    final AdjustmentProposalState? current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(statusMessage: statusMessage));
  }
}

/// 把最新且可验证的 ACWR 指标转换为确定性的计划差异预览。
class AcwrAdjustmentProposalFactory {
  const AcwrAdjustmentProposalFactory();

  AdjustmentProposal? build({
    required List<MetricAggregate> metrics,
    required TrainingPlan plan,
    required String athleteProfileId,
    required DateTime now,
  }) {
    final MetricAggregate? metric = _latestCurrentAcwr(metrics, now);
    if (metric == null) return null;

    final List<int> futureWeekIndexes = plan.workoutDays
        .map((WorkoutDay item) => item.weekIndex)
        .where((int value) => value > 1)
        .toSet()
        .toList()
      ..sort();
    if (futureWeekIndexes.isEmpty) return null;
    final int nextWeekIndex = futureWeekIndexes.first;
    final List<WorkoutDay> nextWeek = plan.workoutDays
        .where((WorkoutDay item) => item.weekIndex == nextWeekIndex)
        .toList()
      ..sort((WorkoutDay first, WorkoutDay second) =>
          first.dayIndex.compareTo(second.dayIndex));

    WorkoutDay? highIntensityWorkout;
    String? loweredIntensity;
    for (final WorkoutDay workout in nextWeek) {
      final String? candidate = _lowerExplicitRpe(workout);
      if (candidate != null) {
        highIntensityWorkout = workout;
        loweredIntensity = candidate;
        break;
      }
    }

    final int totalMinutes = nextWeek
        .where((WorkoutDay item) => item.trainingType != TrainingType.rest)
        .fold<int>(
            0, (int total, WorkoutDay item) => total + item.estimatedMinutes);
    if (highIntensityWorkout == null && totalMinutes <= 0) return null;
    final List<AdjustmentProposalWorkoutChange> weeklyChanges =
        highIntensityWorkout == null
            ? _buildWeeklyDurationChanges(nextWeek)
            : const <AdjustmentProposalWorkoutChange>[];
    if (highIntensityWorkout == null && weeklyChanges.isEmpty) return null;

    final AcwrResult result = AcwrResult(
      status: metric.status,
      method: metric.loadMethod,
      ratio: metric.value,
      acuteTotal: (metric.metadata['acuteTotal'] as num?)?.toDouble() ?? 0,
      chronicTotal: (metric.metadata['chronicTotal'] as num?)?.toDouble() ?? 0,
      coverage: metric.coverage,
      reason: metric.metadata['reason'] as String? ?? '同口径 28 天负荷信号。',
    );
    final TrainingMetricsEngine engine = TrainingMetricsEngine();
    final bool hasHighIntensityWorkout = highIntensityWorkout != null;
    final AdjustmentProposal? preview = engine.buildAcwrProposal(
      result: result,
      athleteProfileId: athleteProfileId,
      planId: plan.id,
      workoutDayId: highIntensityWorkout?.id,
      workoutTitle: highIntensityWorkout?.title ?? '下周训练总目标',
      originalMinutes: highIntensityWorkout?.estimatedMinutes ?? totalMinutes,
      originalIntensity: highIntensityWorkout?.intensity ?? '按训练日分别执行',
      hasHighIntensityWorkout: hasHighIntensityWorkout,
      now: now,
    );
    if (preview == null) return null;

    return AdjustmentProposal(
      id: 'adjustment-proposal:${Uri.encodeComponent(metric.id)}:'
          '${Uri.encodeComponent(plan.id)}',
      athleteProfileId: preview.athleteProfileId,
      planId: preview.planId,
      workoutDayId: preview.workoutDayId,
      workoutTitle: preview.workoutTitle,
      triggerMetricCode: preview.triggerMetricCode,
      triggerAlgorithmVersion: preview.triggerAlgorithmVersion,
      explanation: preview.explanation,
      originalMinutes: preview.originalMinutes,
      adjustedMinutes: weeklyChanges.isEmpty
          ? preview.adjustedMinutes
          : weeklyChanges.fold<int>(
              0,
              (int total, AdjustmentProposalWorkoutChange change) =>
                  total + change.adjustedMinutes,
            ),
      originalIntensity: preview.originalIntensity,
      adjustedIntensity: loweredIntensity ?? preview.adjustedIntensity,
      status: preview.status,
      createdAt: preview.createdAt,
      workoutChanges: weeklyChanges,
    );
  }

  List<AdjustmentProposalWorkoutChange> _buildWeeklyDurationChanges(
    List<WorkoutDay> workouts,
  ) {
    final List<WorkoutDay> active = workouts
        .where((WorkoutDay item) => item.trainingType != TrainingType.rest)
        .toList(growable: false);
    if (active.isEmpty ||
        active.any((WorkoutDay item) => item.estimatedMinutes < 5)) {
      return const <AdjustmentProposalWorkoutChange>[];
    }
    final int originalTotal = active.fold<int>(
      0,
      (int total, WorkoutDay item) => total + item.estimatedMinutes,
    );
    final int targetTotal = (originalTotal * 0.9)
        .round()
        .clamp(active.length * 5, originalTotal)
        .toInt();
    if (targetTotal >= originalTotal) {
      return const <AdjustmentProposalWorkoutChange>[];
    }

    final Map<String, int> adjustedById = <String, int>{};
    final Map<String, double> fractionalById = <String, double>{};
    int assigned = 0;
    for (final WorkoutDay workout in active) {
      final double ideal =
          workout.estimatedMinutes * targetTotal / originalTotal;
      final int base = ideal.floor().clamp(5, workout.estimatedMinutes).toInt();
      adjustedById[workout.id] = base;
      fractionalById[workout.id] = ideal - ideal.floor();
      assigned += base;
    }
    final List<WorkoutDay> allocationOrder = List<WorkoutDay>.from(active)
      ..sort((WorkoutDay first, WorkoutDay second) {
        final int byFraction = (fractionalById[second.id] ?? 0)
            .compareTo(fractionalById[first.id] ?? 0);
        return byFraction != 0
            ? byFraction
            : first.dayIndex.compareTo(second.dayIndex);
      });
    int remaining = targetTotal - assigned;
    while (remaining > 0) {
      bool allocated = false;
      for (final WorkoutDay workout in allocationOrder) {
        final int current = adjustedById[workout.id]!;
        if (current >= workout.estimatedMinutes) continue;
        adjustedById[workout.id] = current + 1;
        remaining -= 1;
        allocated = true;
        if (remaining == 0) break;
      }
      if (!allocated) return const <AdjustmentProposalWorkoutChange>[];
    }

    return List<AdjustmentProposalWorkoutChange>.unmodifiable(
      active.map(
        (WorkoutDay workout) => AdjustmentProposalWorkoutChange(
          workoutDayId: workout.id,
          workoutTitle: workout.title,
          originalMinutes: workout.estimatedMinutes,
          adjustedMinutes: adjustedById[workout.id]!,
          originalIntensity: workout.intensity,
          adjustedIntensity: workout.intensity,
        ),
      ),
    );
  }

  MetricAggregate? _latestCurrentAcwr(
    List<MetricAggregate> metrics,
    DateTime now,
  ) {
    final DateTime monday = _mondayOf(now);
    final DateTime oldestAccepted = monday.subtract(const Duration(days: 7));
    final DateTime newestAccepted = monday.add(const Duration(days: 7));
    final List<MetricAggregate> eligible = metrics
        .where(
          (MetricAggregate item) =>
              item.period == MetricPeriod.week &&
              (item.metricCode == 'acwr' ||
                  item.metricCode.startsWith('acwr.')) &&
              item.status == MetricStatus.ready &&
              item.algorithmVersion ==
                  TrainingMetricsEngine.acwrAlgorithmVersion &&
              item.loadMethod != null &&
              item.value != null &&
              item.metadata['windowCoverageVerified'] == true &&
              !item.periodStart.isBefore(oldestAccepted) &&
              item.periodStart.isBefore(newestAccepted),
        )
        .toList()
      ..sort((MetricAggregate first, MetricAggregate second) {
        final int byComputed = second.computedAt.compareTo(first.computedAt);
        return byComputed != 0 ? byComputed : second.id.compareTo(first.id);
      });
    return eligible.isEmpty ? null : eligible.first;
  }

  String? _lowerExplicitRpe(WorkoutDay workout) {
    if (workout.trainingType != TrainingType.intervalRun &&
        workout.trainingType != TrainingType.tempoRun &&
        workout.trainingType != TrainingType.hyrox) {
      return null;
    }
    final RegExpMatch? match = RegExp(r'^RPE\s+(\d+)(?:-(\d+))?$')
        .firstMatch(workout.intensity.trim());
    if (match == null) return null;
    final int lower = int.parse(match.group(1)!);
    final int upper = int.parse(match.group(2) ?? match.group(1)!);
    if (upper < 6 || lower <= 1) return null;
    final int adjustedLower = lower - 1;
    final int adjustedUpper = upper - 1;
    return adjustedLower == adjustedUpper
        ? 'RPE $adjustedLower'
        : 'RPE $adjustedLower-$adjustedUpper';
  }

  DateTime _mondayOf(DateTime value) {
    final DateTime date = DateTime(value.year, value.month, value.day);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }
}

void _sortProposals(List<AdjustmentProposal> proposals) {
  proposals.sort((AdjustmentProposal first, AdjustmentProposal second) {
    final int byTime = second.createdAt.compareTo(first.createdAt);
    return byTime != 0 ? byTime : second.id.compareTo(first.id);
  });
}

String _errorText(Object error) {
  if (error is StateError) return error.message.toString();
  return '本地保存失败，请稍后重试。';
}
