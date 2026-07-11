import 'dart:math' as math;

import '../data/models/motion_check.dart';
import '../data/models/motion_pose.dart';

class MotionPoseAnalysisService {
  MotionPoseAnalysis analyze({
    required MotionCheckType type,
    required MotionPoseFrame frame,
  }) {
    final List<MotionPoseMeasurement> measurements = [];
    final List<String> errors = [];
    bool hasMissingLandmarks = false;

    void addMeasurement(
      String label,
      MotionPoseLandmarkType first,
      MotionPoseLandmarkType vertex,
      MotionPoseLandmarkType third,
    ) {
      final double? angle = _angle(
        frame.landmark(first),
        frame.landmark(vertex),
        frame.landmark(third),
      );
      if (angle == null) {
        hasMissingLandmarks = true;
        return;
      }
      measurements.add(
        MotionPoseMeasurement(label: label, angleDegrees: angle),
      );
    }

    switch (type) {
      case MotionCheckType.squat:
      case MotionCheckType.lunge:
        addMeasurement(
          '左膝夹角',
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftKnee,
          MotionPoseLandmarkType.leftAnkle,
        );
        addMeasurement(
          '右膝夹角',
          MotionPoseLandmarkType.rightHip,
          MotionPoseLandmarkType.rightKnee,
          MotionPoseLandmarkType.rightAnkle,
        );
        break;
      case MotionCheckType.hipHinge:
        addMeasurement(
          '左侧髋折叠角',
          MotionPoseLandmarkType.leftShoulder,
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftKnee,
        );
        addMeasurement(
          '右侧髋折叠角',
          MotionPoseLandmarkType.rightShoulder,
          MotionPoseLandmarkType.rightHip,
          MotionPoseLandmarkType.rightKnee,
        );
        break;
      case MotionCheckType.pushUp:
        addMeasurement(
          '左肘夹角',
          MotionPoseLandmarkType.leftShoulder,
          MotionPoseLandmarkType.leftElbow,
          MotionPoseLandmarkType.leftWrist,
        );
        addMeasurement(
          '左侧身体线',
          MotionPoseLandmarkType.leftShoulder,
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftAnkle,
        );
        break;
      case MotionCheckType.plank:
        addMeasurement(
          '左侧身体线',
          MotionPoseLandmarkType.leftShoulder,
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftAnkle,
        );
        addMeasurement(
          '右侧身体线',
          MotionPoseLandmarkType.rightShoulder,
          MotionPoseLandmarkType.rightHip,
          MotionPoseLandmarkType.rightAnkle,
        );
        break;
      case MotionCheckType.calfRaise:
        addMeasurement(
          '左侧下肢对齐角',
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftKnee,
          MotionPoseLandmarkType.leftAnkle,
        );
        addMeasurement(
          '右侧下肢对齐角',
          MotionPoseLandmarkType.rightHip,
          MotionPoseLandmarkType.rightKnee,
          MotionPoseLandmarkType.rightAnkle,
        );
        break;
      case MotionCheckType.highKnee:
        addMeasurement(
          '左侧抬膝角',
          MotionPoseLandmarkType.leftShoulder,
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftKnee,
        );
        addMeasurement(
          '右侧抬膝角',
          MotionPoseLandmarkType.rightShoulder,
          MotionPoseLandmarkType.rightHip,
          MotionPoseLandmarkType.rightKnee,
        );
        break;
      case MotionCheckType.sideRun:
        addMeasurement(
          '左侧跑姿角',
          MotionPoseLandmarkType.leftShoulder,
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftKnee,
        );
        addMeasurement(
          '左膝夹角',
          MotionPoseLandmarkType.leftHip,
          MotionPoseLandmarkType.leftKnee,
          MotionPoseLandmarkType.leftAnkle,
        );
        break;
    }

    if (measurements.isEmpty) {
      errors.add('关键点不足，无法完成角度计算。');
    } else if (hasMissingLandmarks) {
      errors.add('部分关键点可见度不足，结果需要人工复核。');
    }

    final double minimumAngle = measurements.isEmpty
        ? 180
        : measurements
            .map(
                (MotionPoseMeasurement measurement) => measurement.angleDegrees)
            .reduce(math.min);
    final double maximumAngle = measurements.isEmpty
        ? 0
        : measurements
            .map(
                (MotionPoseMeasurement measurement) => measurement.angleDegrees)
            .reduce(math.max);

    switch (type) {
      case MotionCheckType.squat:
      case MotionCheckType.lunge:
        if (minimumAngle > 165) {
          errors.add('膝关节折叠幅度偏浅，先确认动作深度和活动范围。');
        }
        if (minimumAngle < 65) {
          errors.add('膝关节折叠角度较小，先降低幅度并复核疼痛反馈。');
        }
        break;
      case MotionCheckType.hipHinge:
        if (minimumAngle > 165) {
          errors.add('髋部折叠幅度偏浅，先确认髋部是否主动后移。');
        }
        break;
      case MotionCheckType.pushUp:
      case MotionCheckType.plank:
        if (minimumAngle < 155) {
          errors.add('身体线角度偏小，可能存在塌腰或躯干控制不足。');
        }
        break;
      case MotionCheckType.calfRaise:
        if (maximumAngle < 150) {
          errors.add('下肢对齐角度异常，先降低冲击并复核踝膝稳定。');
        }
        break;
      case MotionCheckType.highKnee:
        if (minimumAngle > 145) {
          errors.add('抬膝角度变化较小，先降低速度练习髋部主动抬升。');
        }
        break;
      case MotionCheckType.sideRun:
        if (minimumAngle < 145) {
          errors.add('跑姿角度变化较大，先降低速度并复核躯干稳定。');
        }
        break;
    }

    final int score =
        measurements.isEmpty ? 0 : math.max(40, 100 - errors.length * 15);
    final MotionRiskLevel riskLevel = score < 60
        ? MotionRiskLevel.high
        : score < 80
            ? MotionRiskLevel.medium
            : MotionRiskLevel.low;
    final double confidence = measurements.isEmpty
        ? 0.2
        : math.min(0.95, 0.45 + measurements.length * 0.12);

    return MotionPoseAnalysis(
      type: type,
      score: score,
      riskLevel: riskLevel,
      confidence: confidence,
      detectedErrors: errors,
      measurements: measurements,
    );
  }

  static MotionPoseFrame sampleFrameFor(MotionCheckType type) {
    final DateTime capturedAt = DateTime.now();
    const List<MotionPoseLandmark> landmarks = [
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.nose,
        x: 0.5,
        y: 0.1,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.leftShoulder,
        x: 0.35,
        y: 0.25,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.rightShoulder,
        x: 0.65,
        y: 0.25,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.leftElbow,
        x: 0.25,
        y: 0.4,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.rightElbow,
        x: 0.75,
        y: 0.4,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.leftWrist,
        x: 0.2,
        y: 0.55,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.rightWrist,
        x: 0.8,
        y: 0.55,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.leftHip,
        x: 0.4,
        y: 0.5,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.rightHip,
        x: 0.6,
        y: 0.5,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.leftKnee,
        x: 0.38,
        y: 0.72,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.rightKnee,
        x: 0.62,
        y: 0.72,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.leftAnkle,
        x: 0.4,
        y: 0.92,
      ),
      MotionPoseLandmark(
        type: MotionPoseLandmarkType.rightAnkle,
        x: 0.6,
        y: 0.92,
      ),
    ];
    return MotionPoseFrame(
      capturedAt: capturedAt,
      sourceLabel: '结构化关键点样例 · ${type.label}',
      landmarks: landmarks,
    );
  }

  double? _angle(
    MotionPoseLandmark? first,
    MotionPoseLandmark? vertex,
    MotionPoseLandmark? third,
  ) {
    if (first == null || vertex == null || third == null) {
      return null;
    }
    if (first.visibility < 0.4 ||
        vertex.visibility < 0.4 ||
        third.visibility < 0.4) {
      return null;
    }
    final double firstX = first.x - vertex.x;
    final double firstY = first.y - vertex.y;
    final double thirdX = third.x - vertex.x;
    final double thirdY = third.y - vertex.y;
    final double firstLength = math.sqrt(firstX * firstX + firstY * firstY);
    final double thirdLength = math.sqrt(thirdX * thirdX + thirdY * thirdY);
    if (firstLength == 0 || thirdLength == 0) {
      return null;
    }
    final double cosine =
        (firstX * thirdX + firstY * thirdY) / (firstLength * thirdLength);
    return math.acos(cosine.clamp(-1.0, 1.0).toDouble()) * 180 / math.pi;
  }
}
