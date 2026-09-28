import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import 'running_video_controller.dart';
import 'running_report_view.dart';

class RunningVideoPage extends ConsumerStatefulWidget {
  const RunningVideoPage({super.key});
  @override
  ConsumerState<RunningVideoPage> createState() => _RunningVideoPageState();
}

class _RunningVideoPageState extends ConsumerState<RunningVideoPage> {
  bool _confirmed = false;
  RunningVideoController? _controller;
  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.cancel(notify: false).catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(runningVideoControllerProvider);
    final controller = ref.read(runningVideoControllerProvider.notifier);
    _controller = controller;
    final writable =
        ref.watch(pluginRuntimeProvider).isWritable('feature.motion_check');
    final preview = ref.watch(runningVideoPreviewProvider);
    return Scaffold(
        appBar: AppBar(title: const Text('跑姿视频分析 · 验收版')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              '拍摄要求：固定机位、单人侧面、全身清晰；平地或跑步机，5–20 秒常速视频。正面、坡地、跟拍和多人视频请重新拍摄。'),
          const Text('全部分析在 iPhone 本机完成，原视频不上传。分项规则仍在真实视频验收中。'),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('我确认上述拍摄条件，且视频未经变速'),
              value: _confirmed,
              onChanged: state.busy
                  ? null
                  : (value) => setState(() => _confirmed = value ?? false)),
          if (!preview) const Text('正式发行尚未开放此流程。'),
          if (!writable) const Text('动作分析功能已停用或正在切换；已保存报告仍可在核心历史读取。'),
          FilledButton(
              onPressed: state.busy || !preview || !writable
                  ? null
                  : () => controller.start(captureConfirmed: _confirmed),
              child: const Text('从相册选择跑步视频')),
          if (state.busy) ...[
            LinearProgressIndicator(
                value: state.phase == RunningVideoPhase.extracting
                    ? state.progress
                    : null),
            TextButton(
                onPressed: () => controller.cancel(), child: const Text('取消分析'))
          ],
          Text(state.message, key: const ValueKey('running-video-status')),
          if (state.report case final report?) ...[
            RunningReportView(
                key: ValueKey(report.id),
                report: report,
                loadThumbnail: controller.thumbnail),
            FilledButton(
                onPressed: state.busy || state.saved || !writable
                    ? null
                    : controller.save,
                child: Text(state.saved ? '已保存到本机' : '手动保存报告')),
            TextButton(
                onPressed: controller.cancel, child: const Text('关闭本次结果并清理视频')),
          ],
          TextButton(
              onPressed: () async {
                await controller.cancel();
                if (context.mounted) context.push('/history/running');
              },
              child: const Text('查看已保存跑姿报告')),
          TextButton(
              onPressed: writable && !state.busy ? () => _manage() : null,
              child: const Text('管理已保存报告')),
        ])));
  }

  Future<void> _manage() async {
    try {
      final reports = ref.read(runningFormReportRepositoryProvider).list();
      final id = await showDialog<String>(
          context: context,
          builder: (context) =>
              SimpleDialog(title: const Text('选择要删除的报告'), children: [
                if (reports.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16), child: Text('暂无已保存报告')),
                for (final report in reports)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, report.id),
                      child: Text(
                          '${report.createdAt.toLocal()} · ${report.side}')),
              ]));
      if (id == null || !mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('删除这份跑姿报告？'),
                  content: const Text('仅删除所选本机结构化报告，不删除相册视频或其他训练记录。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('保留')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除')),
                  ]));
      if (confirmed != true || !mounted) return;
      await ref.read(runningVideoControllerProvider.notifier).deleteReport(id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('报告已删除')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('报告操作未完成，请复核本机报告后重试。')));
      }
    }
  }
}
