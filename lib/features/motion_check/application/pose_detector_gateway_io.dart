import 'dart:io';

import 'package:flutter/services.dart';

import '../../../data/models/motion_pose.dart';

abstract class PoseDetectorGateway {
  bool get isSupported;
  Future<MotionPoseFrame> detect(
      {required String path, required Uint8List bytes});
  Future<void> dispose();
}

PoseDetectorGateway createPoseDetectorGateway() => _VisionPoseDetector();

class _VisionPoseDetector implements PoseDetectorGateway {
  static const MethodChannel _channel =
      MethodChannel('trainflow.ai/vision_pose');

  @override
  bool get isSupported => Platform.isIOS;

  @override
  Future<MotionPoseFrame> detect({
    required String path,
    required Uint8List bytes,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('当前平台暂不支持照片姿态识别');
    }
    final List<dynamic>? raw = await _channel.invokeListMethod<dynamic>(
      'detectPose',
      <String, dynamic>{'path': path},
    );
    if (raw == null || raw.isEmpty) {
      throw const FormatException('照片中没有识别到人体，请确保全身清晰入镜。');
    }
    final List<MotionPoseLandmark> landmarks = <MotionPoseLandmark>[];
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final MotionPoseLandmarkType? type = _landmarkTypes[item['type']];
      if (type == null) continue;
      landmarks.add(MotionPoseLandmark(
        type: type,
        x: (item['x'] as num?)?.toDouble() ?? 0,
        y: (item['y'] as num?)?.toDouble() ?? 0,
        visibility: (item['confidence'] as num?)?.toDouble() ?? 0,
      ));
    }
    if (landmarks.length < 10) {
      throw const FormatException('可见关键点不足，请重新拍摄完整身体。');
    }
    final double averageConfidence = landmarks
            .map((MotionPoseLandmark item) => item.visibility)
            .reduce((double a, double b) => a + b) /
        landmarks.length;
    if (averageConfidence < 0.6) {
      throw const FormatException('关键点置信度不足，请在光线充足处重新拍摄。');
    }
    return MotionPoseFrame(
      capturedAt: DateTime.now(),
      sourceLabel: '手机照片 · 设备端姿态识别',
      landmarks: landmarks,
    );
  }

  @override
  Future<void> dispose() async {}
}

const Map<Object?, MotionPoseLandmarkType> _landmarkTypes = {
  'nose': MotionPoseLandmarkType.nose,
  'left_shoulder': MotionPoseLandmarkType.leftShoulder,
  'right_shoulder': MotionPoseLandmarkType.rightShoulder,
  'left_elbow': MotionPoseLandmarkType.leftElbow,
  'right_elbow': MotionPoseLandmarkType.rightElbow,
  'left_wrist': MotionPoseLandmarkType.leftWrist,
  'right_wrist': MotionPoseLandmarkType.rightWrist,
  'left_hip': MotionPoseLandmarkType.leftHip,
  'right_hip': MotionPoseLandmarkType.rightHip,
  'left_knee': MotionPoseLandmarkType.leftKnee,
  'right_knee': MotionPoseLandmarkType.rightKnee,
  'left_ankle': MotionPoseLandmarkType.leftAnkle,
  'right_ankle': MotionPoseLandmarkType.rightAnkle,
};
