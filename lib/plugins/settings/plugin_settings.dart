import '../core/plugin_descriptor.dart';

const String pluginSettingsStorageKey = 'trainflow.plugin_settings.v1';

class PluginSettings {
  const PluginSettings({
    this.version = 1,
    this.enabledOverrides = const <String, bool>{},
  });

  final int version;
  final Map<String, bool> enabledOverrides;

  factory PluginSettings.fromJson(Map<String, dynamic> json) {
    final Object? rawVersion = json['version'];
    if (rawVersion is! int || rawVersion != 1) {
      throw const FormatException('功能设置版本无法读取');
    }
    final Object? rawOverrides = json['enabledOverrides'];
    if (rawOverrides is! Map) {
      throw const FormatException('功能设置内容不完整');
    }
    final Map<String, bool> overrides = <String, bool>{};
    for (final MapEntry<Object?, Object?> entry in rawOverrides.entries) {
      if (entry.key is! String ||
          (entry.key! as String).trim().isEmpty ||
          entry.value is! bool) {
        throw const FormatException('功能设置内容格式不正确');
      }
      overrides[entry.key! as String] = entry.value! as bool;
    }
    return PluginSettings(
      enabledOverrides: Map<String, bool>.unmodifiable(overrides),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'enabledOverrides': enabledOverrides,
      };

  Set<String> enabledIds(Map<String, PluginDescriptor> descriptors) {
    return <String>{
      for (final PluginDescriptor descriptor in descriptors.values)
        if (descriptor.isRequired ||
            (enabledOverrides[descriptor.id] ?? descriptor.defaultEnabled))
          descriptor.id,
    };
  }

  PluginSettings forEnabledIds(
    Map<String, PluginDescriptor> descriptors,
    Set<String> enabledIds,
  ) {
    final Set<String> knownIds = descriptors.keys.toSet();
    final Map<String, bool> next = <String, bool>{
      for (final MapEntry<String, bool> entry in enabledOverrides.entries)
        if (!knownIds.contains(entry.key)) entry.key: entry.value,
    };
    for (final PluginDescriptor descriptor in descriptors.values) {
      if (descriptor.isRequired) continue;
      final bool enabled = enabledIds.contains(descriptor.id);
      if (enabled != descriptor.defaultEnabled) {
        next[descriptor.id] = enabled;
      }
    }
    return PluginSettings(
        enabledOverrides: Map<String, bool>.unmodifiable(next));
  }
}

class PluginSettingsReadResult {
  const PluginSettingsReadResult({
    required this.settings,
    required this.rawDocument,
    this.rawDocumentText,
    this.rawDocumentUnreadable = false,
    this.recoveryMessage,
  });

  final PluginSettings settings;
  final Map<String, dynamic>? rawDocument;
  final String? rawDocumentText;
  final bool rawDocumentUnreadable;
  final String? recoveryMessage;

  bool get needsRecovery => recoveryMessage != null;
}
