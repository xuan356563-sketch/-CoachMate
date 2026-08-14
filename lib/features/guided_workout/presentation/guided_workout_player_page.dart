import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/exercise_media.dart';
import '../../../core/widgets/trainmate_showcase_widgets.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/exercise.dart';
import '../../../data/models/pre_exercise_clearance.dart';
import '../../../data/models/training_log.dart';
import '../../training_log/application/training_log_controller.dart';
import '../../dashboard/training_mvp_controller.dart';
import '../../training_plan/application/pre_exercise_clearance_controller.dart';
import '../../workout_player/application/workout_player_assist_controller.dart';
import '../application/guided_workout_engine.dart';
import '../application/guided_workout_log_builder.dart';
import '../data/guided_workout_catalog_loader.dart';
import '../domain/guided_workout_course.dart';
import 'guided_workout_pages.dart';

class GuidedWorkoutPlayerPage extends ConsumerStatefulWidget {
  final String courseId;
  final int? selectedRounds;
  final String? fallbackRoute;

  const GuidedWorkoutPlayerPage({
    super.key,
    required this.courseId,
    this.selectedRounds,
    this.fallbackRoute,
  });

  @override
  ConsumerState<GuidedWorkoutPlayerPage> createState() =>
      _GuidedWorkoutPlayerPageState();
}

class _GuidedWorkoutPlayerPageState
    extends ConsumerState<GuidedWorkoutPlayerPage> with WidgetsBindingObserver {
  GuidedWorkoutEngine? _engine;
  Timer? _refreshTimer;
  bool _initializing = false;
  bool _saved = false;
  bool _exitDialogVisible = false;
  late final WorkoutPlayerAssistController _assistController;
  late final String _sessionId =
      'guided-workout-${DateTime.now().microsecondsSinceEpoch}';

  String get _detailRoute =>
      widget.fallbackRoute ?? AppRoutes.guidedWorkoutDetail(widget.courseId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _assistController = ref.read(
      workoutPlayerAssistControllerProvider.notifier,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _engine?.removeListener(_onEngineChanged);
    _engine?.dispose();
    unawaited(
      Future<void>.microtask(
        () => _assistController.setScreenAwake(
          false,
          enabledMessage: '训练进行中，屏幕保持常亮。',
          disabledMessage: '已释放屏幕常亮。',
        ),
      ),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final GuidedWorkoutEngine? engine = _engine;
    if (engine == null) return;
    if (state == AppLifecycleState.resumed) {
      engine.reconcile();
      _drainVoiceEvents();
      if (engine.state.status == GuidedWorkoutStatus.running) {
        ref.read(workoutPlayerAssistControllerProvider.notifier).setScreenAwake(
              true,
              enabledMessage: '训练进行中，屏幕保持常亮。',
              disabledMessage: '已释放屏幕常亮。',
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<GuidedWorkoutCatalog> catalog =
        ref.watch(guidedWorkoutCatalogProvider);
    final AsyncValue<PreExerciseClearanceState> clearance =
        ref.watch(preExerciseClearanceControllerProvider);
    final WorkoutPlayerAssistState assist =
        ref.watch(workoutPlayerAssistControllerProvider);
    final TrainingMvpState trainingState = ref.watch(trainingMvpProvider);

    return catalog.when(
      loading: () => _PlayerLoadingPage(
        courseId: widget.courseId,
        fallbackRoute: _detailRoute,
        message: '正在读取跳绳课程…',
      ),
      error: (Object error, StackTrace stackTrace) => _PlayerLoadingPage(
        courseId: widget.courseId,
        fallbackRoute: _detailRoute,
        message: '跳绳课程读取失败：$error',
      ),
      data: (GuidedWorkoutCatalog value) {
        final GuidedWorkoutCourse? course = value.findById(widget.courseId);
        if (course == null) {
          return _PlayerLoadingPage(
            courseId: widget.courseId,
            fallbackRoute: _detailRoute,
            message: '没有找到这套跳绳课程。',
          );
        }
        final PreExerciseClearance? currentClearance =
            clearance.value?.clearance;
        if (currentClearance == null) {
          return _PlayerLoadingPage(
            courseId: widget.courseId,
            fallbackRoute: _detailRoute,
            message: '正在核对运动前筛查状态…',
          );
        }
        final String? blocker = guidedWorkoutStartBlocker(
          currentClearance,
          ref.read(preExerciseClearanceRealtimeClockProvider)(),
        );
        if (blocker != null) {
          return TrainFlowPage(
            title: '开始前需要完成筛查',
            leading: TrainMateBackButton(
              fallbackRoute: _detailRoute,
            ),
            children: [
              TrainFlowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(blocker),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.push(AppRoutes.planGenerate),
                      child: const Text('去完成筛查'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        _ensureInitialized(course);
        final GuidedWorkoutEngine? engine = _engine;
        if (engine == null) {
          return _PlayerLoadingPage(
            courseId: widget.courseId,
            fallbackRoute: _detailRoute,
            message: '正在准备跟练计时器…',
          );
        }
        return PopScope(
          canPop: engine.state.status == GuidedWorkoutStatus.completed,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) unawaited(_requestExit());
          },
          child: _buildPlayer(context, course, engine, assist, trainingState),
        );
      },
    );
  }

  Widget _buildPlayer(
    BuildContext context,
    GuidedWorkoutCourse course,
    GuidedWorkoutEngine engine,
    WorkoutPlayerAssistState assist,
    TrainingMvpState trainingState,
  ) {
    final GuidedWorkoutState state = engine.state;
    if (state.status == GuidedWorkoutStatus.completed) {
      return TrainFlowPage(
        title: '跟练完成',
        subtitle: course.title,
        eyebrow: '训练总结',
        leading: TrainMateBackButton(
          fallbackRoute: _detailRoute,
        ),
        children: [
          TrainFlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本次完成情况',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                InfoRow(
                  label: '实际用时',
                  value: _formatElapsed(state.elapsedMilliseconds),
                ),
                InfoRow(
                  label: '完成动作',
                  value:
                      '${state.completedExerciseCount}/${state.plannedExerciseCount}',
                ),
                InfoRow(
                  label: '跳过动作',
                  value: '${state.skippedExerciseCount}',
                ),
                InfoRow(
                  label: '完成率',
                  value: '${state.completionPercentage}%',
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go(
                course.kind == GuidedWorkoutCourseKind.functionalCircuit
                    ? AppRoutes.exercises
                    : AppRoutes.plans,
              ),
              icon: const Icon(Icons.check),
              label: Text(
                course.kind == GuidedWorkoutCourseKind.functionalCircuit
                    ? '返回动作库'
                    : '返回训练计划',
              ),
            ),
          ),
        ],
      );
    }

    final GuidedWorkoutSegment segment = state.segment;
    final GuidedWorkoutSegment? next = engine.nextExerciseSegment;
    return TrainMateImmersivePage(
      title: course.title,
      subtitle: '全程听语音即可完成，音乐和耳机媒体按键保持由音乐 App 控制。',
      leading: TrainMateBackButton(
        fallbackRoute: _detailRoute,
        onPressed: _requestExit,
      ),
      children: [
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            children: [
              Text(
                segment.kind == GuidedWorkoutSegmentKind.rest
                    ? '休息'
                    : segment.exercise.name,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: segment.kind == GuidedWorkoutSegmentKind.exercise &&
                        segment.exercise.completionMode ==
                            GuidedWorkoutCompletionMode.repetitions
                    ? '第 ${segment.roundIndex}/${segment.roundCount} 轮，${segment.exercise.repetitionLabel}'
                    : '剩余时间 ${state.remainingLabel}',
                child: Text(
                  segment.kind == GuidedWorkoutSegmentKind.exercise &&
                          segment.exercise.completionMode ==
                              GuidedWorkoutCompletionMode.repetitions
                      ? '第 ${segment.roundIndex}/${segment.roundCount} 轮\n${segment.exercise.repetitionLabel}'
                      : state.remainingLabel,
                  key: const ValueKey<String>('guided-workout-countdown'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: state.overallProgress,
                minHeight: 10,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 8),
              Text(
                '已完成 ${state.completedExerciseCount} · '
                '跳过 ${state.skippedExerciseCount} · '
                '共 ${state.plannedExerciseCount} 组',
              ),
            ],
          ),
        ),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                segment.kind == GuidedWorkoutSegmentKind.rest
                    ? '调整呼吸和站位'
                    : '动作要领',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (segment.kind == GuidedWorkoutSegmentKind.exercise)
                for (final String cue in segment.exercise.cues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $cue'),
                  )
              else
                Text('下一组：${next?.exercise.name ?? '进入训练总结'}'),
              const SizedBox(height: 10),
              InfoRow(
                label: '下一个动作',
                value: next?.exercise.name ?? '训练结束',
              ),
            ],
          ),
        ),
        if (segment.kind == GuidedWorkoutSegmentKind.exercise &&
            segment.exercise.libraryExerciseId != null)
          _LinkedExerciseMedia(
            exerciseId: segment.exercise.libraryExerciseId!,
            exercises: trainingState.exercises,
          ),
        _PlayerControls(
          running: state.status == GuidedWorkoutStatus.running,
          voiceEnabled: assist.voiceEnabled,
          onPauseResume: _togglePause,
          onPrevious: engine.goToPrevious,
          onSkip: engine.skipCurrent,
          showComplete: segment.kind == GuidedWorkoutSegmentKind.exercise &&
              segment.exercise.completionMode ==
                  GuidedWorkoutCompletionMode.repetitions,
          onComplete: () {
            engine.completeCurrent();
            _drainVoiceEvents();
          },
          onToggleVoice: () => ref
              .read(workoutPlayerAssistControllerProvider.notifier)
              .toggleVoice(),
        ),
        Text(
          assist.screenAwakeStatusMessage,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }

  void _ensureInitialized(GuidedWorkoutCourse course) {
    if (_engine != null || _initializing) return;
    _initializing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _engine != null) return;
      final GuidedWorkoutEngine engine = GuidedWorkoutEngine(
        course: course,
        selectedRounds: widget.selectedRounds,
      );
      engine.addListener(_onEngineChanged);
      engine.start();
      _engine = engine;
      if (course.kind == GuidedWorkoutCourseKind.timedCourse) {
        _refreshTimer = Timer.periodic(
          const Duration(milliseconds: 200),
          (_) {
            engine.reconcile();
            _drainVoiceEvents();
          },
        );
      }
      ref.read(workoutPlayerAssistControllerProvider.notifier).setScreenAwake(
            true,
            enabledMessage: '训练进行中，屏幕保持常亮。',
            disabledMessage: '已释放屏幕常亮。',
          );
      _drainVoiceEvents();
      setState(() {});
    });
  }

  void _onEngineChanged() {
    final GuidedWorkoutEngine? engine = _engine;
    if (!mounted || engine == null) return;
    _drainVoiceEvents();
    if (engine.state.status == GuidedWorkoutStatus.completed) {
      _refreshTimer?.cancel();
      _saveSession(completedFlow: true);
      ref.read(workoutPlayerAssistControllerProvider.notifier).setScreenAwake(
            false,
            enabledMessage: '训练进行中，屏幕保持常亮。',
            disabledMessage: '训练完成，已释放屏幕常亮。',
          );
    }
    setState(() {});
  }

  void _drainVoiceEvents() {
    final GuidedWorkoutEngine? engine = _engine;
    if (engine == null) return;
    final controller = ref.read(workoutPlayerAssistControllerProvider.notifier);
    for (final GuidedWorkoutVoiceEvent event
        in engine.takePendingVoiceEvents()) {
      controller.enqueueCue(
        event.text,
        rate: engine.course.voice.rate,
        voiceName: engine.course.voice.voiceName,
      );
    }
  }

  void _togglePause() {
    final GuidedWorkoutEngine? engine = _engine;
    if (engine == null) return;
    final controller = ref.read(workoutPlayerAssistControllerProvider.notifier);
    if (engine.state.status == GuidedWorkoutStatus.running) {
      engine.pause();
      controller.setScreenAwake(
        false,
        enabledMessage: '训练进行中，屏幕保持常亮。',
        disabledMessage: '训练已暂停，已释放屏幕常亮。',
      );
    } else if (engine.state.status == GuidedWorkoutStatus.paused) {
      engine.resume();
      controller.setScreenAwake(
        true,
        enabledMessage: '训练继续，屏幕保持常亮。',
        disabledMessage: '已释放屏幕常亮。',
      );
    }
    _drainVoiceEvents();
  }

  void _saveSession({required bool completedFlow}) {
    if (_saved) return;
    final GuidedWorkoutEngine? engine = _engine;
    if (engine == null) return;
    final GuidedWorkoutState state = engine.state;
    final DateTime now = DateTime.now();
    final TrainingLog log = buildGuidedWorkoutTrainingLog(
      sessionId: _sessionId,
      course: engine.course,
      state: state,
      now: now,
      completedFlow: completedFlow,
    );
    ref.read(trainingLogControllerProvider.notifier).save(log);
    _saved = true;
  }

  Future<void> _requestExit() async {
    if (_exitDialogVisible || !mounted) return;
    final GuidedWorkoutEngine? engine = _engine;
    if (engine == null ||
        engine.state.status == GuidedWorkoutStatus.completed) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(_detailRoute);
      }
      return;
    }
    _exitDialogVisible = true;
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('退出本次跟练？'),
        content: const Text('可以保存当前完成情况，也可以放弃本次记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('放弃记录'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存部分记录'),
          ),
        ],
      ),
    );
    _exitDialogVisible = false;
    if (save == null || !mounted) return;
    if (save) _saveSession(completedFlow: false);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_detailRoute);
    }
  }
}

class _PlayerControls extends StatelessWidget {
  final bool running;
  final bool voiceEnabled;
  final VoidCallback onPauseResume;
  final VoidCallback onPrevious;
  final VoidCallback onSkip;
  final bool showComplete;
  final VoidCallback onComplete;
  final VoidCallback onToggleVoice;

  const _PlayerControls({
    required this.running,
    required this.voiceEnabled,
    required this.onPauseResume,
    required this.onPrevious,
    required this.onSkip,
    required this.showComplete,
    required this.onComplete,
    required this.onToggleVoice,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('guided-workout-pause-resume'),
              onPressed: onPauseResume,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
              label: Text(running ? '暂停' : '继续'),
            ),
          ),
          const SizedBox(height: 10),
          if (showComplete) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey<String>('guided-workout-complete-current'),
                onPressed: onComplete,
                icon: const Icon(Icons.check),
                label: const Text('完成本动作'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('guided-workout-previous'),
                  onPressed: onPrevious,
                  icon: const Icon(Icons.skip_previous),
                  label: const Text('上一步'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('guided-workout-skip'),
                  onPressed: onSkip,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('跳过'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onToggleVoice,
            icon: Icon(voiceEnabled ? Icons.volume_up : Icons.volume_off),
            label: Text(voiceEnabled ? '关闭语音' : '开启语音'),
          ),
        ],
      ),
    );
  }
}

class _PlayerLoadingPage extends StatelessWidget {
  final String courseId;
  final String fallbackRoute;
  final String message;

  const _PlayerLoadingPage({
    required this.courseId,
    required this.fallbackRoute,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: '跳绳跟练',
      leading: TrainMateBackButton(
        fallbackRoute: fallbackRoute,
      ),
      children: [
        TrainFlowCard(child: Text(message)),
      ],
    );
  }
}

class _LinkedExerciseMedia extends StatelessWidget {
  final String exerciseId;
  final List<Exercise> exercises;

  const _LinkedExerciseMedia({
    required this.exerciseId,
    required this.exercises,
  });

  @override
  Widget build(BuildContext context) {
    Exercise? exercise;
    for (final Exercise candidate in exercises) {
      if (candidate.id == exerciseId) {
        exercise = candidate;
        break;
      }
    }
    if (exercise == null) return const SizedBox.shrink();
    return TrainFlowCard(child: ExerciseMedia(exercise: exercise, compact: true));
  }
}

String _formatElapsed(int milliseconds) {
  final int totalSeconds = milliseconds ~/ 1000;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '$minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
}
