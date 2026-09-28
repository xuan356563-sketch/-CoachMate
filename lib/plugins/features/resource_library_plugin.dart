import '../../features/resource_library/assessment_record.dart';
import '../../features/resource_library/resource_catalog.dart';
import '../../features/resource_library/resource_plan_preview.dart';
import '../core/plugin_core.dart';

class ResourceLibraryPlugin extends TrainMatePlugin {
  static const id = 'feature.resource_library';
  static const catalog = '$id.catalog';
  static const assessment = '$id.assessment';
  static const preview = '$id.preview';
  @override
  PluginDescriptor get descriptor => PluginDescriptor(
          id: id,
          name: '运动资源库',
          type: PluginType.feature,
          version: '1.0.0',
          description: '按运动共享基础评估指引和现有计划策略',
          capabilities: [
            catalog,
            assessment,
            preview
          ],
          skills: [
            for (final e in const {
              catalog: '资源检索',
              assessment: '评估记录',
              preview: '模板预览'
            }.entries)
              PluginSkillBinding(
                  ownerPluginId: id,
                  id: e.key,
                  name: e.value,
                  version: '1.0.0',
                  execution: SkillExecution.local,
                  capabilityId: e.key,
                  purpose: '${e.value}，使用已审核内置内容。',
                  inputs: '资源标识及用户确认的本机上下文。',
                  outputs: '带来源的资源、待保存事实记录或候选计划。',
                  fallback: '内容未审核、来源变化或条件不足时说明原因，不自动提交。')
          ]);
  @override
  Future<void> initialize(PluginContext context) async {
    context.registerCapability(
        catalog, ResourceCatalog(checkActive: context.checkActive));
    context.registerCapability(
        assessment, AssessmentService(checkActive: context.checkActive));
    context.registerCapability(
        preview, ResourcePlanPreview(checkActive: context.checkActive));
  }
}
