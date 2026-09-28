import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_brand.dart';
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
  int _screenAwakeRequestRevision = 0;
  bool _released = false;
  int _speechRevision = 0;

  late WorkoutPlatformService _platform;

  @override
  WorkoutPlayerAssistState build() {
    final WorkoutPlatformService platform =
        ref.read(workoutPlatformServiceProvider);
    _platform = platform;
    ref.onDispose(() {
      _released = true;
      _screenAwakeRequestRevision++;
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

  /// 两套执行器共用的原始释放操作，不保存训练记录、不更改语音偏好。
  Future<void> releaseResources({bool updateState = true}) async {
    _released = true;
    _speechRevision++;
    _screenAwakeRequestRevision++;
    final platform = _platform;
    if (updateState && ref.mounted) {
      state = state.copyWith(
          voiceQueue: [],
          screenAwakeRequested: false,
          screenAwakeStatusMessage: '已释放屏幕常亮。');
    }
    await platform.stopSpeech();
    await platform.setScreenAwake(false);
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
    if (requested) _released = false;
    final int revision = ++_screenAwakeRequestRevision;
    state = state.copyWith(
      screenAwakeRequested: requested,
      screenAwakeStatusMessage: requested ? enabledMessage : disabledMessage,
    );
    unawaited(
      _applyScreenAwake(
        requested,
        revision: revision,
      ),
    );
  }

  Future<void> _applyScreenAwake(
    bool requested, {
    required int revision,
  }) async {
    final bool supported = await _platform.setScreenAwake(requested);
    if (_released || !ref.mounted) {
      if (requested) await _platform.setScreenAwake(false);
      return;
    }
    if (revision != _screenAwakeRequestRevision) {
      if (requested && !state.screenAwakeRequested) {
        await _platform.setScreenAwake(false);
      }
      return;
    }
    if (!requested || supported) {
      return;
    }
    state = state.copyWith(
      screenAwakeRequested: false,
      screenAwakeStatusMessage:
          '当前环境不支持屏幕常亮，请升级 iOS/Safari 或使用${AppBrand.displayName} App。',
    );
  }

  void replaceQueueWithCue(
    String cue, {
    double rate = 1,
    String? voiceName,
  }) {
    final String trimmedCue = cue.trim();
    state = state.copyWith(
      voiceQueue:
          state.voiceEnabled && trimmedCue.isNotEmpty ? [trimmedCue] : [],
      voiceStatusMessage: _statusFor(trimmedCue),
    );
    _speak(trimmedCue, rate: rate, voiceName: voiceName);
  }

  void enqueueCue(
    String cue, {
    double rate = 1,
    String? voiceName,
  }) {
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
    _speak(trimmedCue, rate: rate, voiceName: voiceName);
  }

  String _statusFor(String cue) {
    if (!state.voiceEnabled) {
      return 'TTS 提示队列已关闭；当前只显示文字动作提示。';
    }
    return '已加入 TTS 提示队列：$cue';
  }

  void _speak(
    String cue, {
    required double rate,
    String? voiceName,
  }) {
    if (!state.voiceEnabled || cue.isEmpty) {
      return;
    }
    _released = false;
    final revision = ++_speechRevision;
    final platform = _platform;
    unawaited(
        platform.speak(cue, rate: rate, voiceName: voiceName).then((_) async {
      if (_released && revision != _speechRevision) await platform.stopSpeech();
    }));
  }
}
