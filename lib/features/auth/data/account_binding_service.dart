import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/local_storage_service.dart';

final accountBindingServiceProvider = Provider<AccountBindingService>(
  (Ref ref) => AccountBindingService(ref.watch(localStorageServiceProvider)),
);

class AccountBindingService {
  static const String installationIdKey = 'trainflow.installation_id.v1';
  static const String accountBindingKey = 'trainflow.account_binding.v1';

  final LocalStorageService _storage;

  AccountBindingService(this._storage);

  String get installationId {
    final String? stored =
        _storage.readJson(installationIdKey)?['value'] as String?;
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final String generated = _generateUuidV4();
    _storage.saveJson(installationIdKey, <String, dynamic>{'value': generated});
    return generated;
  }

  String? get boundUserId =>
      _storage.readJson(accountBindingKey)?['userId'] as String?;

  bool requiresConfirmation(String userId) {
    final String? current = boundUserId;
    return current != null && current != userId;
  }

  void bind(String userId) {
    _storage.saveJson(accountBindingKey, <String, dynamic>{
      'userId': userId,
      'boundAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> clearBusinessDataAndBind(String userId) {
    final DateTime boundAt = DateTime.now();
    return _storage.replaceBusinessDataAtomically(
      preservedKeys: const <String>{installationIdKey},
      replacementDocuments: <String, Map<String, dynamic>>{
        accountBindingKey: <String, dynamic>{
          'userId': userId,
          'boundAt': boundAt.toIso8601String(),
        },
      },
    );
  }

  String _generateUuidV4() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final String hex = bytes
        .map((int value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
