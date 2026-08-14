import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/profile_privacy_parser.dart';

export '../application/profile_privacy_parser.dart' show ProfileSensitiveDraft;

abstract interface class SensitiveProfileDraftStore {
  Future<ProfileSensitiveDraft?> load();

  Future<void> save(ProfileSensitiveDraft draft);

  Future<void> clear();
}

final sensitiveProfileDraftStoreProvider = Provider<SensitiveProfileDraftStore>(
  (Ref ref) => SecureSensitiveProfileDraftStore(),
);

/// 登录前敏感资料的短期加密草稿。
///
/// 只保存本地结构化值，不保存音频、完整对话或联系方式；七天未继续建档会自动清除。
class SecureSensitiveProfileDraftStore implements SensitiveProfileDraftStore {
  SecureSensitiveProfileDraftStore({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now;

  static const String _key = 'trainmate.first_run_sensitive_profile.v1';
  static const Duration _retention = Duration(days: 7);

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  @override
  Future<ProfileSensitiveDraft?> load() async {
    final String? encoded = await _storage.read(key: _key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final Map<String, dynamic> payload =
          Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      final DateTime? updatedAt =
          DateTime.tryParse(payload['updated_at'] as String? ?? '');
      if (updatedAt == null ||
          _now().toUtc().difference(updatedAt.toUtc()) > _retention) {
        await clear();
        return null;
      }
      final Object? rawDraft = payload['draft'];
      if (rawDraft is! Map) {
        await clear();
        return null;
      }
      return ProfileSensitiveDraft.fromJson(
        Map<String, dynamic>.from(rawDraft),
      );
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(ProfileSensitiveDraft draft) {
    if (draft.isEmpty) return clear();
    return _storage.write(
      key: _key,
      value: jsonEncode(<String, dynamic>{
        'schema_version': 1,
        'updated_at': _now().toUtc().toIso8601String(),
        'draft': draft.toJson(),
      }),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
