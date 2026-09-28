import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import '../../../plugins/features/motion_check_plugin.dart';
import '../../../services/local_storage_service.dart';
import 'running_form_assessment_service.dart';
import 'running_form_report_repository.dart';
import 'running_metrics_service.dart';
import 'running_video_pose_gateway.dart';

abstract class RunningVideoPicker {
  Future<String?> pick();
}

class PlatformRunningVideoPicker implements RunningVideoPicker {
  @override
  Future<String?> pick() async =>
      (await ImagePicker().pickVideo(source: ImageSource.gallery))?.path;
}

final runningVideoPickerProvider =
    Provider<RunningVideoPicker>((ref) => PlatformRunningVideoPicker());
final runningVideoPreviewProvider =
    Provider<bool>((ref) => runningVideoPreviewEnabled);
final runningFormReportRepositoryProvider =
    Provider<RunningFormReportRepository>((ref) {
  ref.watch(pluginRuntimeProvider.select((r) => r.accountEpoch));
  return RunningFormReportRepository(ref.watch(localStorageServiceProvider));
});
final runningVideoControllerProvider =
    NotifierProvider.autoDispose<RunningVideoController, RunningVideoState>(
        RunningVideoController.new);

enum RunningVideoPhase {
  idle,
  picking,
  extracting,
  measuring,
  ready,
  saving,
  failed
}

class RunningVideoState {
  const RunningVideoState(
      {this.phase = RunningVideoPhase.idle,
      this.progress = 0,
      this.message = '请选择符合拍摄要求的视频。',
      this.report,
      this.saved = false});
  final RunningVideoPhase phase;
  final double progress;
  final String message;
  final RunningFormReport? report;
  final bool saved;
  bool get busy => [
        RunningVideoPhase.picking,
        RunningVideoPhase.extracting,
        RunningVideoPhase.measuring,
        RunningVideoPhase.saving
      ].contains(phase);
}

class RunningVideoController extends Notifier<RunningVideoState>
    with WidgetsBindingObserver {
  static const featureId = 'feature.motion_check';
  String? _taskId;
  RunningVideoPoseGateway? _gateway;
  FeatureOperation? _reportOperation;
  int _epoch = 0;
  bool _disposed = false;
  bool _starting = false;
  Future<void> _cleanup = Future.value();
  @override
  RunningVideoState build() {
    WidgetsBinding.instance.addObserver(this);
    bindFeatureController(ref, featureId, 'running_video_controller', this,
        cleanup: cancel);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      unawaited(cancel().catchError((Object _) {}));
    });
    return const RunningVideoState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 相册选择器会暂时 inactive；真正进入后台时才终止选择或分析。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(cancel().catchError((Object _) {}));
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> start({required bool captureConfirmed}) async {
    if (state.busy || _starting) return;
    if (!ref.read(runningVideoPreviewProvider)) {
      state = const RunningVideoState(
          phase: RunningVideoPhase.failed, message: '跑姿视频仍在验收中，正式发行尚未开放。');
      return;
    }
    if (!captureConfirmed) {
      state = const RunningVideoState(
          phase: RunningVideoPhase.failed, message: '请先确认拍摄条件和视频未经变速。');
      return;
    }
    final operation = ref.read(featureAccessProvider).beginOperation(featureId);
    final runtime = ref.read(pluginRuntimeProvider);
    final picker = ref.read(runningVideoPickerProvider);
    _starting = true;
    final cleanup = cancel();
    final epoch = _epoch;
    try {
      await cleanup;
      if (!_current(epoch)) return;
      operation.checkActive();
      final gateway = runtime.registry
          .readCapability<RunningVideoPoseGateway>(MotionCheckPlugin.extract);
      if (gateway == null || !gateway.isSupported) {
        throw StateError('跑姿视频分析仅支持 iPhone 本机运行');
      }
      final metrics = runtime.registry
          .readCapability<RunningMetricsService>(MotionCheckPlugin.measure)!;
      final assessment = runtime.registry
          .readCapability<RunningFormAssessmentService>(
              MotionCheckPlugin.assess)!;
      state = const RunningVideoState(
          phase: RunningVideoPhase.picking, message: '正在选择本机视频…');
      final path = await picker.pick();
      if (!_current(epoch)) return;
      operation.checkActive();
      if (path == null) {
        state = const RunningVideoState();
        return;
      }
      final id = _newTaskId();
      _taskId = id;
      _gateway = gateway;
      state = const RunningVideoState(
          phase: RunningVideoPhase.extracting, message: '正在设备端提取连续关键点…');
      final sequence = await gateway.analyze(
          taskId: id,
          path: path,
          onProgress: (progress) {
            if (_current(epoch)) {
              state = RunningVideoState(
                  phase: RunningVideoPhase.extracting,
                  progress: progress,
                  message: '正在设备端提取连续关键点…');
            }
          });
      if (!_current(epoch)) return;
      operation.checkActive();
      state = const RunningVideoState(
          phase: RunningVideoPhase.measuring,
          progress: 1,
          message: '正在计算可测分项…');
      final report = assessment.assess(
          id: id,
          now: DateTime.now(),
          sequence: sequence,
          measurements: metrics.measure(sequence),
          captureConfirmed: captureConfirmed);
      operation.checkActive();
      _reportOperation = operation;
      state = RunningVideoState(
          phase: RunningVideoPhase.ready,
          progress: 1,
          report: report,
          message: '分析完成；请复核证据，再手动保存报告。');
    } on FeatureOperationInvalidation {
      if (_current(epoch)) await cancel();
    } catch (error) {
      if (!_current(epoch)) return;
      final message = error is PlatformException
          ? (error.message ?? '视频识别失败，请重试。')
          : error is FormatException
              ? error.message
              : error is StateError
                  ? error.message.toString()
                  : '视频分析失败，请更换视频后重试。';
      try {
        await cancel();
      } catch (_) {}
      if (!_disposed) {
        state = RunningVideoState(
            phase: RunningVideoPhase.failed, message: message);
      }
    } finally {
      _starting = false;
    }
  }

  Future<Uint8List?> thumbnail(double seconds) async {
    final epoch = _epoch, id = _taskId, gateway = _gateway;
    if (id == null || gateway == null) return null;
    try {
      final image = await gateway.thumbnail(id, seconds);
      return _current(epoch) ? image : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final current = state,
        report = current.report,
        operation = _reportOperation;
    if (current.busy || report == null || operation == null || current.saved) {
      return;
    }
    final epoch = _epoch;
    final repository = ref.read(runningFormReportRepositoryProvider);
    state = RunningVideoState(
        phase: RunningVideoPhase.saving, report: report, message: '正在保存本机报告…');
    try {
      await operation.commit(() => repository.save(report));
      if (!_current(epoch)) return;
      state = RunningVideoState(
          phase: RunningVideoPhase.ready,
          report: report,
          saved: true,
          message: '报告已保存到本机历史；原视频未保存。');
    } on FeatureOperationInvalidation {
      if (_current(epoch)) await cancel();
    } catch (error) {
      if (_current(epoch)) {
        state = RunningVideoState(
            phase: RunningVideoPhase.ready,
            report: report,
            message: error is StateError
                ? error.message.toString()
                : '保存失败，当前分析仍保留，可重试。');
      }
    }
  }

  Future<void> deleteReport(String id) async {
    final operation = ref.read(featureAccessProvider).beginOperation(featureId);
    final repository = ref.read(runningFormReportRepositoryProvider);
    await operation.commit(() => repository.delete(id));
  }

  Future<void> cancel({bool notify = true}) async {
    _epoch++;
    final id = _taskId, gateway = _gateway;
    _reportOperation = null;
    if (!_disposed && notify) {
      state = const RunningVideoState(message: '可重新选择视频；上一任务已取消或关闭。');
    }
    if (!notify) {
      final epoch = _epoch;
      scheduleMicrotask(() {
        if (_current(epoch)) state = const RunningVideoState();
      });
    }
    final previous = _cleanup;
    _cleanup = () async {
      // 上次清理失败时允许重试同一任务；任务身份保留到原生确认完成。
      try {
        await previous;
      } catch (_) {}
      if (id != null && gateway != null) {
        await gateway.cancel(id);
        if (_taskId == id) {
          _taskId = null;
          _gateway = null;
        }
      }
    }();
    try {
      await _cleanup;
    } catch (_) {
      if (!_disposed) {
        state = const RunningVideoState(
            phase: RunningVideoPhase.failed,
            message: '视频临时文件尚未清理成功，请重试取消或重新打开应用。');
      }
      rethrow;
    }
  }

  String _newTaskId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
