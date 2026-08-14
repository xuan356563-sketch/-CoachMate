import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/pre_exercise_clearance.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../training_plan/application/pre_exercise_clearance_controller.dart';
import '../../workout_player/application/workout_player_assist_controller.dart';
import '../data/guided_workout_catalog_loader.dart';
import '../domain/guided_workout_course.dart';

String? guidedWorkoutStartBlocker(
  PreExerciseClearance clearance,
  DateTime now,
) {
  if (clearance.isValidAt(now)) return null;
  return clearance.blockingReasonAt(now);
}

class GuidedWorkoutCourseSection extends StatelessWidget {
  final List<GuidedWorkoutCourse> courses;
  final ValueChanged<String> onSelected;
  final String title;

  const GuidedWorkoutCourseSection({
    super.key,
    required this.courses,
    required this.onSelected,
    this.title = '跳绳跟练课程',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: title),
        for (final GuidedWorkoutCourse course in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TrainFlowCard(
              key: ValueKey<String>('guided-workout-course-${course.id}'),
              onTap: () => onSelected(course.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.sports_gymnastics,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          course.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      ToneBadge(label: course.levelLabel),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    course.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: InfoRow(
                          label: '时长',
                          value: course.durationLabel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InfoRow(
                          label: '阶段',
                          value: '${course.phases.length} 个',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class GuidedWorkoutCatalogPage extends ConsumerWidget {
  const GuidedWorkoutCatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GuidedWorkoutCatalog> catalog =
        ref.watch(guidedWorkoutCatalogProvider);
    return TrainFlowPage(
      title: '跳绳跟练',
      subtitle: '按语音完成热身、间歇、变式、降温和拉伸。',
      eyebrow: '配置化课程',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.plans,
      ),
      children: [
        catalog.when(
          data: (GuidedWorkoutCatalog value) => GuidedWorkoutCourseSection(
            courses: value.courses
                .where(
                  (GuidedWorkoutCourse course) =>
                      course.kind == GuidedWorkoutCourseKind.timedCourse,
                )
                .toList(growable: false),
            onSelected: (String id) =>
                context.push(AppRoutes.guidedWorkoutDetail(id)),
          ),
          loading: () => const TrainFlowCard(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace stackTrace) => TrainFlowCard(
            child: Text('跳绳课程读取失败：$error'),
          ),
        ),
      ],
    );
  }
}

class FunctionalCircuitDetailPage extends ConsumerStatefulWidget {
  final String courseId;

  const FunctionalCircuitDetailPage({
    super.key,
    required this.courseId,
  });

  @override
  ConsumerState<FunctionalCircuitDetailPage> createState() =>
      _FunctionalCircuitDetailPageState();
}

class _FunctionalCircuitDetailPageState
    extends ConsumerState<FunctionalCircuitDetailPage> {
  int? _selectedRounds;
  final Set<int> _confirmedChecks = <int>{};

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GuidedWorkoutCatalog> catalog =
        ref.watch(guidedWorkoutCatalogProvider);
    final AsyncValue<PreExerciseClearanceState> clearance =
        ref.watch(preExerciseClearanceControllerProvider);
    final TrainingMvpState trainingState = ref.watch(trainingMvpProvider);
    return catalog.when(
      loading: () => const _CircuitLoadingPage(message: '正在读取功能性训练循环…'),
      error: (Object error, StackTrace stackTrace) =>
          _CircuitLoadingPage(message: '功能性训练循环读取失败：$error'),
      data: (GuidedWorkoutCatalog value) {
        final GuidedWorkoutCourse? course = value.findById(widget.courseId);
        if (course == null ||
            course.kind != GuidedWorkoutCourseKind.functionalCircuit) {
          return const TrainFlowPage(
            title: '循环不存在',
            leading: TrainMateBackButton(fallbackRoute: AppRoutes.exercises),
            children: [TrainFlowCard(child: Text('没有找到这套功能性训练循环。'))],
          );
        }
        final int selectedRounds = _selectedRounds ?? course.defaultRounds;
        return TrainFlowPage(
          title: course.title,
          subtitle: course.description,
          eyebrow: '小肌群 · 功能性',
          leading: const TrainMateBackButton(fallbackRoute: AppRoutes.exercises),
          children: [
            TrainFlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '动作顺序',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  for (final GuidedWorkoutExercise exercise
                      in course.phases.expand(
                    (GuidedWorkoutPhase phase) => phase.exercises,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InfoRow(
                        label: exercise.name,
                        value: exercise.repetitionLabel,
                      ),
                    ),
                ],
              ),
            ),
            TrainFlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择轮次',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final int rounds in course.roundOptions)
                        ChoiceChip(
                          label: Text('$rounds 轮 · ${rounds * course.exerciseSetCount} 个动作'),
                          selected: selectedRounds == rounds,
                          onSelected: (_) => setState(
                            () => _selectedRounds = rounds,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            TrainFlowCard(
              tone: TrainFlowCardTone.peach,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '开始前确认',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text('如出现严重肿胀、不能负重、关节锁住或打软腿、红热伴发热，请不要开始本循环。'),
                  for (int index = 0;
                      index < course.preflightChecks.length;
                      index += 1)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _confirmedChecks.contains(index),
                      title: Text(course.preflightChecks[index]),
                      onChanged: (bool? value) => setState(() {
                        if (value == true) {
                          _confirmedChecks.add(index);
                        } else {
                          _confirmedChecks.remove(index);
                        }
                      }),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey<String>('functional-circuit-start'),
                onPressed: clearance.value == null ||
                        _confirmedChecks.length != course.preflightChecks.length
                    ? null
                    : () => _start(
                          context,
                          course,
                          selectedRounds,
                          clearance.value!.clearance,
                          trainingState,
                        ),
                icon: const Icon(Icons.play_arrow),
                label: Text('开始 $selectedRounds 轮跟练'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _start(
    BuildContext context,
    GuidedWorkoutCourse course,
    int rounds,
    PreExerciseClearance clearance,
    TrainingMvpState trainingState,
  ) {
    final DateTime now = ref.read(preExerciseClearanceRealtimeClockProvider)();
    final String? clearanceBlocker = guidedWorkoutStartBlocker(clearance, now);
    final painLog = trainingState.latestPainLog;
    final String? painBlocker = painLog?.requiresMedicalAttention == true
        ? '${painLog!.medicalAttentionReason}，请先停止训练并寻求专业评估。'
        : painLog?.shouldDeloadTraining == true
            ? '${painLog!.bodyPart}当前疼痛 ${painLog.painLevel}/10，暂不启动此循环。'
            : null;
    final String? blocker = clearanceBlocker ?? painBlocker;
    if (blocker != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blocker)),
      );
      return;
    }
    ref
        .read(workoutPlayerAssistControllerProvider.notifier)
        .replaceQueueWithCue('功能性训练循环准备开始');
    context.push(AppRoutes.exerciseCircuitSession(course.id, rounds: rounds));
  }
}

class _CircuitLoadingPage extends StatelessWidget {
  final String message;

  const _CircuitLoadingPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: '功能性循环',
      leading: const TrainMateBackButton(fallbackRoute: AppRoutes.exercises),
      children: [TrainFlowCard(child: Text(message))],
    );
  }
}

class GuidedWorkoutCourseDetailPage extends ConsumerWidget {
  final String courseId;

  const GuidedWorkoutCourseDetailPage({
    super.key,
    required this.courseId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GuidedWorkoutCatalog> catalog =
        ref.watch(guidedWorkoutCatalogProvider);
    final AsyncValue<PreExerciseClearanceState> clearance =
        ref.watch(preExerciseClearanceControllerProvider);
    return catalog.when(
      loading: () => const TrainFlowPage(
        title: '跳绳课程',
        leading: TrainMateBackButton(
          fallbackRoute: AppRoutes.guidedWorkouts,
        ),
        children: [
          TrainFlowCard(
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (Object error, StackTrace stackTrace) => TrainFlowPage(
        title: '跳绳课程',
        leading: const TrainMateBackButton(
          fallbackRoute: AppRoutes.guidedWorkouts,
        ),
        children: [
          TrainFlowCard(child: Text('跳绳课程读取失败：$error')),
        ],
      ),
      data: (GuidedWorkoutCatalog value) {
        final GuidedWorkoutCourse? course = value.findById(courseId);
        if (course == null) {
          return TrainFlowPage(
            title: '课程不存在',
            leading: const TrainMateBackButton(
              fallbackRoute: AppRoutes.guidedWorkouts,
            ),
            children: const [
              TrainFlowCard(child: Text('没有找到这套跳绳课程。')),
            ],
          );
        }
        return TrainFlowPage(
          title: course.title,
          subtitle: course.description,
          eyebrow: '${course.levelLabel} · ${course.durationLabel}',
          leading: const TrainMateBackButton(
            fallbackRoute: AppRoutes.guidedWorkouts,
          ),
          children: [
            TrainFlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '课程结构',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  for (final GuidedWorkoutPhase phase in course.phases)
                    InfoRow(
                      label: phase.name,
                      value: '${phase.totalDurationSeconds ~/ 60} 分钟',
                    ),
                ],
              ),
            ),
            const TrainFlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '开始前确认',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text('准备跳绳和防滑空间，穿着有缓冲的运动鞋。'),
                  SizedBox(height: 6),
                  Text('出现胸痛、明显头晕、呼吸异常或疼痛加重时立即停止训练。'),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey<String>('guided-workout-start'),
                onPressed: clearance.value == null
                    ? null
                    : () => _start(context, ref, clearance.value!.clearance),
                icon: const Icon(Icons.play_arrow),
                label: Text('开始跟练 · ${course.durationLabel}'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _start(
    BuildContext context,
    WidgetRef ref,
    PreExerciseClearance clearance,
  ) {
    final DateTime now = ref.read(preExerciseClearanceRealtimeClockProvider)();
    final String? blocker = guidedWorkoutStartBlocker(clearance, now);
    if (blocker != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(blocker),
          action: SnackBarAction(
            label: '去完成筛查',
            onPressed: () => context.push(AppRoutes.planGenerate),
          ),
        ),
      );
      return;
    }
    ref
        .read(workoutPlayerAssistControllerProvider.notifier)
        .replaceQueueWithCue('跳绳跟练准备开始');
    context.push(AppRoutes.guidedWorkoutSession(courseId));
  }
}
