import 'dart:typed_data';

import '../../../data/models/motion_pose.dart';

abstract class PoseDetectorGateway {
  bool get isSupported;
  Future<MotionPoseFrame> detect(
      {required String path, required Uint8List bytes});
  Future<void> dispose();
}

PoseDetectorGateway createPoseDetectorGateway() => _UnsupportedPoseDetector();

class _UnsupportedPoseDetector implements PoseDetectorGateway {
  @override
  bool get isSupported => false;

  @override
  Future<MotionPoseFrame> detect({
    required String path,
    required Uint8List bytes,
  }) {
    throw UnsupportedError('当前平台暂不支持照片姿态识别');
  }

  @override
  Future<void> dispose() async {}
}
