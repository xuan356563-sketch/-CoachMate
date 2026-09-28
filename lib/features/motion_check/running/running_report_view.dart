import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../data/models/motion_pose.dart';
import 'running_form_assessment_service.dart';
import 'running_pose_models.dart';

class RunningReportView extends StatefulWidget {
  const RunningReportView(
      {super.key, required this.report, this.loadThumbnail});
  final RunningFormReport report;
  final Future<Uint8List?> Function(double)? loadThumbnail;
  @override
  State<RunningReportView> createState() => _RunningReportViewState();
}

class _RunningReportViewState extends State<RunningReportView> {
  int _index = 0, _request = 0;
  Uint8List? _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (widget.report.frames.isEmpty || widget.loadThumbnail == null) return;
    final image =
        await widget.loadThumbnail!(widget.report.frames[_index].seconds);
    if (mounted && request == _request) setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final frame = report.frames.isEmpty ? null : report.frames[_index];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('测量侧：${report.side} · 时长 ${report.duration.toStringAsFixed(1)} 秒'),
      const Text('分项仅描述可测变化，不代表综合跑姿评分或损伤风险。'),
      for (final metric in report.metrics)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metric.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(metric.explanation),
                      for (final entry in metric.values.entries)
                        Text('${entry.key}：${entry.value.toStringAsFixed(2)}'),
                      Text(
                          '有效帧 ${(metric.coverage * 100).toStringAsFixed(0)}% · 关键点置信度 ${(metric.confidence * 100).toStringAsFixed(0)}%'),
                      if (metric.evidence.isNotEmpty)
                        Text(
                            '证据时间：${metric.evidence.take(8).map((t) => t.toStringAsFixed(2)).join('、')} 秒'),
                    ]))),
      if (frame != null) ...[
        Text(
            '关键点证据 ${frame.seconds.toStringAsFixed(2)} 秒${frame.isValid ? '' : ' · 此帧不可测'}'),
        AspectRatio(
            aspectRatio: frame.width / frame.height,
            child: ColoredBox(
                color: Colors.black12,
                child: Stack(fit: StackFit.expand, children: [
                  if (_image != null)
                    Image.memory(_image!,
                        fit: BoxFit.fill, gaplessPlayback: false),
                  CustomPaint(painter: RunningSkeletonPainter(frame)),
                ]))),
        if (report.frames.length > 1)
          Slider(
              value: _index.toDouble(),
              min: 0,
              max: (report.frames.length - 1).toDouble(),
              divisions: report.frames.length - 1,
              label: '${frame.seconds.toStringAsFixed(2)} 秒',
              onChanged: (value) {
                setState(() {
                  _index = value.round();
                  _image = null;
                  _request++;
                });
              },
              onChangeEnd: (_) => _load()),
        Text(widget.loadThumbnail == null
            ? '原视频未保存；这里仅显示保存的关键点骨架。'
            : _image == null
                ? '此证据帧仅显示骨架，原画面暂不可用。'
                : '原画面仅供本次复核，退出后清理应用临时副本。'),
      ],
      Text(
          '拍摄条件：${report.captureConfirmed ? '用户已确认固定机位、单人侧面、平整场地、全身清晰及常速' : '未确认'}'),
      Text('规则 ${report.ruleVersion} · ${report.detectorVersion}',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class RunningSkeletonPainter extends CustomPainter {
  RunningSkeletonPainter(this.frame);
  final RunningPoseFrame frame;
  static const _links = [
    (MotionPoseLandmarkType.leftShoulder, MotionPoseLandmarkType.rightShoulder),
    (MotionPoseLandmarkType.leftShoulder, MotionPoseLandmarkType.leftHip),
    (MotionPoseLandmarkType.rightShoulder, MotionPoseLandmarkType.rightHip),
    (MotionPoseLandmarkType.leftHip, MotionPoseLandmarkType.rightHip),
    (MotionPoseLandmarkType.leftHip, MotionPoseLandmarkType.leftKnee),
    (MotionPoseLandmarkType.leftKnee, MotionPoseLandmarkType.leftAnkle),
    (MotionPoseLandmarkType.rightHip, MotionPoseLandmarkType.rightKnee),
    (MotionPoseLandmarkType.rightKnee, MotionPoseLandmarkType.rightAnkle),
    (MotionPoseLandmarkType.leftShoulder, MotionPoseLandmarkType.leftElbow),
    (MotionPoseLandmarkType.leftElbow, MotionPoseLandmarkType.leftWrist),
    (MotionPoseLandmarkType.rightShoulder, MotionPoseLandmarkType.rightElbow),
    (MotionPoseLandmarkType.rightElbow, MotionPoseLandmarkType.rightWrist),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (frame.isValid ? Colors.lightGreenAccent : Colors.orange)
      ..strokeWidth = 2;
    Offset xy(MotionPoseLandmark p) =>
        Offset(p.x * size.width, p.y * size.height);
    for (final link in _links) {
      final a = frame.point(link.$1), b = frame.point(link.$2);
      if (a != null && b != null) canvas.drawLine(xy(a), xy(b), paint);
    }
    for (final type in MotionPoseLandmarkType.values) {
      final p = frame.point(type);
      if (p != null) canvas.drawCircle(xy(p), 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RunningSkeletonPainter oldDelegate) =>
      !identical(oldDelegate.frame, frame);
}
