import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/motion_pose.dart';
import 'package:trainflow_ai/features/motion_check/running/running_pose_models.dart';
import 'package:trainflow_ai/features/motion_check/running/running_metrics_service.dart';
import 'package:trainflow_ai/features/motion_check/running/running_form_assessment_service.dart';

RunningPoseSequence sequence(
        {double amplitude = 40,
        double period = .8,
        bool mirror = false,
        String Function(int)? status,
        double Function(int)? time,
        double Function(double)? phase,
        bool hideShoulder = false}) =>
    RunningPoseSequence(
        duration: 10,
        detectorVersion: '合成夹具',
        frames: List.generate(301, (i) {
          final t = i / 30,
              angle = (110 +
                      amplitude *
                          math.cos(
                              2 * math.pi * (phase?.call(t) ?? t / period))) *
                  math.pi /
                  180;
          MotionPoseLandmark p(
                  MotionPoseLandmarkType type, double x, double y) =>
              MotionPoseLandmark(
                  type: type, x: mirror ? 1 - x : x, y: y, visibility: .9);
          return RunningPoseFrame(
              seconds: time?.call(i) ?? t,
              width: 640,
              height: 480,
              status: status?.call(i) ?? 'valid',
              landmarks: [
                if (!hideShoulder)
                  p(MotionPoseLandmarkType.leftShoulder, .4, .2),
                p(MotionPoseLandmarkType.leftHip, .4, .4),
                p(MotionPoseLandmarkType.leftKnee, .4, .6),
                p(
                    MotionPoseLandmarkType.leftAnkle,
                    .4 + math.sin(angle) * .18 * 480 / 640,
                    .6 - math.cos(angle) * .18),
              ]);
        }));
void main() {
  final service = RunningMetricsService();
  test('非方形画面恢复比例后角度正确，镜像结果等价', () {
    final a = service.measure(sequence()),
        b = service.measure(sequence(mirror: true));
    expect(a.metrics[0].measurable, isTrue);
    expect(a.metrics[0].values['周期中位时长（秒）'], closeTo(.8, .035));
    expect(a.metrics[1].values['角度中位数（°）'], 0);
    expect(a.metrics[2].values['最小夹角（°）'], closeTo(70, .1));
    expect(a.metrics[2].values['最大夹角（°）'], closeTo(150, .1));
    for (var i = 0; i < 3; i++) {
      expect(b.metrics[i].values.keys, a.metrics[i].values.keys);
      for (final key in a.metrics[i].values.keys) {
        expect(b.metrics[i].values[key],
            closeTo(a.metrics[i].values[key]!, .0001));
      }
    }
  });
  test('周期改变会改变波动等级，不能复用固定结果', () {
    final steady = service.measure(sequence()).metrics.first;
    final varying = service
        .measure(sequence(phase: (t) => t < 5 ? t : 5 + (t - 5) / .6))
        .metrics
        .first;
    expect(steady.explanation, contains('本段较一致'));
    expect(varying.measurable, isTrue);
    expect(varying.explanation, contains('波动明显'));
    expect(varying.values['周期变异系数（%）'], greaterThan(10));
  });
  test('黑屏、多人、静止及浅幅抖动不会得到有效周期等级', () {
    for (final input in [
      sequence(amplitude: 0),
      sequence(amplitude: 2),
      sequence(status: (_) => 'missing'),
      sequence(status: (_) => 'multiple')
    ]) {
      final metrics = service.measure(input).metrics;
      expect(metrics[0].measurable, isFalse);
      expect(metrics[0].explanation, contains('无法评估'));
    }
  });
  test('缺帧切断周期，不能跨多个短片段拼成完整周期', () {
    final result = service
        .measure(sequence(status: (i) => i % 12 == 0 ? 'missing' : 'valid'));
    expect(result.metrics[0].coverage, greaterThan(.8));
    expect(result.metrics[0].measurable, isFalse);
  });
  test('重复时间戳使结果不可评估，少周期不补出节奏', () {
    expect(
        service
            .measure(sequence(time: (i) => i == 10 ? 9 / 30 : i / 30))
            .metrics
            .every((m) => !m.measurable),
        isTrue);
    expect(
        service.measure(sequence(period: 1.9)).metrics[0].measurable, isFalse);
  });
  test('每项单独检查关键点，缺肩不影响膝测量', () {
    final result = service.measure(sequence(hideShoulder: true));
    expect(result.metrics[0].measurable, isTrue);
    expect(result.metrics[1].measurable, isFalse);
    expect(result.metrics[2].measurable, isTrue);
  });
  test('变帧率保留实际时间，不用帧序号推算周期', () {
    final original = sequence();
    final dropped =
        RunningPoseSequence(duration: 10, detectorVersion: 'test', frames: [
      for (var i = 0; i < original.frames.length; i++)
        if (i % 4 != 0) original.frames[i]
    ]);
    expect(service.measure(dropped).metrics[0].values['周期中位时长（秒）'],
        closeTo(.8, .08));
  });
  test('分项报告需拍摄确认，只保留六十帧且可往返读取', () {
    final source = sequence(), measurements = service.measure(sequence());
    final assessment = RunningFormAssessmentService();
    expect(
        () => assessment.assess(
            id: 'test',
            now: DateTime(2026),
            sequence: source,
            measurements: measurements,
            captureConfirmed: false),
        throwsStateError);
    final report = assessment.assess(
        id: 'test',
        now: DateTime(2026),
        sequence: source,
        measurements: measurements,
        captureConfirmed: true);
    expect(report.frames.length, lessThanOrEqualTo(60));
    expect(
        RunningFormReport.fromJson(report.toJson()).toJson(), report.toJson());
    expect(report.toJson().containsKey('score'), isFalse);
  });
}
