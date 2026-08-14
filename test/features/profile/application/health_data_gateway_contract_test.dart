import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_stub.dart';

void main() {
  test('每日活动摘要 payload 保留自然日、四项活动、三个目标和逐字段可用性', () {
    final HealthDailyActivitySummaryPayload payload =
        HealthDailyActivitySummaryPayload.fromMap(<String, Object?>{
      'localDate': '2026-07-15',
      'timeZoneName': 'Asia/Shanghai',
      'timeZoneOffsetMinutes': 480,
      'steps': 8123,
      'activeEnergyKcal': 456.5,
      'activeEnergyGoalKcal': 500.0,
      'exerciseMinutes': 38,
      'exerciseGoalMinutes': 30,
      'standHours': 11,
      'standGoalHours': 12,
      'availableFields': <Object?>[
        'steps',
        'activeEnergyKcal',
        'activeEnergyGoalKcal',
        'exerciseMinutes',
        'exerciseGoalMinutes',
        'standHours',
        'standGoalHours',
      ],
      'syncedAt': '2026-07-15T12:34:56.000Z',
    });

    expect(payload.localDate, '2026-07-15');
    expect(payload.timeZoneName, 'Asia/Shanghai');
    expect(payload.timeZoneOffsetMinutes, 480);
    expect(payload.steps, 8123);
    expect(payload.activeEnergyKcal, 456.5);
    expect(payload.activeEnergyGoalKcal, 500.0);
    expect(payload.exerciseMinutes, 38);
    expect(payload.exerciseGoalMinutes, 30);
    expect(payload.standHours, 11);
    expect(payload.standGoalHours, 12);
    expect(
      payload.availableFields,
      <String>{
        'steps',
        'activeEnergyKcal',
        'activeEnergyGoalKcal',
        'exerciseMinutes',
        'exerciseGoalMinutes',
        'standHours',
        'standGoalHours',
      },
    );
    expect(payload.syncedAt, DateTime.utc(2026, 7, 15, 12, 34, 56));
    expect(
      HealthDailyActivitySummaryPayload.fromMap(payload.toMap()).toMap(),
      payload.toMap(),
    );
    expect(payload.toMap(), isNot(contains('stepGoal')));
  });

  test('HealthSyncBatch 可以无损解析原生批次并序列化', () {
    final HealthSyncBatch batch = HealthSyncBatch.fromMap(<String, Object?>{
      'batchId': 'batch-1',
      'athleteId': 'athlete-a',
      'objectType': 'workout',
      'queryVersion': 1,
      'upserts': <Object?>[
        <String, Object?>{'uuid': 'workout-1', 'kind': 'workout'},
      ],
      'deletedExternalIds': <Object?>['workout-deleted'],
      'nextAnchor': 'anchor-2',
      'createdAt': '2026-07-15T12:00:00.000Z',
      'requiresAcknowledgement': true,
      'coverageStart': '2026-06-15T12:00:00.000Z',
      'coverageEnd': '2026-07-15T12:00:00.000Z',
    });

    expect(batch.batchId, 'batch-1');
    expect(batch.athleteId, 'athlete-a');
    expect(batch.upserts.single['uuid'], 'workout-1');
    expect(batch.deletedExternalIds, <String>['workout-deleted']);
    expect(batch.requiresAcknowledgement, isTrue);
    expect(batch.coverageStart, DateTime.utc(2026, 6, 15, 12));
    expect(batch.coverageEnd, DateTime.utc(2026, 7, 15, 12));
    expect(HealthSyncBatch.fromMap(batch.toMap()), batch);
  });

  test('未知原生授权状态保持不可判定，不能伪装成已授权', () {
    const HealthAuthorizationResult result = HealthAuthorizationResult(
      stage: HealthPermissionStage.analysis,
      state: HealthAuthorizationState.undetermined,
      requestCompleted: true,
    );

    expect(result.canClaimReadAuthorization, isFalse);
  });

  test('Web 与非 iOS 桩明确返回 HealthKit 不可用且不生成数据', () async {
    const UnsupportedHealthDataGateway gateway = UnsupportedHealthDataGateway();

    final HealthAuthorizationResult authorization =
        await gateway.requestPermission(
      stage: HealthPermissionStage.workout,
      athleteId: 'athlete-a',
    );
    final HealthForegroundSyncResult foreground = await gateway.syncForeground(
      stage: HealthPermissionStage.workout,
      athleteId: 'athlete-a',
      start: DateTime.utc(2026, 7, 14),
      end: DateTime.utc(2026, 7, 15),
    );
    final List<HealthSyncBatch> background =
        await gateway.drainPendingBackgroundBatches();
    final List<HealthDailyActivitySummaryPayload> dailySummaries =
        await gateway.fetchDailyActivitySummaries(
      start: DateTime.utc(2026, 7, 14),
      end: DateTime.utc(2026, 7, 15),
    );
    await gateway.clearAthleteData(athleteId: 'athlete-a');

    expect(gateway.isSupported, isFalse);
    expect(authorization.state, HealthAuthorizationState.unavailable);
    expect(authorization.requestCompleted, isFalse);
    expect(foreground.snapshots, isEmpty);
    expect(foreground.batches, isEmpty);
    expect(background, isEmpty);
    expect(dailySummaries, isEmpty);
  });

  test('本地健康文件保护只接受有限数量的绝对路径', () {
    expect(
      () => validateHealthLocalFilePaths(<String>[
        '/var/mobile/Containers/Data/Application/app/trainflow.db',
        '/var/mobile/Containers/Data/Application/app/trainflow.db-wal',
        '/var/mobile/Containers/Data/Application/app/trainflow.db-shm',
      ]),
      returnsNormally,
    );
    expect(
      () => validateHealthLocalFilePaths(const <String>[]),
      throwsArgumentError,
    );
    expect(
      () => validateHealthLocalFilePaths(<String>['trainflow.db']),
      throwsArgumentError,
    );
    expect(
      () => validateHealthLocalFilePaths(<String>['/tmp/invalid\u0000path']),
      throwsArgumentError,
    );
    expect(
      () => validateHealthLocalFilePaths(
        List<String>.generate(17, (int index) => '/tmp/file-$index'),
      ),
      throwsArgumentError,
    );
  });
}
