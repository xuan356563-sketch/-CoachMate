import '../../../data/models/motion_pose.dart';

/// 时间取自视频展示时间戳，坐标已经校正旋转，左上角为原点。
class RunningPoseFrame {
  RunningPoseFrame(
      {required this.seconds,
      required this.width,
      required this.height,
      required this.status,
      required List<MotionPoseLandmark> landmarks})
      : landmarks = List.unmodifiable(landmarks);
  final double seconds, width, height;
  final String status;
  final List<MotionPoseLandmark> landmarks;
  bool get isValid =>
      status == 'valid' &&
      seconds.isFinite &&
      seconds >= 0 &&
      width.isFinite &&
      width > 0 &&
      height.isFinite &&
      height > 0;
  MotionPoseLandmark? point(MotionPoseLandmarkType type) {
    for (final p in landmarks) {
      if (p.type == type &&
          p.visibility.isFinite &&
          p.visibility >= .6 &&
          p.visibility <= 1 &&
          p.x.isFinite &&
          p.y.isFinite &&
          p.x >= 0 &&
          p.x <= 1 &&
          p.y >= 0 &&
          p.y <= 1) {
        return p;
      }
    }
    return null;
  }

  factory RunningPoseFrame.fromJson(Map<String, dynamic> json) {
    final seconds = json['seconds'];
    final width = json['width'];
    final height = json['height'];
    if (seconds is! num ||
        !seconds.isFinite ||
        seconds < 0 ||
        width is! num ||
        !width.isFinite ||
        width <= 0 ||
        height is! num ||
        !height.isFinite ||
        height <= 0) {
      throw const FormatException('视频帧时间戳或画面尺寸无效');
    }
    final points = <MotionPoseLandmark>[];
    final seen = <String>{};
    for (final raw in json['landmarks'] as List? ?? const []) {
      final p = Map<String, dynamic>.from(raw as Map);
      final type = p['type'];
      if (type is! String ||
          !MotionPoseLandmarkType.values.any((v) => v.jsonValue == type) ||
          !seen.add(type)) {
        throw const FormatException('视频关键点类型无效或重复');
      }
      if (p['x'] is! num || p['y'] is! num || p['visibility'] is! num) {
        throw const FormatException('视频关键点缺少坐标或置信度');
      }
      points.add(MotionPoseLandmark.fromJson(p));
    }
    return RunningPoseFrame(
        seconds: seconds.toDouble(),
        width: width.toDouble(),
        height: height.toDouble(),
        status: json['status'] as String,
        landmarks: points);
  }
  Map<String, dynamic> toJson() => {
        'seconds': seconds,
        'width': width,
        'height': height,
        'status': status,
        'landmarks': landmarks.map((p) => p.toJson()).toList()
      };
}

class RunningPoseSequence {
  RunningPoseSequence(
      {required this.duration,
      required List<RunningPoseFrame> frames,
      required this.detectorVersion})
      : frames = List.unmodifiable(frames);
  final double duration;
  final List<RunningPoseFrame> frames;
  final String detectorVersion;
}
