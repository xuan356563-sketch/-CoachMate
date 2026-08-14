import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/first_run_models.dart';

abstract interface class FirstRunDraftStore {
  Future<FirstRunDraft?> load();

  Future<void> save(FirstRunDraft draft);

  Future<void> clear();
}

class SecureFirstRunDraftStore implements FirstRunDraftStore {
  SecureFirstRunDraftStore({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now;

  static const String _key = 'trainmate.first_run_onboarding.v2';

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  @override
  Future<FirstRunDraft?> load() async {
    final String? encoded = await _storage.read(key: _key);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final FirstRunDraft draft = FirstRunDraft.fromJson(
        Map<String, Object?>.from(jsonDecode(encoded) as Map),
      );
      if (draft.isExpiredAt(_now())) {
        await clear();
        return null;
      }
      return draft;
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(FirstRunDraft draft) {
    return _storage.write(key: _key, value: jsonEncode(draft.toJson()));
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
