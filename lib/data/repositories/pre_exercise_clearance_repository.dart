import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/pre_exercise_clearance.dart';

final preExerciseClearanceRepositoryProvider =
    Provider<PreExerciseClearanceRepository>(
  (Ref ref) => SecurePreExerciseClearanceRepository(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
        sharedPreferencesName: 'TrainMateHealthClearance',
        preferencesKeyPrefix: 'trainmate_',
      ),
      iOptions: IOSOptions(
        accountName: 'com.trainmate.pre-exercise-clearance',
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
      mOptions: MacOsOptions(
        accountName: 'com.trainmate.pre-exercise-clearance',
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
    ),
  ),
);

abstract class PreExerciseClearanceRepository {
  Future<PreExerciseClearance> read({
    required String accountId,
    required String installationId,
  });

  Future<void> save({
    required String accountId,
    required String installationId,
    required PreExerciseClearance clearance,
  });

  Future<void> clear();
}

class SecurePreExerciseClearanceRepository
    implements PreExerciseClearanceRepository {
  static const String storageKey = 'trainflow.pre_exercise_clearance.v1';

  final FlutterSecureStorage _storage;

  const SecurePreExerciseClearanceRepository(this._storage);

  @override
  Future<PreExerciseClearance> read({
    required String accountId,
    required String installationId,
  }) async {
    final String? raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) {
      return const PreExerciseClearance.notCompleted();
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['accountId'] != accountId ||
          decoded['installationId'] != installationId) {
        await clear();
        return const PreExerciseClearance.notCompleted();
      }
      final Object? clearanceJson = decoded['clearance'];
      if (clearanceJson is! Map<String, dynamic>) {
        await clear();
        return const PreExerciseClearance.notCompleted();
      }
      return PreExerciseClearance.fromJson(clearanceJson);
    } on Object {
      // 安全状态损坏时宁可清空并重新筛查，不能继续沿用无法验证的许可。
      await clear();
      return const PreExerciseClearance.notCompleted();
    }
  }

  @override
  Future<void> save({
    required String accountId,
    required String installationId,
    required PreExerciseClearance clearance,
  }) {
    return _storage.write(
      key: storageKey,
      value: jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'accountId': accountId,
        'installationId': installationId,
        'clearance': clearance.toJson(),
      }),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
}
