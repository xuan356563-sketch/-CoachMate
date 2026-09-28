import 'plugin_ref.dart';
import 'plugin_skill_binding.dart';

enum PluginType { core, feature, sport, goal, support }

/// 运动对共享分析流程的可选引用，不形成计划生成的强依赖。
class PluginWorkflowRef {
  const PluginWorkflowRef(
      {required this.ownerPluginId,
      required this.capabilityId,
      required this.label});
  final String ownerPluginId, capabilityId, label;
}

class PluginDescriptor {
  PluginDescriptor(
      {required this.id,
      required this.type,
      required this.version,
      required this.name,
      required this.description,
      this.hostApiVersion = 1,
      Iterable<String> dependencies = const [],
      Iterable<String> capabilities = const [],
      Iterable<PluginSkillBinding> skills = const [],
      Iterable<PluginWorkflowRef> workflows = const [],
      this.defaultEnabled = true,
      this.isRequired = false})
      : dependencies = List.unmodifiable(dependencies),
        skills = List.unmodifiable(skills),
        workflows = List.unmodifiable(workflows),
        capabilities = List.unmodifiable(capabilities) {
    PluginRef.validateId(id);
    PluginRef.validateVersion(version);
    final workflowIds = <String>{};
    for (final workflow in this.workflows) {
      PluginRef.validateId(workflow.ownerPluginId);
      PluginRef.validateId(workflow.capabilityId);
      if (!workflowIds.add(workflow.capabilityId) ||
          workflow.label.trim().isEmpty) {
        throw const FormatException('分析流程引用重复或名称为空');
      }
    }
    final skillIds = <String>{};
    for (final skill in this.skills) {
      if (skill.ownerPluginId != id || !skillIds.add(skill.id)) {
        throw FormatException('插件 $id 的技能归属不一致或标识重复');
      }
      if (skill.execution == SkillExecution.local &&
          (!this.capabilities.contains(skill.capabilityId) ||
              skill.version != version)) {
        throw FormatException('插件 $id 的本地技能必须声明同版本的真实能力');
      }
    }
    if (name.trim().isEmpty || description.trim().isEmpty) {
      throw const FormatException('插件名称和描述不能为空');
    }
    for (final value in [...this.dependencies, ...this.capabilities]) {
      PluginRef.validateId(value);
    }
    if (this.dependencies.toSet().length != this.dependencies.length ||
        this.capabilities.toSet().length != this.capabilities.length) {
      throw FormatException('插件 $id 的依赖或能力声明重复');
    }
  }

  final String id;
  final PluginType type;
  final String version;
  final int hostApiVersion;
  final List<String> dependencies;
  final List<String> capabilities;
  final List<PluginSkillBinding> skills;
  final List<PluginWorkflowRef> workflows;
  final bool defaultEnabled;
  final bool isRequired;
  final String name;
  final String description;

  PluginRef get ref => PluginRef(id: id, version: version);
}
