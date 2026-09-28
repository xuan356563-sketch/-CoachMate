/// 已生成内容所引用的插件身份；不用于加载代码。
class PluginRef {
  PluginRef({required this.id, required this.version}) {
    validateId(id);
    validateVersion(version);
  }

  final String id;
  final String version;

  static void validateId(String value) {
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(value)) {
      throw const FormatException('插件标识必须是稳定的小写字母、数字及分隔符');
    }
  }

  static void validateVersion(String value) {
    if (!RegExp(
            r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
        .hasMatch(value)) {
      throw const FormatException('插件版本必须采用主版本.次版本.修订版本格式');
    }
  }

  factory PluginRef.fromJson(Object? json) {
    if (json is! Map ||
        json.length != 2 ||
        json['id'] is! String ||
        json['version'] is! String) {
      throw const FormatException('插件来源必须且只能包含字符串 id 和 version');
    }
    return PluginRef(
        id: json['id'] as String, version: json['version'] as String);
  }

  /// 缺失保持为 null，空列表保持为空，避免改变旧计划来源语义。
  static List<PluginRef>? parseOptionalList(Object? json) {
    if (json == null) return null;
    if (json is! List) throw const FormatException('插件来源必须是列表');
    final ids = <String>{};
    final refs = <PluginRef>[];
    for (final entry in json) {
      final ref = PluginRef.fromJson(entry);
      if (!ids.add(ref.id)) throw FormatException('插件来源标识重复：${ref.id}');
      refs.add(ref);
    }
    return List.unmodifiable(refs);
  }

  Map<String, Object> toJson() => {'id': id, 'version': version};

  @override
  bool operator ==(Object other) =>
      other is PluginRef && id == other.id && version == other.version;
  @override
  int get hashCode => Object.hash(id, version);
}
