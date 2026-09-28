import '../../plugins/core/plugin_ref.dart';

/// 本地内容来源，不参与云端请求摘要。
class ResourceRef {
  ResourceRef(
      {required this.id, required this.version, required this.fingerprint}) {
    PluginRef.validateId(id);
    PluginRef.validateVersion(version);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('资源内容指纹无效');
    }
  }
  final String id, version, fingerprint;
  factory ResourceRef.fromJson(Map<String, dynamic> json) => ResourceRef(
      id: json['id'] as String,
      version: json['version'] as String,
      fingerprint: json['fingerprint'] as String);
  Map<String, dynamic> toJson() =>
      {'id': id, 'version': version, 'fingerprint': fingerprint};
  @override
  bool operator ==(Object other) =>
      other is ResourceRef &&
      id == other.id &&
      version == other.version &&
      fingerprint == other.fingerprint;
  @override
  int get hashCode => Object.hash(id, version, fingerprint);
}
