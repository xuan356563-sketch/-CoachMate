import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:trainflow_ai/data/models/motion_pose.dart';
import 'package:trainflow_ai/data/seed/seed_motion_checks.dart';
import 'package:trainflow_ai/features/motion_check/application/motion_image_analysis_controller.dart';
import 'package:trainflow_ai/features/motion_check/application/pose_detector_gateway.dart';
import 'package:trainflow_ai/services/motion_pose_analysis_service.dart';

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
}
