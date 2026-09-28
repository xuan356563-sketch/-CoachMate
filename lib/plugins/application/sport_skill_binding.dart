import '../../features/ai_center/data/training_prescription_api_models.dart';
import '../core/plugin_descriptor.dart';
import '../core/plugin_skill_binding.dart';

/// 消费插件声明和既有能力协商，不改变网络请求或 AiSkillRef 格式。
String? cloudSportSkillBlocker(PluginDescriptor descriptor,
    TrainingPrescriptionCapabilities capabilities) {
  final bindings =
      descriptor.skills.where((s) => s.execution == SkillExecution.cloud);
  if (bindings.isEmpty) return '${descriptor.name}未声明云端计划技能，请使用本地规则计划。';
  if (!capabilities.enabled) return '云端计划服务当前不可用，请使用本地规则计划。';
  for (final binding in bindings) {
    final matches =
        capabilities.skills.where((s) => s.id == binding.id).toList();
    if (matches.length != 1) return '服务端未提供唯一的${binding.name}技能，请刷新能力后重试。';
    final skill = matches.single;
    if (!binding.acceptsVersion(skill.version)) {
      return '${binding.name}版本不兼容（需要 ${binding.version}，当前 ${skill.version}），请更新应用或使用本地规则计划。';
    }
    if (!skill.sports.contains(binding.sportCode)) {
      return '${binding.name}没有覆盖当前运动，请使用本地规则计划。';
    }
    if (binding.fragmentKey != null &&
        !skill.fragmentSha256.containsKey(binding.fragmentKey)) {
      return '${binding.name}缺少已声明的专项片段，请刷新能力或使用本地规则计划。';
    }
  }
  return null;
}
