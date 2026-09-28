import 'dart:math' as math;
import '../../../data/models/motion_pose.dart';
import 'running_pose_models.dart';

class RunningMetric {
  RunningMetric(
      {required this.id,
      required this.title,
      required this.explanation,
      required this.coverage,
      required this.confidence,
      Map<String, double> values = const {},
      List<double> evidence = const []})
      : values = Map.unmodifiable(values),
        evidence = List.unmodifiable(evidence);
  final String id, title, explanation;
  final double coverage, confidence;
  final Map<String, double> values;
  final List<double> evidence;
  bool get measurable => values.isNotEmpty;
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'explanation': explanation,
        'coverage': coverage,
        'confidence': confidence,
        'values': values,
        'evidence': evidence
      };
  factory RunningMetric.fromJson(Map<String, dynamic> j) => RunningMetric(
      id: j['id'] as String,
      title: j['title'] as String,
      explanation: j['explanation'] as String,
      coverage: (j['coverage'] as num).toDouble(),
      confidence: (j['confidence'] as num).toDouble(),
      values: (j['values'] as Map)
          .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      evidence:
          (j['evidence'] as List).map((v) => (v as num).toDouble()).toList());
}

class RunningMeasurements {
  const RunningMeasurements(this.side, this.metrics);
  final String side;
  final List<RunningMetric> metrics;
}

class _Sample {
  const _Sample(this.time, this.value, this.confidence, this.segment);
  final double time, value, confidence;
  final int segment;
}

/// 所有阈值用于测量有效性或本段波动说明，不代表医学或理想跑姿标准。
class RunningMetricsService {
  static const version = '1.0.0';
  RunningMeasurements measure(RunningPoseSequence sequence) {
    final frames = sequence.frames;
    bool validTime = sequence.duration.isFinite &&
        sequence.duration >= 5 &&
        sequence.duration <= 20 &&
        frames.length <= 601;
    double previous = -1;
    for (final f in frames) {
      if (!f.seconds.isFinite ||
          f.seconds <= previous ||
          f.seconds > sequence.duration + .1 ||
          f.seconds < 0 ||
          f.width <= 0 ||
          f.height <= 0 ||
          !f.width.isFinite ||
          !f.height.isFinite ||
          (frames.isNotEmpty &&
              (f.width != frames.first.width ||
                  f.height != frames.first.height))) {
        validTime = false;
      }
      previous = f.seconds;
    }
    final left = _collect(frames, true);
    final right = _collect(frames, false);
    // 先比较膝部覆盖率，再比较躯干覆盖率，完全相同时固定使用左侧。
    final useLeft = left.$1.length > right.$1.length ||
        (left.$1.length == right.$1.length &&
            left.$2.length >= right.$2.length);
    final (knees, trunks) = useLeft ? left : right;
    final kneeCoverage = frames.isEmpty ? 0.0 : knees.length / frames.length;
    final trunkCoverage = frames.isEmpty ? 0.0 : trunks.length / frames.length;
    final kneeValues = knees.map((s) => s.value).toList();
    final moving = kneeValues.isNotEmpty &&
        kneeValues.reduce(math.max) - kneeValues.reduce(math.min) >= 10;
    final commonReason = !validTime
        ? '视频时间戳、时长或画面尺寸异常'
        : !moving
            ? '未检测到足够的连续屈伸变化，可能静止或关键点不足'
            : null;
    RunningMetric unavailable(String id, String title, String reason,
            List<_Sample> samples, double coverage) =>
        RunningMetric(
            id: id,
            title: title,
            explanation: '无法评估：$reason。',
            coverage: coverage,
            confidence: _confidence(samples));
    final metrics = <RunningMetric>[];
    final cycles = _cycles(knees);
    final periods = cycles.map((c) => c.$2.time - c.$1.time).toList();
    if (commonReason != null || kneeCoverage < .8 || periods.length < 6) {
      metrics.add(unavailable(
          'rhythm',
          '周期节奏一致性',
          commonReason ?? (kneeCoverage < .8 ? '有效帧不足 80%' : '完整周期不足六个'),
          knees,
          kneeCoverage));
    } else {
      final mean = periods.reduce((a, b) => a + b) / periods.length;
      final cv = math.sqrt(periods
                  .map((p) => math.pow(p - mean, 2))
                  .reduce((a, b) => a + b) /
              periods.length) /
          mean *
          100;
      metrics.add(RunningMetric(
          id: 'rhythm',
          title: '周期节奏一致性',
          explanation:
              '${cv <= 5 ? '本段较一致' : cv <= 10 ? '存在波动' : '波动明显'}；仅描述本段节奏，不代表最佳步频或跑姿总评。',
          coverage: kneeCoverage,
          confidence: _confidence(knees),
          values: {
            '周期中位时长（秒）': quantile(periods, .5),
            '周期变异系数（%）': cv,
            '完整周期数': periods.length.toDouble()
          },
          evidence:
              cycles.expand((c) => [c.$1.time, c.$2.time]).toSet().toList()));
    }
    if (commonReason != null || trunkCoverage < .8 || trunks.length < 5) {
      metrics.add(unavailable('trunk', '躯干角度变化',
          commonReason ?? '肩髋关键点有效帧不足 80%', trunks, trunkCoverage));
    } else {
      final values = trunks.map((s) => s.value).toList();
      metrics.add(RunningMetric(
          id: 'trunk',
          title: '躯干角度变化',
          explanation: '相对画面竖直方向的绝对角度，仅测量本段变化，不判定理想前倾角。',
          coverage: trunkCoverage,
          confidence: _confidence(trunks),
          values: {
            '角度中位数（°）': quantile(values, .5),
            '角度四分位距（°）': quantile(values, .75) - quantile(values, .25)
          },
          evidence: _extremes(trunks)));
    }
    if (commonReason != null || kneeCoverage < .8 || knees.length < 5) {
      metrics.add(unavailable('knee', '膝关节活动变化',
          commonReason ?? '髋膝踝关键点有效帧不足 80%', knees, kneeCoverage));
    } else {
      final ranges = cycles.map((c) {
        final v = knees
            .where((s) =>
                s.segment == c.$1.segment &&
                s.time >= c.$1.time &&
                s.time <= c.$2.time)
            .map((s) => s.value)
            .toList();
        return v.reduce(math.max) - v.reduce(math.min);
      }).toList();
      metrics.add(RunningMetric(
          id: 'knee',
          title: '膝关节活动变化',
          explanation:
              '清晰侧几何测量，不推断疼痛、损伤、触地方式或落地冲击。${ranges.isEmpty ? '完整周期不足，暂不显示周期幅度。' : ''}',
          coverage: kneeCoverage,
          confidence: _confidence(knees),
          values: {
            '最小夹角（°）': kneeValues.reduce(math.min),
            '最大夹角（°）': kneeValues.reduce(math.max),
            if (ranges.isNotEmpty) '周期活动幅度中位数（°）': quantile(ranges, .5),
            if (ranges.isNotEmpty)
              '周期活动幅度四分位距（°）': quantile(ranges, .75) - quantile(ranges, .25)
          },
          evidence: _extremes(knees)));
    }
    return RunningMeasurements(
        useLeft ? '左侧' : '右侧', List.unmodifiable(metrics));
  }

  (List<_Sample>, List<_Sample>) _collect(
      List<RunningPoseFrame> frames, bool left) {
    final knees = <_Sample>[], trunks = <_Sample>[];
    var kneeSegment = 0, trunkSegment = 0;
    RunningPoseFrame? previous;
    final hipType =
        left ? MotionPoseLandmarkType.leftHip : MotionPoseLandmarkType.rightHip;
    final kneeType = left
        ? MotionPoseLandmarkType.leftKnee
        : MotionPoseLandmarkType.rightKnee;
    final ankleType = left
        ? MotionPoseLandmarkType.leftAnkle
        : MotionPoseLandmarkType.rightAnkle;
    final shoulderType = left
        ? MotionPoseLandmarkType.leftShoulder
        : MotionPoseLandmarkType.rightShoulder;
    for (final frame in frames) {
      final gap = previous != null && frame.seconds - previous.seconds > .2;
      bool jumped(MotionPoseLandmarkType type) {
        final a = previous?.point(type), b = frame.point(type);
        return !gap &&
            a != null &&
            b != null &&
            math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)) > .2;
      }

      final hip = frame.point(hipType),
          knee = frame.point(kneeType),
          ankle = frame.point(ankleType),
          shoulder = frame.point(shoulderType);
      if (gap) {
        kneeSegment++;
        trunkSegment++;
      }
      final kneeAngle = frame.isValid &&
              hip != null &&
              knee != null &&
              ankle != null &&
              ![hipType, kneeType, ankleType].any(jumped)
          ? angle(hip, knee, ankle, frame.width, frame.height)
          : null;
      if (kneeAngle == null) {
        kneeSegment++;
      } else {
        knees.add(_Sample(
            frame.seconds,
            kneeAngle,
            [hip!.visibility, knee!.visibility, ankle!.visibility]
                .reduce(math.min),
            kneeSegment));
      }
      if (!frame.isValid ||
          hip == null ||
          shoulder == null ||
          [hipType, shoulderType].any(jumped) ||
          ((shoulder.x - hip.x).abs() + (shoulder.y - hip.y).abs()) < .00001) {
        trunkSegment++;
      } else {
        final value = math.atan2(((shoulder.x - hip.x) * frame.width).abs(),
                (hip.y - shoulder.y) * frame.height) *
            180 /
            math.pi;
        trunks.add(_Sample(frame.seconds, value,
            math.min(hip.visibility, shoulder.visibility), trunkSegment));
      }
      previous = frame;
    }
    return (knees, trunks);
  }

  List<(_Sample, _Sample)> _cycles(List<_Sample> samples) {
    final result = <(_Sample, _Sample)>[];
    final segments = <int, List<_Sample>>{};
    for (final s in samples) {
      segments.putIfAbsent(s.segment, () => []).add(s);
    }
    for (final values in segments.values) {
      if (values.length < 3) continue;
      final smooth = [
        values.first,
        for (var i = 1; i < values.length - 1; i++)
          _Sample(
              values[i].time,
              quantile(
                  [values[i - 1].value, values[i].value, values[i + 1].value],
                  .5),
              values[i].confidence,
              values[i].segment),
        values.last
      ];
      var high = smooth.first.value;
      _Sample? low, previousPeak;
      for (final s in smooth.skip(1)) {
        if (low == null) {
          high = math.max(high, s.value);
          if (high - s.value >= 10) low = s;
        } else if (s.value <= low.value) {
          low = s;
        } else if (s.value - low.value >= 10) {
          if (previousPeak != null) {
            final period = low.time - previousPeak.time;
            // 排除采样抖动和长暂停形成的假周期；阈值不作为训练目标。
            if (period >= .25 && period <= 2) result.add((previousPeak, low));
          }
          previousPeak = low;
          low = null;
          high = s.value;
        }
      }
    }
    return result;
  }

  static double? angle(MotionPoseLandmark a, MotionPoseLandmark b,
      MotionPoseLandmark c, double width, double height) {
    final ax = (a.x - b.x) * width, ay = (a.y - b.y) * height;
    final cx = (c.x - b.x) * width, cy = (c.y - b.y) * height;
    final lengths = math.sqrt(ax * ax + ay * ay) * math.sqrt(cx * cx + cy * cy);
    if (!lengths.isFinite || lengths < .00001) return null;
    return math.acos(((ax * cx + ay * cy) / lengths).clamp(-1, 1)) *
        180 /
        math.pi;
  }

  static double quantile(List<double> values, double p) {
    final sorted = [...values]..sort();
    final index = (sorted.length - 1) * p,
        lo = index.floor(),
        hi = index.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (index - lo);
  }

  double _confidence(List<_Sample> values) => values.isEmpty
      ? 0
      : quantile(values.map((s) => s.confidence).toList(), .5);
  List<double> _extremes(List<_Sample> values) {
    final ordered = [...values]..sort((a, b) => a.value.compareTo(b.value));
    return [
      ordered.first.time,
      ordered[ordered.length ~/ 2].time,
      ordered.last.time
    ];
  }
}
