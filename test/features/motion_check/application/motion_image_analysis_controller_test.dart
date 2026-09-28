import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:trainflow_ai/data/models/motion_pose.dart';
import 'package:trainflow_ai/data/seed/seed_motion_checks.dart';
import 'package:trainflow_ai/features/motion_check/application/motion_image_analysis_controller.dart';
import 'package:trainflow_ai/features/motion_check/application/pose_detector_gateway.dart';
import 'package:trainflow_ai/services/motion_pose_analysis_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

class _FakePicker implements MotionImagePicker {
  _FakePicker(this.file);

  final MotionImageFile? file;

  @override
  Future<MotionImageFile?> pick(ImageSource source) async => file;
}

class _FakePoseDetector implements PoseDetectorGateway {
  @override
  bool get isSupported => true;

  @override
  Future<MotionPoseFrame> detect({
    required String path,
    required Uint8List bytes,
  }) async =>
      MotionPoseAnalysisService.sampleFrameFor(seedMotionChecks.first.type);

  @override
  Future<void> dispose() async {}
}

void main() {
  test('取消照片选择不会生成识别结果', () async {
    final container = ProviderContainer(overrides: [
      motionImagePickerProvider.overrideWithValue(_FakePicker(null)),
      poseDetectorGatewayProvider.overrideWithValue(_FakePoseDetector()),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(motionImageAnalysisControllerProvider.notifier);
    controller.selectRule(seedMotionChecks.first);

    await controller.pickAndAnalyze(ImageSource.gallery);

    final state = container.read(motionImageAnalysisControllerProvider);
    expect(state.analysis, isNull);
    expect(state.status, MotionImageAnalysisStatus.idle);
  });

  test('照片只保留在临时状态，并在设备端生成姿态分析', () async {
    final container = ProviderContainer(overrides: [
      motionImagePickerProvider.overrideWithValue(
        _FakePicker(MotionImageFile(
          path: '/tmp/motion.jpg',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        )),
      ),
      poseDetectorGatewayProvider.overrideWithValue(_FakePoseDetector()),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(motionImageAnalysisControllerProvider.notifier);
    controller.selectRule(seedMotionChecks.first);

    await controller.pickAndAnalyze(ImageSource.camera);

    final state = container.read(motionImageAnalysisControllerProvider);
    expect(state.status, MotionImageAnalysisStatus.success);
    expect(state.imageBytes, isNotEmpty);
    expect(state.frame, isNotNull);
    expect(state.analysis, isNotNull);

    controller.clear();
    expect(container.read(motionImageAnalysisControllerProvider).imageBytes,
        isNull);
  });

  test('姿态检测 Future 迟到时停用会清理临时图像并丢弃结果', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _DeferredPoseDetector detector = _DeferredPoseDetector();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      motionImagePickerProvider.overrideWithValue(
        _FakePicker(MotionImageFile(
          path: '/tmp/motion-late.jpg',
          bytes: Uint8List.fromList(const <int>[1, 2, 3]),
        )),
      ),
      poseDetectorGatewayProvider.overrideWithValue(detector),
    ]);
    addTearDown(container.dispose);
    final MotionImageAnalysisController controller =
        container.read(motionImageAnalysisControllerProvider.notifier);
    controller.selectRule(seedMotionChecks.first);
    final Future<void> pending = controller.pickAndAnalyze(ImageSource.gallery);
    await detector.called.future;

    await runtime.disable('feature.motion_check');
    detector.result.complete(
      MotionPoseAnalysisService.sampleFrameFor(seedMotionChecks.first.type),
    );

    await expectLater(pending, throwsStateError);
    final MotionImageAnalysisState value =
        container.read(motionImageAnalysisControllerProvider);
    expect(value.status, MotionImageAnalysisStatus.idle);
    expect(value.imageBytes, isNull);
    expect(value.analysis, isNull);
    expect(detector.disposeCount, 0);
  });
}

class _DeferredPoseDetector implements PoseDetectorGateway {
  final Completer<void> called = Completer<void>();
  final Completer<MotionPoseFrame> result = Completer<MotionPoseFrame>();
  int disposeCount = 0;

  @override
  bool get isSupported => true;

  @override
  Future<MotionPoseFrame> detect({
    required String path,
    required Uint8List bytes,
  }) {
    called.complete();
    return result.future;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
