import '../../features/motion_check/running/running_metrics_service.dart';
import '../../features/motion_check/running/running_form_assessment_service.dart';
import '../../features/motion_check/running/running_video_pose_gateway.dart';
import '../core/plugin_core.dart';

class MotionCheckPlugin extends TrainMatePlugin {
  static const id = 'feature.motion_check';
  static const extract = '$id.running_pose_extract';
  static const measure = '$id.running_metrics';
  static const assess = '$id.running_review';
  MotionCheckPlugin({RunningVideoPoseGateway Function()? gatewayFactory})
      : _gatewayFactory = gatewayFactory ?? PlatformRunningVideoPoseGateway.new;
  final RunningVideoPoseGateway Function() _gatewayFactory;
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: id,
          type: PluginType.feature,
          version: '1.0.0',
          name: '动作分析',
          description: '照片动作分析与验收中的本机跑姿视频工具链',
          capabilities: [
            extract,
            measure,
            assess
          ],
          skills: [
            for (final entry in const {
              extract: ('跑姿关键点提取', '视频解码、单人连续关键点与真实时间戳'),
              measure: ('跑姿时序测量', '按清晰侧测量周期、躯干角度和膝关节活动'),
              assess: ('跑姿分项评估', '生成分项解释、证据时间点和规则来源，不输出综合分数'),
            }.entries)
              PluginSkillBinding(
                  ownerPluginId: id,
                  id: entry.key,
                  name: entry.value.$1,
                  version: '1.0.0',
                  execution: SkillExecution.local,
                  capabilityId: entry.key,
                  purpose: '${entry.value.$2}。真实视频验收中，仅验收发行可运行。',
                  inputs: '经用户确认拍摄条件的 5–20 秒侧面跑步视频或其本机关键点序列。',
                  outputs: '可复核的关键点、分项指标或待手动保存的报告。',
                  fallback: '证据不足时无法评估；不上传视频、不自动调整计划。'),
          ]);
  @override
  Future<void> initialize(PluginContext context) async {
    final gateway = _gatewayFactory();
    context.registerCapability(extract, gateway);
    context.registerCapability(measure, RunningMetricsService());
    context.registerCapability(assess, RunningFormAssessmentService());
    context.addCleanup(gateway.dispose);
  }
}
