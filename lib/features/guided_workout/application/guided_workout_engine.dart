import 'package:flutter/foundation.dart';

import '../domain/guided_workout_course.dart';

enum GuidedWorkoutStatus { ready, running, paused, completed }

enum GuidedWorkoutSegmentKind { exercise, rest }

class GuidedWorkoutSegment {
  final String id;
  final GuidedWorkoutSegmentKind kind;
  final int phaseIndex;
  final GuidedWorkoutPhase phase;
  final GuidedWorkoutExercise exercise;
  final GuidedWorkoutExercise? nextExercise;
  final int durationMilliseconds;
  final int roundIndex;
  final int roundCount;

  const GuidedWorkoutSegment({
    required this.id,
    required this.kind,
    required this.phaseIndex,
    required this.phase,
    required this.exercise,
    required this.nextExercise,
    required this.durationMilliseconds,
    this.roundIndex = 1,
    this.roundCount = 1,
  });

  String get title =>
      kind == GuidedWorkoutSegmentKind.rest ? '休息' : exercise.name;

  bool get usesTimer =>
      kind == GuidedWorkoutSegmentKind.rest ||
      exercise.completionMode == GuidedWorkoutCompletionMode.timed;
}

class GuidedWorkoutStepResult {
  final String segmentId;
  final String exerciseId;
  final String? libraryExerciseId;
  final int roundIndex;
  final bool completed;

  const GuidedWorkoutStepResult({
    required this.segmentId,
    required this.exerciseId,
    required this.libraryExerciseId,
    required this.roundIndex,
    required this.completed,
  });
}

class GuidedWorkoutVoiceEvent {
  final String id;
  final String text;

  const GuidedWorkoutVoiceEvent({required this.id, required this.text});
}

class GuidedWorkoutState {
  final GuidedWorkoutStatus status;
  final GuidedWorkoutSegment segment;
  final int segmentIndex;
  final int remainingMilliseconds;
  final int elapsedMilliseconds;
  final int plannedExerciseCount;
  final int completedExerciseCount;
  final int skippedExerciseCount;
  final List<GuidedWorkoutStepResult> stepResults;

  const GuidedWorkoutState({
    required this.status,
    required this.segment,
    required this.segmentIndex,
    required this.remainingMilliseconds,
    required this.elapsedMilliseconds,
    required this.plannedExerciseCount,
    required this.completedExerciseCount,
    required this.skippedExerciseCount,
    this.stepResults = const <GuidedWorkoutStepResult>[],
  });

  int get completionPercentage {
    if (plannedExerciseCount <= 0) return 0;
    return ((completedExerciseCount / plannedExerciseCount) * 100)
        .round()
        .clamp(0, 100);
  }

  double get overallProgress {
    final int handled = completedExerciseCount + skippedExerciseCount;
    if (plannedExerciseCount <= 0) return 0;
    return (handled / plannedExerciseCount).clamp(0, 1);
  }

  String get remainingLabel {
    final int totalSeconds = (remainingMilliseconds / 1000).ceil();
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  GuidedWorkoutState copyWith({
    GuidedWorkoutStatus? status,
    GuidedWorkoutSegment? segment,
    int? segmentIndex,
    int? remainingMilliseconds,
    int? elapsedMilliseconds,
    int? plannedExerciseCount,
    int? completedExerciseCount,
    int? skippedExerciseCount,
    List<GuidedWorkoutStepResult>? stepResults,
  }) {
    return GuidedWorkoutState(
      status: status ?? this.status,
      segment: segment ?? this.segment,
      segmentIndex: segmentIndex ?? this.segmentIndex,
      remainingMilliseconds:
          remainingMilliseconds ?? this.remainingMilliseconds,
      elapsedMilliseconds: elapsedMilliseconds ?? this.elapsedMilliseconds,
      plannedExerciseCount: plannedExerciseCount ?? this.plannedExerciseCount,
      completedExerciseCount:
          completedExerciseCount ?? this.completedExerciseCount,
      skippedExerciseCount: skippedExerciseCount ?? this.skippedExerciseCount,
      stepResults: List<GuidedWorkoutStepResult>.unmodifiable(
        stepResults ?? this.stepResults,
      ),
    );
  }
}

class GuidedWorkoutEngine extends ChangeNotifier {
  final GuidedWorkoutCourse course;
  final int selectedRounds;
  final DateTime Function() _now;
  late final List<GuidedWorkoutSegment> _segments;
  final List<GuidedWorkoutVoiceEvent> _pendingVoiceEvents =
      <GuidedWorkoutVoiceEvent>[];
  final Set<String> _emittedVoiceEventIds = <String>{};

  late GuidedWorkoutState _state;
  DateTime? _deadline;
  DateTime? _lastObserved;

  GuidedWorkoutEngine({
    required this.course,
    int? selectedRounds,
    DateTime Function()? now,
  })  : selectedRounds = course.normalizedRounds(selectedRounds),
        _now = now ?? DateTime.now {
    _segments = _compileSegments(
      course,
      course.normalizedRounds(selectedRounds),
    );
    final GuidedWorkoutSegment first = _segments.first;
    _state = GuidedWorkoutState(
      status: GuidedWorkoutStatus.ready,
      segment: first,
      segmentIndex: 0,
      remainingMilliseconds: first.durationMilliseconds,
      elapsedMilliseconds: 0,
      plannedExerciseCount: course.exerciseSetCountForRounds(
        course.normalizedRounds(selectedRounds),
      ),
      completedExerciseCount: 0,
      skippedExerciseCount: 0,
    );
  }

  GuidedWorkoutState get state => _state;

  GuidedWorkoutSegment? get nextExerciseSegment {
    for (int index = _state.segmentIndex + 1;
        index < _segments.length;
        index += 1) {
      final GuidedWorkoutSegment segment = _segments[index];
      if (segment.kind == GuidedWorkoutSegmentKind.exercise) return segment;
    }
    return null;
  }

  void start() {
    if (_state.status != GuidedWorkoutStatus.ready) return;
    final DateTime now = _now();
    _deadline = _state.segment.usesTimer
        ? now.add(Duration(milliseconds: _state.remainingMilliseconds))
        : null;
    _lastObserved = now;
    _state = _state.copyWith(status: GuidedWorkoutStatus.running);
    _queueCurrentSegmentAnnouncement(includePhase: true);
    notifyListeners();
  }

  void pause() {
    if (_state.status != GuidedWorkoutStatus.running) return;
    reconcile();
    if (_state.status != GuidedWorkoutStatus.running) return;
    _state = _state.copyWith(status: GuidedWorkoutStatus.paused);
    _deadline = null;
    _lastObserved = null;
    _queueVoice('pause-${_state.segmentIndex}', '训练已暂停');
    notifyListeners();
  }

  void resume() {
    if (_state.status != GuidedWorkoutStatus.paused) return;
    final DateTime now = _now();
    _deadline = _state.segment.usesTimer
        ? now.add(Duration(milliseconds: _state.remainingMilliseconds))
        : null;
    _lastObserved = now;
    _state = _state.copyWith(status: GuidedWorkoutStatus.running);
    _queueVoice('resume-${_state.segmentIndex}', '继续${_state.segment.title}');
    notifyListeners();
  }

  void reconcile([DateTime? at]) {
    if (_state.status != GuidedWorkoutStatus.running) return;
    final DateTime now = at ?? _now();
    _accumulateElapsed(now);
    if (!_state.segment.usesTimer || _deadline == null) {
      notifyListeners();
      return;
    }
    DateTime deadline = _deadline!;
    int transitions = 0;
    while (!now.isBefore(deadline) &&
        _state.status == GuidedWorkoutStatus.running) {
      final int nextIndex = _state.segmentIndex + 1;
      if (_state.segment.kind == GuidedWorkoutSegmentKind.exercise) {
        _state = _state.copyWith(
          completedExerciseCount: _state.completedExerciseCount + 1,
          stepResults: _recordCurrentResult(completed: true),
        );
      }
      if (nextIndex >= _segments.length) {
        _complete();
        return;
      }
      final GuidedWorkoutSegment next = _segments[nextIndex];
      _state = _state.copyWith(
        segment: next,
        segmentIndex: nextIndex,
        remainingMilliseconds: next.durationMilliseconds,
      );
      deadline = deadline.add(
        Duration(milliseconds: next.durationMilliseconds),
      );
      _deadline = deadline;
      transitions += 1;
    }
    if (_state.status != GuidedWorkoutStatus.running) return;
    final int remaining = deadline.difference(now).inMilliseconds.clamp(
          0,
          _state.segment.durationMilliseconds,
        );
    _state = _state.copyWith(remainingMilliseconds: remaining);
    if (transitions > 0) {
      _pendingVoiceEvents.clear();
      _queueCurrentSegmentAnnouncement();
    } else {
      _queueCountdownIfNeeded();
    }
    notifyListeners();
  }

  void skipCurrent() {
    if (_state.status == GuidedWorkoutStatus.ready) start();
    if (_state.status != GuidedWorkoutStatus.running &&
        _state.status != GuidedWorkoutStatus.paused) {
      return;
    }
    if (_state.status == GuidedWorkoutStatus.running) {
      reconcile();
    }
    final bool wasRunning = _state.status == GuidedWorkoutStatus.running;
    final bool skippingExercise =
        _state.segment.kind == GuidedWorkoutSegmentKind.exercise;
    final int skipped = skippingExercise
        ? _state.skippedExerciseCount + 1
        : _state.skippedExerciseCount;
    final int? nextIndex = _nextExerciseIndex(_state.segmentIndex + 1);
    if (nextIndex == null) {
      _state = _state.copyWith(
        skippedExerciseCount: skipped,
        stepResults: skippingExercise
            ? _recordCurrentResult(completed: false)
            : _state.stepResults,
      );
      _complete();
      return;
    }
    _jumpToSegment(
      nextIndex,
      status:
          wasRunning ? GuidedWorkoutStatus.running : GuidedWorkoutStatus.paused,
      skippedExerciseCount: skipped,
      stepResults: skippingExercise
          ? _recordCurrentResult(completed: false)
          : _state.stepResults,
    );
    _queueVoice(
      'skip-${_state.segmentIndex}-${_state.skippedExerciseCount}',
      '已跳过，下一组：${_state.segment.exercise.name}',
    );
    notifyListeners();
  }

  /// 完成当前次数型动作。计时型课程继续由 [reconcile] 自动推进。
  void completeCurrent() {
    if (_state.status == GuidedWorkoutStatus.ready) start();
    if (_state.status != GuidedWorkoutStatus.running &&
        _state.status != GuidedWorkoutStatus.paused) {
      return;
    }
    if (_state.segment.kind != GuidedWorkoutSegmentKind.exercise ||
        _state.segment.exercise.completionMode !=
            GuidedWorkoutCompletionMode.repetitions) {
      return;
    }
    final bool wasRunning = _state.status == GuidedWorkoutStatus.running;
    _state = _state.copyWith(
      completedExerciseCount: _state.completedExerciseCount + 1,
      stepResults: _recordCurrentResult(completed: true),
    );
    final int nextIndex = _state.segmentIndex + 1;
    if (nextIndex >= _segments.length) {
      _complete();
      return;
    }
    _jumpToSegment(
      nextIndex,
      status:
          wasRunning ? GuidedWorkoutStatus.running : GuidedWorkoutStatus.paused,
    );
    _queueCurrentSegmentAnnouncement();
    notifyListeners();
  }

  void goToPrevious() {
    if (_state.status != GuidedWorkoutStatus.running &&
        _state.status != GuidedWorkoutStatus.paused) {
      return;
    }
    if (_state.status == GuidedWorkoutStatus.running) {
      reconcile();
    }
    final bool wasRunning = _state.status == GuidedWorkoutStatus.running;
    final int elapsedInSegment =
        _state.segment.durationMilliseconds - _state.remainingMilliseconds;
    int targetIndex = _state.segmentIndex;
    if (_state.segment.kind == GuidedWorkoutSegmentKind.rest ||
        elapsedInSegment < 3000) {
      targetIndex = _previousExerciseIndex(_state.segmentIndex - 1) ?? 0;
    } else if (_state.segment.kind != GuidedWorkoutSegmentKind.exercise) {
      targetIndex = _previousExerciseIndex(_state.segmentIndex) ?? 0;
    }
    _jumpToSegment(
      targetIndex,
      status:
          wasRunning ? GuidedWorkoutStatus.running : GuidedWorkoutStatus.paused,
    );
    _queueVoice(
      'previous-${_state.segmentIndex}-${_state.elapsedMilliseconds}',
      '返回${_state.segment.exercise.name}',
    );
    notifyListeners();
  }

  List<GuidedWorkoutVoiceEvent> takePendingVoiceEvents() {
    final List<GuidedWorkoutVoiceEvent> result =
        List<GuidedWorkoutVoiceEvent>.unmodifiable(_pendingVoiceEvents);
    _pendingVoiceEvents.clear();
    return result;
  }

  void _accumulateElapsed(DateTime now) {
    final DateTime? last = _lastObserved;
    if (last != null && now.isAfter(last)) {
      final int nextElapsed =
          _state.elapsedMilliseconds + now.difference(last).inMilliseconds;
      _state = _state.copyWith(
        elapsedMilliseconds: nextElapsed.clamp(
          0,
          course.expectedDurationSecondsForRounds(selectedRounds) * 1000,
        ),
      );
    }
    _lastObserved = now;
  }

  void _jumpToSegment(
    int index, {
    required GuidedWorkoutStatus status,
    int? skippedExerciseCount,
    List<GuidedWorkoutStepResult>? stepResults,
  }) {
    final GuidedWorkoutSegment segment = _segments[index];
    final DateTime now = _now();
    _state = _state.copyWith(
      status: status,
      segment: segment,
      segmentIndex: index,
      remainingMilliseconds: segment.durationMilliseconds,
      skippedExerciseCount: skippedExerciseCount ?? _state.skippedExerciseCount,
      stepResults: stepResults ?? _state.stepResults,
    );
    if (status == GuidedWorkoutStatus.running) {
      _deadline = segment.usesTimer
          ? now.add(Duration(milliseconds: segment.durationMilliseconds))
          : null;
      _lastObserved = now;
    } else {
      _deadline = null;
      _lastObserved = null;
    }
  }

  void _complete() {
    _state = _state.copyWith(
      status: GuidedWorkoutStatus.completed,
      remainingMilliseconds: 0,
    );
    _deadline = null;
    _lastObserved = null;
    _pendingVoiceEvents.clear();
    _queueVoice(
      'complete',
      course.kind == GuidedWorkoutCourseKind.functionalCircuit
          ? '本次功能性循环已完成'
          : '本次跳绳跟练已完成',
    );
    notifyListeners();
  }

  void _queueCurrentSegmentAnnouncement({bool includePhase = false}) {
    final GuidedWorkoutSegment segment = _state.segment;
    if (includePhase) {
      _queueVoice(
        'phase-${segment.phaseIndex}',
        '开始${segment.phase.name}',
      );
    }
    if (segment.kind == GuidedWorkoutSegmentKind.rest) {
      final String nextName = segment.nextExercise?.name ?? '下一阶段';
      _queueVoice(
        'segment-${_state.segmentIndex}',
        '休息 ${segment.durationMilliseconds ~/ 1000} 秒，下一组：$nextName',
      );
      return;
    }
    if (segment.exercise.completionMode ==
        GuidedWorkoutCompletionMode.repetitions) {
      _queueVoice(
        'segment-${_state.segmentIndex}',
        '第 ${segment.roundIndex}/${segment.roundCount} 轮，'
            '${segment.exercise.name}，${segment.exercise.repetitionLabel}',
      );
      return;
    }
    final String announcement = segment.exercise.announce.isEmpty
        ? '开始${segment.exercise.name}'
        : segment.exercise.announce;
    _queueVoice('segment-${_state.segmentIndex}', announcement);
  }

  void _queueCountdownIfNeeded() {
    final int seconds = (_state.remainingMilliseconds / 1000).ceil();
    if (_state.segment.kind == GuidedWorkoutSegmentKind.rest) {
      if (seconds >= 1 && seconds <= 3) {
        _queueVoice('rest-${_state.segmentIndex}-$seconds', '$seconds');
      }
      return;
    }
    if (_state.segment.exercise.completionMode ==
        GuidedWorkoutCompletionMode.repetitions) {
      return;
    }
    if (seconds >= 1 && seconds <= course.voice.countdownLast) {
      _queueVoice('exercise-${_state.segmentIndex}-$seconds', '$seconds');
    }
  }

  void _queueVoice(String id, String text) {
    if (!course.voice.enabled || text.trim().isEmpty) return;
    if (!_emittedVoiceEventIds.add(id)) return;
    _pendingVoiceEvents.add(
      GuidedWorkoutVoiceEvent(id: id, text: text.trim()),
    );
  }

  int? _nextExerciseIndex(int start) {
    for (int index = start; index < _segments.length; index += 1) {
      if (_segments[index].kind == GuidedWorkoutSegmentKind.exercise) {
        return index;
      }
    }
    return null;
  }

  int? _previousExerciseIndex(int start) {
    for (int index = start; index >= 0; index -= 1) {
      if (_segments[index].kind == GuidedWorkoutSegmentKind.exercise) {
        return index;
      }
    }
    return null;
  }

  List<GuidedWorkoutStepResult> _recordCurrentResult({
    required bool completed,
  }) {
    final GuidedWorkoutSegment segment = _state.segment;
    if (segment.kind != GuidedWorkoutSegmentKind.exercise) {
      return _state.stepResults;
    }
    final List<GuidedWorkoutStepResult> results =
        List<GuidedWorkoutStepResult>.from(_state.stepResults);
    results.removeWhere(
      (GuidedWorkoutStepResult item) => item.segmentId == segment.id,
    );
    results.add(
      GuidedWorkoutStepResult(
        segmentId: segment.id,
        exerciseId: segment.exercise.id,
        libraryExerciseId: segment.exercise.libraryExerciseId,
        roundIndex: segment.roundIndex,
        completed: completed,
      ),
    );
    return List<GuidedWorkoutStepResult>.unmodifiable(results);
  }
}

List<GuidedWorkoutSegment> _compileSegments(
  GuidedWorkoutCourse course,
  int selectedRounds,
) {
  final List<_ExerciseOccurrence> occurrences = <_ExerciseOccurrence>[];
  final int rounds = course.kind == GuidedWorkoutCourseKind.functionalCircuit
      ? selectedRounds
      : 1;
  for (int roundIndex = 1; roundIndex <= rounds; roundIndex += 1) {
    for (int phaseIndex = 0;
        phaseIndex < course.phases.length;
        phaseIndex += 1) {
      final GuidedWorkoutPhase phase = course.phases[phaseIndex];
      for (final GuidedWorkoutExercise exercise in phase.exercises) {
        for (int repeatIndex = 0;
            repeatIndex < exercise.repeat;
            repeatIndex += 1) {
          occurrences.add(
            _ExerciseOccurrence(
              phaseIndex: phaseIndex,
              phase: phase,
              exercise: exercise,
              repeatIndex: repeatIndex,
              roundIndex: roundIndex,
              roundCount: rounds,
            ),
          );
        }
      }
    }
  }

  final List<GuidedWorkoutSegment> result = <GuidedWorkoutSegment>[];
  for (int index = 0; index < occurrences.length; index += 1) {
    final _ExerciseOccurrence occurrence = occurrences[index];
    final GuidedWorkoutExercise? nextExercise =
        index + 1 < occurrences.length ? occurrences[index + 1].exercise : null;
    result.add(
      GuidedWorkoutSegment(
        id: '${occurrence.phase.id}-${occurrence.exercise.id}-'
            '${occurrence.repeatIndex}-exercise',
        kind: GuidedWorkoutSegmentKind.exercise,
        phaseIndex: occurrence.phaseIndex,
        phase: occurrence.phase,
        exercise: occurrence.exercise,
        nextExercise: nextExercise,
        durationMilliseconds: occurrence.exercise.durationSeconds * 1000,
        roundIndex: occurrence.roundIndex,
        roundCount: occurrence.roundCount,
      ),
    );
    if (occurrence.exercise.restSeconds > 0) {
      result.add(
        GuidedWorkoutSegment(
          id: '${occurrence.phase.id}-${occurrence.exercise.id}-'
              '${occurrence.repeatIndex}-rest',
          kind: GuidedWorkoutSegmentKind.rest,
          phaseIndex: occurrence.phaseIndex,
          phase: occurrence.phase,
          exercise: occurrence.exercise,
          nextExercise: nextExercise,
          durationMilliseconds: occurrence.exercise.restSeconds * 1000,
          roundIndex: occurrence.roundIndex,
          roundCount: occurrence.roundCount,
        ),
      );
    }
  }
  if (result.isEmpty) {
    throw const FormatException('课程没有可播放的动作。');
  }
  return List<GuidedWorkoutSegment>.unmodifiable(result);
}

class _ExerciseOccurrence {
  final int phaseIndex;
  final GuidedWorkoutPhase phase;
  final GuidedWorkoutExercise exercise;
  final int repeatIndex;
  final int roundIndex;
  final int roundCount;

  const _ExerciseOccurrence({
    required this.phaseIndex,
    required this.phase,
    required this.exercise,
    required this.repeatIndex,
    required this.roundIndex,
    required this.roundCount,
  });
}
