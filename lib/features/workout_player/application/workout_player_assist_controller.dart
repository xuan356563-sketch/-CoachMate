import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/workout_platform_service.dart';

final workoutPlatformServiceProvider = Provider<WorkoutPlatformService>(
  (Ref ref) => WorkoutPlatformService(),
);

final workoutPlayerAssistControllerProvider =
    NotifierProvider<WorkoutPlayerAssistController, WorkoutPlayerAssistState>(
  WorkoutPlayerAssistController.new,
);

class WorkoutPlayerAssistState {
  final bool voiceEnabled;
  final List<String> voiceQueue;
  final String voiceStatusMessage;
  final bool screenAwakeRequested;
  final String screenAwakeStatusMessage;

  const WorkoutPlayerAssistState({
    required this.voiceEnabled,
    required this.voiceQueue,
    required this.voiceStatusMessage,
    required this.screenAwakeRequested,
    required this.screenAwakeStatusMessage,
  });

  WorkoutPlayerAssistState copyWith({
    bool? voiceEnabled,
    List<String>? voiceQueue,
    String? voiceStatusMessage,
    bool? screenAwakeRequested,
    String? screenAwakeStatusMessage,
  }) {
    return WorkoutPlayerAssistState(
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceQueue: voiceQueue ?? this.voiceQueue,
      voiceStatusMessage: voiceStatusMessage ?? this.voiceStatusMessage,
      screenAwakeRequested: screenAwakeRequested ?? this.screenAwakeRequested,
      screenAwakeStatusMessage:
          screenAwakeStatusMessage ?? this.screenAwakeStatusMessage,
    );
  }
}

class WorkoutPlayerAssistController extends Notifier<WorkoutPlayerAssistState> {
  WorkoutPlatformService get _platform =>
      ref.read(workoutPlatformServiceProvider);

  @override
  WorkoutPlayerAssistState build() {
    final WorkoutPlatformService platform =
        ref.read(workoutPlatformServiceProvider);
    ref.onDispose(() {
      unawaited(platform.stopSpeech());
      unawaited(platform.setScreenAwake(false));
    });
    return const WorkoutPlayerAssistState(
      voiceEnabled: true,
      voiceQueue: [],
      voiceStatusMessage: 'TTS 提示队列已准备；开始跟练后会生成当前步骤播报文案。',
      screenAwakeRequested: false,
      screenAwakeStatusMessage: '尚未请求屏幕常亮；进入跟练后会启用本地常亮意图。',
    );
  }

  void toggleVoice() {
    final bool enabled = !state.voiceEnabled;
    if (!enabled) {
      unawaited(_platform.stopSpeech());
    }
    state = state.copyWith(
      voiceEnabled: enabled,
      voiceStatusMessage:
          enabled ? 'TTS 提示队列已开启；后续步骤会调用浏览器语音播报。' : 'TTS 提示队列已关闭；当前只显示文字动作提示。',
    );
  }

  void toggleScreenAwake() {
    setScreenAwake(
      !state.screenAwakeRequested,
      enabledMessage: '已请求浏览器屏幕常亮；不支持 Wake Lock 的环境会保持普通显示。',
      disabledMessage: '已取消屏幕常亮意图；系统可能按默认策略熄屏。',
    );
  }

  void setScreenAwake(
    bool requested, {
    required String enabledMessage,
    required String disabledMessage,
  }) {
    state = state.copyWith(
      screenAwakeRequested: requested,
      screenAwakeStatusMessage: requested ? enabledMessage : disabledMessage,
    );
    unawaited(_platform.setScreenAwake(requested));
  }

  void replaceQueueWithCue(String cue) {
    final String trimmedCue = cue.trim();
    state = state.copyWith(
      voiceQueue:
          state.voiceEnabled && trimmedCue.isNotEmpty ? [trimmedCue] : [],
      voiceStatusMessage: _statusFor(trimmedCue),
    );
    _speak(trimmedCue);
  }

  void enqueueCue(String cue) {
    final String trimmedCue = cue.trim();
    if (!state.voiceEnabled || trimmedCue.isEmpty) {
      state = state.copyWith(voiceStatusMessage: _statusFor(trimmedCue));
      return;
    }
    final List<String> queue = [trimmedCue, ...state.voiceQueue];
    if (queue.length > 6) {
      queue.removeRange(6, queue.length);
    }
    state = state.copyWith(
      voiceQueue: List<String>.unmodifiable(queue),
      voiceStatusMessage: _statusFor(trimmedCue),
    );
    _speak(trimmedCue);
  }

  String _statusFor(String cue) {
    if (!state.voiceEnabled) {
      return 'TTS 提示队列已关闭；当前只显示文字动作提示。';
    }
    return '已加入 TTS 提示队列：$cue';
  }

  void _speak(String cue) {
    if (!state.voiceEnabled || cue.isEmpty) {
      return;
    }
    unawaited(_platform.speak(cue));
  }
}
