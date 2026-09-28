import '../../../plugins/core/plugin_ref.dart';
import 'running_metrics_service.dart';
import 'running_pose_models.dart';

class RunningFormReport {
  RunningFormReport(
      {required this.id,
      required this.createdAt,
      required this.duration,
      required this.side,
      required this.detectorVersion,
      required this.ruleVersion,
      required this.captureConfirmed,
      required List<RunningMetric> metrics,
      required List<RunningPoseFrame> frames,
      required List<PluginRef> pluginRefs})
      : metrics = List.unmodifiable(metrics),
        frames = List.unmodifiable(frames),
        pluginRefs = List.unmodifiable(pluginRefs);
  final String id, side, detectorVersion, ruleVersion;
  final DateTime createdAt;
  final double duration;
  final bool captureConfirmed;
  final List<RunningMetric> metrics;
  final List<RunningPoseFrame> frames;
  final List<PluginRef> pluginRefs;
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'duration': duration,
        'side': side,
        'detectorVersion': detectorVersion,
        'ruleVersion': ruleVersion,
        'captureConfirmed': captureConfirmed,
        'metrics': metrics.map((m) => m.toJson()).toList(),
        'frames': frames.map((f) => f.toJson()).toList(),
        'pluginRefs': pluginRefs.map((r) => r.toJson()).toList()
      };
  factory RunningFormReport.fromJson(Map<String, dynamic> j) {
    final frames = (j['frames'] as List)
        .map((f) =>
            RunningPoseFrame.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();
    final metrics = (j['metrics'] as List)
        .map((m) => RunningMetric.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
    final duration = (j['duration'] as num).toDouble();
    if (frames.length > 60 ||
        metrics.length != 3 ||
        duration < 5 ||
        duration > 20 ||
        !duration.isFinite ||
        frames.any((f) =>
            !f.seconds.isFinite ||
            f.seconds < 0 ||
            f.seconds > duration + .1 ||
            !f.width.isFinite ||
            f.width <= 0 ||
            !f.height.isFinite ||
            f.height <= 0) ||
        metrics.any((m) =>
            !m.coverage.isFinite ||
            m.coverage < 0 ||
            m.coverage > 1 ||
            !m.confidence.isFinite ||
            m.confidence < 0 ||
            m.confidence > 1 ||
            m.values.values.any((v) => !v.isFinite) ||
            m.evidence.any((v) => !v.isFinite || v < 0 || v > duration + .1))) {
      throw const FormatException('跑姿报告结构或数值无效');
    }
    return RunningFormReport(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        duration: duration,
        side: j['side'] as String,
        detectorVersion: j['detectorVersion'] as String,
        ruleVersion: j['ruleVersion'] as String,
        captureConfirmed: j['captureConfirmed'] == true,
        metrics: metrics,
        frames: frames,
        pluginRefs: PluginRef.parseOptionalList(j['pluginRefs']) ?? []);
  }
}

class RunningFormAssessmentService {
  static const version = '1.0.0';
  RunningFormReport assess(
      {required String id,
      required DateTime now,
      required RunningPoseSequence sequence,
      required RunningMeasurements measurements,
      required bool captureConfirmed}) {
    if (!captureConfirmed) throw StateError('请先确认固定机位、单人侧面、全身清晰、平地或跑步机及常速视频');
    // 证据最多占三十帧，剩余名额覆盖全段，避免高频周期挤掉视频尾部。
    final selected = <double, RunningPoseFrame>{};
    final times =
        measurements.metrics.expand((m) => m.evidence).toSet().toList()..sort();
    final count = times.length > 30 ? 30 : times.length;
    for (var i = 0; i < count; i++) {
      final time = times[
          count <= 1 ? 0 : ((times.length - 1) * i / (count - 1)).round()];
      for (final f in sequence.frames) {
        if (f.seconds == time) {
          selected[time] = f;
          break;
        }
      }
    }
    final available = sequence.frames;
    final remaining = 60 - selected.length;
    for (var i = 0; i < remaining && available.isNotEmpty; i++) {
      final index = remaining <= 1
          ? 0
          : ((available.length - 1) * i / (remaining - 1)).round();
      selected[available[index].seconds] = available[index];
    }
    final frames = selected.values.toList()
      ..sort((a, b) => a.seconds.compareTo(b.seconds));
    return RunningFormReport(
        id: id,
        createdAt: now,
        duration: sequence.duration,
        side: measurements.side,
        detectorVersion: sequence.detectorVersion,
        ruleVersion: version,
        captureConfirmed: true,
        metrics: measurements.metrics,
        frames: frames,
        pluginRefs: [PluginRef(id: 'feature.motion_check', version: '1.0.0')]);
  }
}
