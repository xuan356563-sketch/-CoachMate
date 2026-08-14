import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/repositories/pre_exercise_clearance_repository.dart';

void main() {
  test('加密筛查记录类型损坏时清空并按未完成处理', () async {
    final String corrupted = jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'accountId': 'user-a',
      'installationId': 'install-a',
      'clearance': <String, dynamic>{
        'status': 'self_cleared',
        'completedAt': '2026-07-17T00:00:00.000',
        'validUntil': '2027-07-17T00:00:00.000',
        'sourceUrl': PreExerciseClearance.officialSourceUrl,
        'sourceLabel': PreExerciseClearance.officialSourceLabel,
        'policyVersion': PreExerciseClearance.currentPolicyVersion,
        'currentInjuryOrRestriction': '不是布尔值',
      },
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SecurePreExerciseClearanceRepository.storageKey: corrupted,
    });
    const FlutterSecureStorage storage = FlutterSecureStorage();
    const SecurePreExerciseClearanceRepository repository =
        SecurePreExerciseClearanceRepository(storage);

    final PreExerciseClearance result = await repository.read(
      accountId: 'user-a',
      installationId: 'install-a',
    );

    expect(result.status, PreExerciseClearanceStatus.notCompleted);
    expect(
      await storage.read(
        key: SecurePreExerciseClearanceRepository.storageKey,
      ),
      isNull,
    );
  });
}
