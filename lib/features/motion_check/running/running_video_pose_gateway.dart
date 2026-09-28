import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'running_pose_models.dart';

/// 验收通过之前，正式发行不能用编译参数打开新分析入口。
const runningVideoPreviewEnabled =
    !kReleaseMode && bool.fromEnvironment('TRAINMATE_RUNNING_VIDEO_PREVIEW');

abstract class RunningVideoPoseGateway {
  bool get isSupported;
  Future<RunningPoseSequence> analyze(
      {required String taskId,
      required String path,
      required void Function(double) onProgress});
  Future<Uint8List?> thumbnail(String taskId, double seconds);
  Future<void> cancel(String taskId);
  Future<void> dispose();
}

class PlatformRunningVideoPoseGateway implements RunningVideoPoseGateway {
  static const _channel = MethodChannel('trainflow.ai/running_video');
  static const _events = EventChannel('trainflow.ai/running_video_progress');
  final Set<String> _tasks = {};
  final Set<String> _cancelled = {};
  final Map<String, Future<void>> _cancellations = {};
  bool _disposed = false;
  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  @override
  Future<RunningPoseSequence> analyze(
      {required String taskId,
      required String path,
      required void Function(double) onProgress}) async {
    if (!isSupported || _disposed) throw StateError('跑姿视频识别仅支持 iPhone 本机运行');
    if (_tasks.isNotEmpty) throw StateError('请先关闭或取消上一段视频');
    _tasks.add(taskId);
    final frames = <RunningPoseFrame>[];
    Object? streamError;
    final sub = _events.receiveBroadcastStream().listen((raw) {
      if (_disposed ||
          _cancelled.contains(taskId) ||
          !_tasks.contains(taskId) ||
          raw is! Map ||
          raw['taskId'] != taskId) {
        return;
      }
      try {
        if (raw['frame'] is Map) {
          if (frames.length >= 601) throw const FormatException('视频帧数超过处理上限');
          frames.add(RunningPoseFrame.fromJson(
              Map<String, dynamic>.from(raw['frame'] as Map)));
        }
        onProgress(((raw['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1));
      } catch (error) {
        streamError = error;
      }
    }, onError: (Object error) {
      streamError = error;
    });
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
          'analyze', {'taskId': taskId, 'path': path});
      if (!_tasks.contains(taskId) ||
          _disposed ||
          _cancelled.contains(taskId)) {
        throw StateError('视频分析已取消');
      }
      if (streamError != null) throw streamError!;
      if (raw == null || frames.length != raw['frameCount']) {
        throw const FormatException('视频关键点传输不完整，请重试');
      }
      return RunningPoseSequence(
          duration: (raw['duration'] as num).toDouble(),
          frames: frames,
          detectorVersion: raw['detectorVersion'] as String);
    } catch (_) {
      await cancel(taskId);
      rethrow;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<Uint8List?> thumbnail(String taskId, double seconds) async {
    if (!_tasks.contains(taskId) || _disposed || _cancelled.contains(taskId)) {
      return null;
    }
    return _channel.invokeMethod<Uint8List>(
        'thumbnail', {'taskId': taskId, 'seconds': seconds});
  }

  @override
  Future<void> cancel(String taskId) {
    if (!_tasks.contains(taskId)) return Future.value();
    _cancelled.add(taskId);
    return _cancellations.putIfAbsent(taskId, () => _cancelNative(taskId));
  }

  Future<void> _cancelNative(String taskId) async {
    try {
      if (isSupported) {
        await _channel.invokeMethod<void>('cancel', {'taskId': taskId});
      }
      _tasks.remove(taskId);
      _cancelled.remove(taskId);
    } finally {
      _cancellations.remove(taskId);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final id in _tasks.toList()) {
      await cancel(id);
    }
  }
}
