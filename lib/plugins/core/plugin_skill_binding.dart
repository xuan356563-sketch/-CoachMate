import 'plugin_ref.dart';

enum SkillExecution { local, cloud }

/// 插件对既有技能的使用声明；不加载代码，也不授予网络或数据权限。
class PluginSkillBinding {
  PluginSkillBinding({
    required this.ownerPluginId,
    required this.id,
    required this.name,
    required this.version,
    required this.execution,
    required this.purpose,
    required this.inputs,
    required this.outputs,
    required this.fallback,
    this.capabilityId,
    this.sportCode,
    this.fragmentKey,
  }) {
    PluginRef.validateId(ownerPluginId);
    PluginRef.validateId(id);
    if ([name, purpose, inputs, outputs, fallback]
        .any((s) => s.trim().isEmpty)) {
      throw const FormatException('技能名称、用途、输入输出和回退说明不能为空');
    }
    if (execution == SkillExecution.local) {
      PluginRef.validateVersion(version);
      if (capabilityId == null || sportCode != null || fragmentKey != null) {
        throw const FormatException('本地技能必须绑定本地能力，不能声明云端运动片段');
      }
      PluginRef.validateId(capabilityId!);
    } else {
      if (!RegExp(r'^[1-9]\d*\.x$').hasMatch(version) ||
          sportCode == null ||
          capabilityId != null) {
        throw const FormatException('云端技能必须声明兼容主版本和运动代码');
      }
      PluginRef.validateId(sportCode!);
      if (fragmentKey != null && fragmentKey != sportCode) {
        throw const FormatException('技能专项片段必须与绑定运动一致');
      }
    }
  }

  final String ownerPluginId;
  final String id;
  final String name;

  /// 本地为发行版本；云端为兼容主版本，实际版本由既有能力协商返回。
  final String version;
  final SkillExecution execution;
  final String purpose;
  final String inputs;
  final String outputs;
  final String fallback;
  final String? capabilityId;
  final String? sportCode;
  final String? fragmentKey;

  bool acceptsVersion(String actual) {
    try {
      PluginRef.validateVersion(actual);
    } on FormatException {
      return false;
    }
    if (execution == SkillExecution.local) return version == actual;
    // 未审核的预发布版本不能因主版本相同而自动进入已有技能契约。
    return !actual.split('+').first.contains('-') &&
        actual.split('.').first == version.split('.').first;
  }
}
