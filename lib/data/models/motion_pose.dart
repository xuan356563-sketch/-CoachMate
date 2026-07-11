import 'motion_check.dart';

enum MotionPoseLandmarkType {
  nose,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

extension MotionPoseLandmarkTypeJson on MotionPoseLandmarkType {
  String get jsonValue {
    return switch (this) {
      MotionPoseLandmarkType.nose => 'nose',
      MotionPoseLandmarkType.leftShoulder => 'left_shoulder',
      MotionPoseLandmarkType.rightShoulder => 'right_shoulder',
      MotionPoseLandmarkType.leftElbow => 'left_elbow',
      MotionPoseLandmarkType.rightElbow => 'right_elbow',
      MotionPoseLandmarkType.leftWrist => 'left_wrist',
      MotionPoseLandmarkType.rightWrist => 'right_wrist',
      MotionPoseLandmarkType.leftHip => 'left_hip',
      MotionPoseLandmarkType.rightHip => 'right_hip',
      MotionPoseLandmarkType.leftKnee => 'left_knee',
      MotionPoseLandmarkType.rightKnee => 'right_knee',
      MotionPoseLandmarkType.leftAnkle => 'left_ankle',
      MotionPoseLandmarkType.rightAnkle => 'right_ankle',
    };
  }

  String get label {
    return switch (this) {
      MotionPoseLandmarkType.nose => '鼻尖',
      MotionPoseLandmarkType.leftShoulder => '左肩',
      MotionPoseLandmarkType.rightShoulder => '右肩',
      MotionPoseLandmarkType.leftElbow => '左肘',
      MotionPoseLandmarkType.rightElbow => '右肘',
      MotionPoseLandmarkType.leftWrist => '左腕',
      MotionPoseLandmarkType.rightWrist => '右腕',
      MotionPoseLandmarkType.leftHip => '左髋',
      MotionPoseLandmarkType.rightHip => '右髋',
      MotionPoseLandmarkType.leftKnee => '左膝',
      MotionPoseLandmarkType.rightKnee => '右膝',
      MotionPoseLandmarkType.leftAnkle => '左踝',
      MotionPoseLandmarkType.rightAnkle => '右踝',
    };
  }
}

MotionPoseLandmarkType motionPoseLandmarkTypeFromJson(String? value) {
  for (final MotionPoseLandmarkType type in MotionPoseLandmarkType.values) {
    if (type.jsonValue == value) {
      return type;
    }
  }
  return MotionPoseLandmarkType.nose;
}

class MotionPoseLandmark {
  final MotionPoseLandmarkType type;
  final double x;
  final double y;
  final double visibility;

  const MotionPoseLandmark({
    required this.type,
    required this.x,
    required this.y,
    this.visibility = 1,
  });

  factory MotionPoseLandmark.fromJson(Map<String, dynamic> json) {
    return MotionPoseLandmark(
      type: motionPoseLandmarkTypeFromJson(json['type'] as String?),
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      visibility: (json['visibility'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.jsonValue,
      'x': x,
      'y': y,
      'visibility': visibility,
    };
  }
}

class MotionPoseFrame {
  final DateTime capturedAt;
  final String sourceLabel;
  final List<MotionPoseLandmark> landmarks;

  const MotionPoseFrame({
    required this.capturedAt,
    required this.sourceLabel,
    required this.landmarks,
  });

  MotionPoseLandmark? landmark(MotionPoseLandmarkType type) {
    for (final MotionPoseLandmark landmark in landmarks) {
      if (landmark.type == type) {
        return landmark;
      }
    }
    return null;
  }

  factory MotionPoseFrame.fromJson(Map<String, dynamic> json) {
    final List<dynamic> landmarkJson =
        json['landmarks'] as List<dynamic>? ?? const [];
    return MotionPoseFrame(
      capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceLabel: json['sourceLabel'] as String? ?? '结构化关键点',
      landmarks: landmarkJson
          .whereType<Map<String, dynamic>>()
          .map(MotionPoseLandmark.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'capturedAt': capturedAt.toIso8601String(),
      'sourceLabel': sourceLabel,
      'landmarks': landmarks
          .map((MotionPoseLandmark landmark) => landmark.toJson())
          .toList(),
    };
  }
}

class MotionPoseMeasurement {
  final String label;
  final double angleDegrees;

  const MotionPoseMeasurement({
    required this.label,
    required this.angleDegrees,
  });

  String get valueLabel => '${angleDegrees.toStringAsFixed(1)}°';
}

class MotionPoseAnalysis {
  final MotionCheckType type;
  final int score;
  final MotionRiskLevel riskLevel;
  final double confidence;
  final List<String> detectedErrors;
  final List<MotionPoseMeasurement> measurements;

  const MotionPoseAnalysis({
    required this.type,
    required this.score,
    required this.riskLevel,
    required this.confidence,
    required this.detectedErrors,
    required this.measurements,
  });
}
