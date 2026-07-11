import 'dart:convert';

import '../data/models/motion_pose.dart';

class MotionPoseImportResult {
  final MotionPoseFrame? frame;
  final String? errorMessage;

  const MotionPoseImportResult({
    required this.frame,
    required this.errorMessage,
  });

  bool get isValid => frame != null && errorMessage == null;
}

class MotionPoseImportService {
  MotionPoseImportResult parse(String rawJson) {
    final String trimmedJson = rawJson.trim();
    if (trimmedJson.isEmpty) {
      return const MotionPoseImportResult(
        frame: null,
        errorMessage: '关键点数据不能为空。',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmedJson);
    } on FormatException {
      return const MotionPoseImportResult(
        frame: null,
        errorMessage: '关键点数据不是有效 JSON。',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      return const MotionPoseImportResult(
        frame: null,
        errorMessage: '关键点数据必须是 JSON 对象。',
      );
    }

    final dynamic nestedFrame = decoded['poseFrame'];
    final Map<String, dynamic> frameJson =
        nestedFrame is Map<String, dynamic> ? nestedFrame : decoded;
    final MotionPoseFrame parsedFrame = MotionPoseFrame.fromJson(frameJson);
    if (parsedFrame.landmarks.isEmpty) {
      return const MotionPoseImportResult(
        frame: null,
        errorMessage: '关键点数据至少需要包含一个关键点。',
      );
    }

    final Set<MotionPoseLandmarkType> seenTypes = {};
    for (final MotionPoseLandmark landmark in parsedFrame.landmarks) {
      if (!seenTypes.add(landmark.type)) {
        return MotionPoseImportResult(
          frame: null,
          errorMessage: '${landmark.type.label}重复，不能导入重复关键点。',
        );
      }
      if (!_isNormalized(landmark.x) || !_isNormalized(landmark.y)) {
        return MotionPoseImportResult(
          frame: null,
          errorMessage: '${landmark.type.label}坐标必须在 0 到 1 之间。',
        );
      }
      if (!_isNormalized(landmark.visibility)) {
        return MotionPoseImportResult(
          frame: null,
          errorMessage: '${landmark.type.label}可见度必须在 0 到 1 之间。',
        );
      }
    }

    final MotionPoseFrame normalizedFrame = MotionPoseFrame(
      capturedAt: frameJson['capturedAt'] == null
          ? DateTime.now()
          : parsedFrame.capturedAt,
      sourceLabel: parsedFrame.sourceLabel,
      landmarks: parsedFrame.landmarks,
    );
    return MotionPoseImportResult(
      frame: normalizedFrame,
      errorMessage: null,
    );
  }

  bool _isNormalized(double value) {
    return value.isFinite && value >= 0 && value <= 1;
  }
}
