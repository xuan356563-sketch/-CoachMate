import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:trainflow_ai/data/local/sqflite_trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainmate_structured_database_gateway.dart';
import 'package:trainflow_ai/features/profile/application/health_data_gateway_contract.dart';

void main() {
  test('路线只选择完整包住它的最窄单一训练候选', () {
    final List<Map<String, Object?>> candidates = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'wide',
        'elapsed_duration_seconds': 5400,
        'started_at_utc': '2026-07-15T07:30:00.000Z',
      },
      <String, Object?>{
        'id': 'narrow-earlier',
        'elapsed_duration_seconds': 1800,
        'started_at_utc': '2026-07-15T08:00:00.000Z',
      },
      <String, Object?>{
        'id': 'narrow-later',
        'elapsed_duration_seconds': 1800,
        'started_at_utc': '2026-07-15T08:05:00.000Z',
      },
    ];

    final Map<String, Object?>? selected =
        selectRouteWorkoutCandidate(candidates);

    expect(selected?['id'], 'narrow-later');
    expect(candidates.first['id'], 'wide');
  });

  group('结构化健康批次事务', () {
    late _MemoryStructuredDriver driver;
    late StructuredHealthSyncCoordinator coordinator;

    setUp(() {
      driver = _MemoryStructuredDriver(<String>{'athlete-a', 'athlete-b'});
      coordinator = StructuredHealthSyncCoordinator(driver);
    });

    test('同一运动员、来源和外部 UUID 重投时更新原记录而不重复插入', () async {
      await coordinator.apply(
        _workoutBatch(
          batchId: 'batch-1',
          durationSeconds: 1800,
          nextAnchor: 'anchor-1',
        ),
      );

      final HealthSyncApplyResult result = await coordinator.apply(
        _workoutBatch(
          batchId: 'batch-2',
          durationSeconds: 2400,
          nextAnchor: 'anchor-2',
        ),
      );

      expect(driver.workouts, hasLength(1));
      expect(driver.workouts.values.single['elapsed_duration_seconds'], 2400);
      expect(result.upsertCount, 1);
      expect(result.invalidatedSourceIds, hasLength(1));
      expect(
        driver.anchors['athlete-a|HKWorkoutTypeIdentifier|1'],
        'anchor-2',
      );
    });

    test('前台训练只落摘要，payload 不得保留逐秒心率或路线坐标', () async {
      final DateTime start = DateTime.utc(2026, 7, 15, 8);
      await coordinator.apply(
        HealthSyncBatch(
          batchId: 'batch-private-details',
          athleteId: 'athlete-a',
          objectType: 'foreground.analysis',
          queryVersion: 1,
          upserts: <Map<String, Object?>>[
            <String, Object?>{
              'uuid': 'workout-private',
              'kind': 'workout',
              'healthKitType': 'HKWorkoutTypeIdentifier',
              'sourceBundleId': 'com.apple.health',
              'startTime': start.millisecondsSinceEpoch,
              'endTime':
                  start.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
              'durationSeconds': 60,
              'discipline': 'roadRun',
              'timeZoneName': 'Asia/Shanghai',
              'timeZoneOffsetMinutes': 480,
              'heartRateSamples': <Map<String, Object?>>[
                <String, Object?>{
                  'startTime': start.millisecondsSinceEpoch,
                  'value': 100.0,
                },
                <String, Object?>{
                  'startTime': start
                      .add(const Duration(seconds: 5))
                      .millisecondsSinceEpoch,
                  'value': 110.0,
                },
                <String, Object?>{
                  'startTime': start
                      .add(const Duration(seconds: 20))
                      .millisecondsSinceEpoch,
                  'value': 120.0,
                },
              ],
              'routes': <Map<String, Object?>>[
                <String, Object?>{
                  'uuid': 'route-private',
                  'kind': 'workoutRoute',
                  'locations': <Map<String, Object?>>[
                    <String, Object?>{
                      'latitude': 31.123456789,
                      'longitude': 121.987654321,
                      'timestamp': start.millisecondsSinceEpoch,
                      'horizontalAccuracy': 5.0,
                    },
                  ],
                },
              ],
            },
          ],
          deletedExternalIds: const <String>[],
          nextAnchor: null,
          createdAt: DateTime.utc(2026, 7, 15, 9),
          requiresAcknowledgement: false,
        ),
      );

      final Map<String, Object?> row = driver.workouts.values.single;
      final String payloadText = row['payload_json']! as String;
      final Map<String, Object?> payload =
          Map<String, Object?>.from(jsonDecode(payloadText) as Map);
      expect(row['heart_rate_sample_count'], 3);
      expect(row['average_heart_rate'], 110.0);
      expect(row['maximum_heart_rate'], 120.0);
      expect(row['heart_rate_coverage'], closeTo(5 / 60, 0.000001));
      expect(row['route_status'], 'available');
      expect(row['route_external_uuid'], 'route-private');
      expect(payload, isNot(contains('heartRateSamples')));
      expect(payload, isNot(contains('routes')));
      expect(payloadText, isNot(contains('locations')));
      expect(payloadText, isNot(contains('31.123456789')));
      expect(payload['heartRateSummary'], isA<Map>());
      expect(payload['routeSummary'], isA<Map>());
    });

    test('HealthKit 删除会标记事实并失效分析、指标、血缘和成长证据', () async {
      await coordinator.apply(
        _workoutBatch(
          batchId: 'batch-1',
          durationSeconds: 1800,
          nextAnchor: 'anchor-1',
        ),
      );
      final String workoutId = driver.workouts.keys.single;
      driver.analysisRows['analysis-1'] = <String, Object?>{
        'id': 'analysis-1',
        'athlete_profile_id': 'athlete-a',
        'workout_id': workoutId,
        'status': 'ready',
        'invalidated_at': null,
      };
      driver.metricRows['metric-1'] = <String, Object?>{
        'id': 'metric-1',
        'athlete_profile_id': 'athlete-a',
        'status': 'ready',
        'invalidated_at': null,
      };
      driver.lineageRows['metric-1|workouts|$workoutId|input'] =
          <String, Object?>{
        'metric_aggregate_id': 'metric-1',
        'source_table': 'workouts',
        'source_id': workoutId,
        'relationship': 'input',
        'invalidated_at': null,
      };
      driver.growthEvidenceRows['evidence-1'] = <String, Object?>{
        'id': 'evidence-1',
        'athlete_profile_id': 'athlete-a',
        'source_table': 'workouts',
        'source_id': workoutId,
        'revoked_at': null,
      };

      final HealthSyncApplyResult result = await coordinator.apply(
        HealthSyncBatch(
          batchId: 'batch-delete',
          athleteId: 'athlete-a',
          objectType: 'HKWorkoutTypeIdentifier',
          queryVersion: 1,
          upserts: const <Map<String, Object?>>[],
          deletedExternalIds: const <String>['workout-uuid'],
          nextAnchor: 'anchor-3',
          createdAt: DateTime.utc(2026, 7, 16, 2),
          requiresAcknowledgement: true,
        ),
      );

      expect(result.deletedCount, 1);
      expect(result.invalidatedSources.single.sourceType, 'workouts');
      expect(result.invalidatedSources.single.localDate, '2026-07-15');
      expect(driver.workouts[workoutId]!['source_deleted_at'], isNotNull);
      expect(driver.analysisRows['analysis-1']!['status'], 'invalidated');
      expect(driver.metricRows['metric-1']!['status'], 'invalidated');
      expect(
        driver.lineageRows.values.single['invalidated_at'],
        isNotNull,
      );
      expect(
        driver.growthEvidenceRows['evidence-1']!['revoked_at'],
        isNotNull,
      );
    });

    test('删除历史离散健康样本时返回原始本地日期供指标重算', () async {
      final DateTime observedAt = DateTime.utc(2026, 5, 31, 16);
      await coordinator.apply(
        HealthSyncBatch(
          batchId: 'observation-upsert',
          athleteId: 'athlete-a',
          objectType: 'HKQuantityTypeIdentifierRestingHeartRate',
          queryVersion: 1,
          upserts: <Map<String, Object?>>[
            <String, Object?>{
              'uuid': 'resting-heart-rate-old',
              'kind': 'observation',
              'healthKitType': 'HKQuantityTypeIdentifierRestingHeartRate',
              'sourceBundleId': 'com.apple.health',
              'startTime': observedAt.millisecondsSinceEpoch,
              'endTime': observedAt.millisecondsSinceEpoch,
              'timeZoneName': 'Asia/Shanghai',
              'timeZoneOffsetMinutes': 480,
              'value': 52.0,
              'unit': 'count/min',
            },
          ],
          deletedExternalIds: const <String>[],
          nextAnchor: 'observation-anchor-1',
          createdAt: DateTime.utc(2026, 6, 1),
          requiresAcknowledgement: true,
        ),
      );

      final HealthSyncApplyResult result = await coordinator.apply(
        HealthSyncBatch(
          batchId: 'observation-delete',
          athleteId: 'athlete-a',
          objectType: 'HKQuantityTypeIdentifierRestingHeartRate',
          queryVersion: 1,
          upserts: const <Map<String, Object?>>[],
          deletedExternalIds: const <String>['resting-heart-rate-old'],
          nextAnchor: 'observation-anchor-2',
          createdAt: DateTime.utc(2026, 7, 15),
          requiresAcknowledgement: true,
        ),
      );

      expect(result.invalidatedSources, hasLength(1));
      expect(
          result.invalidatedSources.single.sourceType, 'health_observations');
      expect(result.invalidatedSources.single.localDate, '2026-06-01');
      expect(result.invalidatedSources.single.timeZoneName, 'Asia/Shanghai');
    });

    test('删除批次重投仍返回墓碑事实的原周期，供失败后的指标重算', () async {
      await coordinator.apply(
        _workoutBatch(
          batchId: 'delete-source',
          externalUuid: 'workout-external-1',
          durationSeconds: 1800,
          nextAnchor: 'delete-source-anchor',
        ),
      );
      final HealthSyncBatch deletion = HealthSyncBatch(
        batchId: 'delete-retry-1',
        athleteId: 'athlete-a',
        objectType: 'HKWorkoutTypeIdentifier',
        queryVersion: 1,
        upserts: const <Map<String, Object?>>[],
        deletedExternalIds: const <String>['workout-external-1'],
        nextAnchor: 'delete-anchor-1',
        createdAt: DateTime.utc(2026, 7, 16),
        requiresAcknowledgement: true,
      );
      final HealthSyncApplyResult first = await coordinator.apply(deletion);
      final HealthSyncApplyResult retry = await coordinator.apply(
        HealthSyncBatch(
          batchId: 'delete-retry-2',
          athleteId: deletion.athleteId,
          objectType: deletion.objectType,
          queryVersion: deletion.queryVersion,
          upserts: deletion.upserts,
          deletedExternalIds: deletion.deletedExternalIds,
          nextAnchor: 'delete-anchor-2',
          createdAt: DateTime.utc(2026, 7, 16, 0, 1),
          requiresAcknowledgement: true,
        ),
      );

      expect(first.invalidatedSources.single.localDate, '2026-07-15');
      expect(retry.invalidatedSources.single.sourceType, 'workouts');
      expect(retry.invalidatedSources.single.localDate, '2026-07-15');
      expect(retry.invalidatedSources.single.timeZoneName, 'Asia/Shanghai');
    });

    test('前台回填范围与事实在同一事务中写入覆盖证明', () async {
      final HealthSyncBatch base = _workoutBatch(
        batchId: 'foreground-coverage',
        durationSeconds: 1800,
        nextAnchor: '',
      );
      await coordinator.apply(
        HealthSyncBatch(
          batchId: base.batchId,
          athleteId: base.athleteId,
          objectType: 'foreground.workout',
          queryVersion: base.queryVersion,
          upserts: base.upserts,
          deletedExternalIds: base.deletedExternalIds,
          nextAnchor: null,
          createdAt: base.createdAt,
          requiresAcknowledgement: false,
          coverageStart: DateTime.utc(2026, 6, 15),
          coverageEnd: DateTime.utc(2026, 7, 15),
        ),
        syncMode: 'foreground',
      );

      final String? payload =
          driver.anchors['athlete-a|coverage:foreground.workout|1'];
      expect(payload, isNotNull);
      expect(jsonDecode(payload!)['start'], '2026-06-15T00:00:00.000Z');
      expect(jsonDecode(payload)['end'], '2026-07-15T00:00:00.000Z');
    });

    test('后续短范围同步不会覆盖首次完整回填范围', () async {
      final HealthSyncBatch base = _workoutBatch(
        batchId: 'foreground-initial',
        durationSeconds: 1800,
        nextAnchor: '',
      );
      Future<void> applyCoverage({
        required String batchId,
        required DateTime start,
        required DateTime end,
      }) =>
          coordinator
              .apply(
                HealthSyncBatch(
                  batchId: batchId,
                  athleteId: base.athleteId,
                  objectType: 'foreground.workout',
                  queryVersion: base.queryVersion,
                  upserts: base.upserts,
                  deletedExternalIds: base.deletedExternalIds,
                  nextAnchor: null,
                  createdAt: end,
                  requiresAcknowledgement: false,
                  coverageStart: start,
                  coverageEnd: end,
                ),
                syncMode: 'foreground',
              )
              .then((_) {});

      await applyCoverage(
        batchId: 'foreground-initial',
        start: DateTime.utc(2026, 6, 15),
        end: DateTime.utc(2026, 7, 15),
      );
      await applyCoverage(
        batchId: 'foreground-incremental',
        start: DateTime.utc(2026, 7, 14),
        end: DateTime.utc(2026, 7, 16),
      );

      final String payload =
          driver.anchors['athlete-a|coverage:foreground.workout|1']!;
      expect(jsonDecode(payload)['start'], '2026-06-15T00:00:00.000Z');
      expect(jsonDecode(payload)['end'], '2026-07-16T00:00:00.000Z');
    });

    test('锚点提交失败时回滚本批次的全部事实和同步运行记录', () async {
      driver.failAnchorCommit = true;

      await expectLater(
        coordinator.apply(
          _workoutBatch(
            batchId: 'batch-failed',
            durationSeconds: 1800,
            nextAnchor: 'anchor-failed',
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(driver.workouts, isEmpty);
      expect(driver.syncRuns, isEmpty);
      expect(driver.anchors, isEmpty);
    });

    test('清理指定运动员时不影响其他账号，并在事务内执行外键检查', () async {
      await coordinator.apply(
        _workoutBatch(
          batchId: 'batch-a',
          athleteId: 'athlete-a',
          externalUuid: 'workout-a',
          durationSeconds: 1800,
          nextAnchor: 'anchor-a',
        ),
      );
      await coordinator.apply(
        _workoutBatch(
          batchId: 'batch-b',
          athleteId: 'athlete-b',
          externalUuid: 'workout-b',
          durationSeconds: 2400,
          nextAnchor: 'anchor-b',
        ),
      );
      driver.reportRows['report-a'] = <String, Object?>{
        'id': 'report-a',
        'athlete_profile_id': 'athlete-a',
      };
      driver.reportRows['report-b'] = <String, Object?>{
        'id': 'report-b',
        'athlete_profile_id': 'athlete-b',
      };
      driver.proposalRows['proposal-a'] = <String, Object?>{
        'id': 'proposal-a',
        'athlete_profile_id': 'athlete-a',
      };

      await coordinator.clearAthleteData('athlete-a');

      expect(
        driver.workouts.values
            .map((Map<String, Object?> row) => row['athlete_profile_id']),
        <Object?>['athlete-b'],
      );
      expect(driver.reportRows.keys, <String>['report-b']);
      expect(driver.proposalRows, isEmpty);
      expect(
          driver.anchors.keys, <String>['athlete-b|HKWorkoutTypeIdentifier|1']);
      expect(driver.foreignKeyCheckCount, 1);
    });
  });

  group('本地训练事实原子写入', () {
    late _MemoryStructuredDriver driver;
    late StructuredLocalTrainingCoordinator coordinator;

    setUp(() {
      driver = _MemoryStructuredDriver(<String>{'athlete-a'});
      coordinator = StructuredLocalTrainingCoordinator(driver);
    });

    test('手动训练以空外部 UUID 写入，并同时保存 L1 判定与力量组次', () async {
      final LocalTrainingFactWriteResult result =
          await coordinator.apply(_localTrainingWrite());

      expect(result.workoutId, 'local-workout:athlete-a:log-1');
      expect(driver.workouts.values.single['external_uuid'], isNull);
      expect(driver.scheduledResultRows, hasLength(1));
      expect(
        driver.scheduledResultRows.values.single['manual_override_status'],
        isNull,
      );
      expect(driver.strengthSetRows, hasLength(1));
      expect(driver.strengthSetRows.values.single['rpe'], isNull);
      expect(driver.foreignKeyCheckCount, 1);
    });

    test('力量组次写入失败时 workout 与 L1 判定一并回滚', () async {
      driver.failStrengthSetWrite = true;

      await expectLater(
        coordinator.apply(_localTrainingWrite()),
        throwsA(isA<StateError>()),
      );

      expect(driver.workouts, isEmpty);
      expect(driver.scheduledResultRows, isEmpty);
      expect(driver.strengthSetRows, isEmpty);
    });

    test('外键检查失败时回滚完整本地训练事实', () async {
      driver.reportForeignKeyViolation = true;

      await expectLater(
        coordinator.apply(_localTrainingWrite()),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            '中文错误',
            contains('外键'),
          ),
        ),
      );

      expect(driver.workouts, isEmpty);
      expect(driver.scheduledResultRows, isEmpty);
      expect(driver.strengthSetRows, isEmpty);
    });

    test('运动员资料不存在时不留下任何部分写入', () async {
      await expectLater(
        coordinator.apply(_localTrainingWrite(athleteId: 'missing-athlete')),
        throwsA(isA<StateError>()),
      );

      expect(driver.workouts, isEmpty);
      expect(driver.scheduledResultRows, isEmpty);
    });

    test('系统重算只更新 system 字段，不覆盖已经存在的人工判定', () async {
      final LocalTrainingFactWrite first = _localTrainingWrite();
      await coordinator.apply(first);
      final Map<String, Object?> stored =
          driver.scheduledResultRows.values.single;
      stored['manual_override_status'] = 'partial';
      stored['override_reason'] = '用户确认只完成一半';

      final LocalTrainingFactWrite recomputed = _localTrainingWrite();
      recomputed.scheduledWorkoutResultRow['system_status'] = 'missed';
      recomputed.scheduledWorkoutResultRow['system_completion_ratio'] = 0.2;
      await coordinator.apply(recomputed);

      final Map<String, Object?> updated =
          driver.scheduledResultRows.values.single;
      expect(updated['system_status'], 'missed');
      expect(updated['manual_override_status'], 'partial');
      expect(updated['override_reason'], '用户确认只完成一半');
    });
  });

  group('L1 计划快照原子投影', () {
    late _MemoryStructuredDriver driver;
    late StructuredL1ScheduleCoordinator coordinator;

    setUp(() {
      driver = _MemoryStructuredDriver(<String>{'athlete-a'});
      coordinator = StructuredL1ScheduleCoordinator(driver);
    });

    test('计划、计划项、训练事实和稳定判定 ID 在一个事务内写入', () async {
      final L1ScheduleProjectionWrite write =
          _l1ScheduleProjectionWrite(matched: true);

      final L1ScheduleProjectionWriteResult first =
          await coordinator.apply(write);
      final String resultId = write
          .localTrainingFacts.single.scheduledWorkoutResultRow['id']! as String;
      final Map<String, Object?> stored = driver.scheduledResultRows[resultId]!;

      expect(first.planVersionId, 'l1-plan:athlete-a');
      expect(driver.planVersionRows, hasLength(1));
      expect(driver.scheduledWorkoutRows, hasLength(1));
      expect(stored['scheduled_workout_id'], 'l1-scheduled:athlete-a:plan-1');
      expect(stored['workout_id'], 'local-workout:athlete-a:log-1');

      write.localTrainingFacts.single.scheduledWorkoutResultRow
        ..['system_status'] = 'partial'
        ..['system_completion_ratio'] = 0.75;
      await coordinator.apply(write);

      expect(driver.scheduledResultRows, hasLength(1));
      expect(driver.scheduledResultRows.keys.single, resultId);
      expect(driver.scheduledResultRows[resultId]!['system_status'], 'partial');
    });

    test('无计划训练后续匹配计划项时清理陈旧 unplanned 行', () async {
      final L1ScheduleProjectionWrite unplanned =
          _l1ScheduleProjectionWrite(matched: false);
      await coordinator.apply(unplanned);
      expect(driver.scheduledResultRows.keys.single, contains('unplanned'));

      final L1ScheduleProjectionWrite matched =
          _l1ScheduleProjectionWrite(matched: true);
      await coordinator.apply(matched);

      expect(driver.scheduledResultRows, hasLength(1));
      expect(driver.scheduledResultRows.keys.single, contains('scheduled'));
      expect(
        driver.scheduledResultRows.values.single['scheduled_workout_id'],
        isNotNull,
      );
    });

    test('外键检查失败时回滚计划、训练和判定', () async {
      driver.reportForeignKeyViolation = true;

      await expectLater(
        coordinator.apply(_l1ScheduleProjectionWrite(matched: true)),
        throwsA(isA<StateError>()),
      );

      expect(driver.planVersionRows, isEmpty);
      expect(driver.scheduledWorkoutRows, isEmpty);
      expect(driver.workouts, isEmpty);
      expect(driver.scheduledResultRows, isEmpty);
    });
  });

  group('版本化数据库备份清理边界', () {
    test('只删除当前数据库同目录且严格匹配 .vN.bak 的普通文件', () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('trainmate-backup-test-');
      addTearDown(() => directory.delete(recursive: true));
      final String databasePath = p.join(directory.path, 'trainflow.db');
      final File version1 = File('$databasePath.v1.bak');
      final File version23 = File('$databasePath.v23.bak');
      final File version0 = File('$databasePath.v0.bak');
      final File suffixMismatch = File('$databasePath.v2.bak.keep');
      final File otherDatabase =
          File(p.join(directory.path, 'other.db.v1.bak'));
      final Directory nested = Directory(p.join(directory.path, 'nested'));
      await nested.create();
      final File nestedMatch = File(p.join(nested.path, 'trainflow.db.v9.bak'));
      for (final File file in <File>[
        version1,
        version23,
        version0,
        suffixMismatch,
        otherDatabase,
        nestedMatch,
      ]) {
        await file.writeAsString('测试备份');
      }

      final int removed =
          await removeControlledVersionedDatabaseBackups(databasePath);

      expect(removed, 2);
      expect(await version1.exists(), isFalse);
      expect(await version23.exists(), isFalse);
      expect(await version0.exists(), isTrue);
      expect(await suffixMismatch.exists(), isTrue);
      expect(await otherDatabase.exists(), isTrue);
      expect(await nestedMatch.exists(), isTrue);
    });

    test('拒绝相对路径，避免清理范围随工作目录漂移', () async {
      await expectLater(
        removeControlledVersionedDatabaseBackups('trainflow.db'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            '中文错误',
            contains('绝对路径'),
          ),
        ),
      );
    });
  });
}

L1ScheduleProjectionWrite _l1ScheduleProjectionWrite({
  required bool matched,
}) {
  final LocalTrainingFactWrite fact = _localTrainingWrite();
  final Map<String, Object?> result = fact.scheduledWorkoutResultRow;
  result['id'] = matched
      ? 'local-result:athlete-a:scheduled:plan-1'
      : 'local-result:athlete-a:unplanned:log-1';
  result['scheduled_workout_id'] =
      matched ? 'l1-scheduled:athlete-a:plan-1' : null;
  return L1ScheduleProjectionWrite(
    planVersionRow: <String, Object?>{
      'id': 'l1-plan:athlete-a',
      'athlete_profile_id': 'athlete-a',
      'activated_at': '2026-07-15T09:00:00.000Z',
      'created_at': '2026-07-15T09:00:00.000Z',
    },
    scheduledWorkoutRows: matched
        ? <Map<String, Object?>>[
            <String, Object?>{
              'id': 'l1-scheduled:athlete-a:plan-1',
              'plan_version_id': 'l1-plan:athlete-a',
              'source_workout_id': 'plan-1',
              'status': 'planned',
              'created_at': '2026-07-15T09:00:00.000Z',
              'updated_at': '2026-07-15T09:00:00.000Z',
            },
          ]
        : const <Map<String, Object?>>[],
    localTrainingFacts: <LocalTrainingFactWrite>[fact],
    unmatchedScheduledResultRows: const <Map<String, Object?>>[],
  );
}

LocalTrainingFactWrite _localTrainingWrite({
  String athleteId = 'athlete-a',
}) {
  final String workoutId = 'local-workout:$athleteId:log-1';
  return LocalTrainingFactWrite(
    workoutRow: <String, Object?>{
      'id': workoutId,
      'athlete_profile_id': athleteId,
      'external_uuid': null,
      'source_kind': 'local_manual',
      'created_at': '2026-07-15T09:00:00.000Z',
    },
    scheduledWorkoutResultRow: <String, Object?>{
      'id': 'local-result:$athleteId:plan-1:log-1',
      'athlete_profile_id': athleteId,
      'scheduled_workout_id': null,
      'workout_id': workoutId,
      'system_status': 'completed',
      'system_completion_ratio': 1.0,
      'manual_override_status': null,
      'override_reason': null,
      'matching_basis': 'plan_item_id=plan-1;match=workout_day_id',
      'decided_at': '2026-07-15T09:00:00.000Z',
      'updated_at': '2026-07-15T09:00:00.000Z',
    },
    strengthSetRows: <Map<String, Object?>>[
      <String, Object?>{
        'id': 'strength-set-1',
        'athlete_profile_id': athleteId,
        'workout_id': workoutId,
        'rpe': null,
      },
    ],
  );
}

HealthSyncBatch _workoutBatch({
  required String batchId,
  String athleteId = 'athlete-a',
  String externalUuid = 'workout-uuid',
  required int durationSeconds,
  required String nextAnchor,
  String timeZoneName = 'Asia/Shanghai',
  int timeZoneOffsetMinutes = 480,
}) {
  return HealthSyncBatch(
    batchId: batchId,
    athleteId: athleteId,
    objectType: 'HKWorkoutTypeIdentifier',
    queryVersion: 1,
    upserts: <Map<String, Object?>>[
      <String, Object?>{
        'uuid': externalUuid,
        'kind': 'workout',
        'healthKitType': 'HKWorkoutTypeIdentifier',
        'sourceBundleId': 'com.apple.health',
        'sourceName': '健康',
        'startTime': DateTime.utc(2026, 7, 15, 8).millisecondsSinceEpoch,
        'endTime': DateTime.utc(2026, 7, 15, 8)
            .add(Duration(seconds: durationSeconds))
            .millisecondsSinceEpoch,
        'durationSeconds': durationSeconds,
        'discipline': 'roadRun',
        'runContext': 'road',
        'timeZoneName': timeZoneName,
        'timeZoneOffsetMinutes': timeZoneOffsetMinutes,
        'totalDistanceMeters': 5000.0,
      },
    ],
    deletedExternalIds: const <String>[],
    nextAnchor: nextAnchor,
    createdAt: DateTime.utc(2026, 7, 15, 9),
    requiresAcknowledgement: true,
  );
}

class _MemoryStructuredDriver implements StructuredStorageDriver {
  _MemoryStructuredDriver(this.athletes);

  final Set<String> athletes;
  Map<String, Map<String, Object?>> workouts = <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> observations =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> syncRuns = <String, Map<String, Object?>>{};
  Map<String, String> anchors = <String, String>{};
  Map<String, Map<String, Object?>> analysisRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> metricRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> lineageRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> growthEvidenceRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> reportRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> proposalRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> planVersionRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> scheduledWorkoutRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> scheduledResultRows =
      <String, Map<String, Object?>>{};
  Map<String, Map<String, Object?>> strengthSetRows =
      <String, Map<String, Object?>>{};
  bool failAnchorCommit = false;
  bool failStrengthSetWrite = false;
  bool reportForeignKeyViolation = false;
  int foreignKeyCheckCount = 0;

  @override
  Future<T> runStructuredTransaction<T>(
    Future<T> Function(StructuredStorageTransaction transaction) action,
  ) async {
    final String snapshot = jsonEncode(<String, Object?>{
      'workouts': workouts,
      'observations': observations,
      'syncRuns': syncRuns,
      'anchors': anchors,
      'analysisRows': analysisRows,
      'metricRows': metricRows,
      'lineageRows': lineageRows,
      'growthEvidenceRows': growthEvidenceRows,
      'reportRows': reportRows,
      'proposalRows': proposalRows,
      'planVersionRows': planVersionRows,
      'scheduledWorkoutRows': scheduledWorkoutRows,
      'scheduledResultRows': scheduledResultRows,
      'strengthSetRows': strengthSetRows,
      'foreignKeyCheckCount': foreignKeyCheckCount,
    });
    try {
      return await action(_MemoryStructuredTransaction(this));
    } catch (_) {
      final Map<String, Object?> restored =
          Map<String, Object?>.from(jsonDecode(snapshot) as Map);
      workouts = _rows(restored['workouts']);
      observations = _rows(restored['observations']);
      syncRuns = _rows(restored['syncRuns']);
      anchors = Map<String, String>.from(restored['anchors']! as Map);
      analysisRows = _rows(restored['analysisRows']);
      metricRows = _rows(restored['metricRows']);
      lineageRows = _rows(restored['lineageRows']);
      growthEvidenceRows = _rows(restored['growthEvidenceRows']);
      reportRows = _rows(restored['reportRows']);
      proposalRows = _rows(restored['proposalRows']);
      planVersionRows = _rows(restored['planVersionRows']);
      scheduledWorkoutRows = _rows(restored['scheduledWorkoutRows']);
      scheduledResultRows = _rows(restored['scheduledResultRows']);
      strengthSetRows = _rows(restored['strengthSetRows']);
      foreignKeyCheckCount = restored['foreignKeyCheckCount']! as int;
      rethrow;
    }
  }
}

class _MemoryStructuredTransaction implements StructuredStorageTransaction {
  const _MemoryStructuredTransaction(this.driver);

  final _MemoryStructuredDriver driver;

  @override
  Future<void> upsertTrainingPlanVersion(Map<String, Object?> row) async {
    _requireAthlete(row['athlete_profile_id']);
    final String id = row['id']! as String;
    final Object? createdAt = driver.planVersionRows[id]?['created_at'];
    driver.planVersionRows[id] = Map<String, Object?>.from(row);
    if (createdAt != null) {
      driver.planVersionRows[id]!['created_at'] = createdAt;
    }
  }

  @override
  Future<void> upsertScheduledWorkout(Map<String, Object?> row) async {
    final String planVersionId = row['plan_version_id']! as String;
    if (!driver.planVersionRows.containsKey(planVersionId)) {
      throw StateError('L1 计划项引用的计划版本不存在');
    }
    final String id = row['id']! as String;
    final Object? createdAt = driver.scheduledWorkoutRows[id]?['created_at'];
    driver.scheduledWorkoutRows[id] = Map<String, Object?>.from(row);
    if (createdAt != null) {
      driver.scheduledWorkoutRows[id]!['created_at'] = createdAt;
    }
  }

  @override
  Future<void> supersedeMissingScheduledWorkouts({
    required String planVersionId,
    required List<String> activeScheduledWorkoutIds,
    required String updatedAt,
  }) async {
    final Set<String> activeIds = activeScheduledWorkoutIds.toSet();
    for (final MapEntry<String, Map<String, Object?>> entry
        in driver.scheduledWorkoutRows.entries) {
      if (entry.value['plan_version_id'] == planVersionId &&
          !activeIds.contains(entry.key)) {
        entry.value['status'] = 'superseded';
        entry.value['updated_at'] = updatedAt;
      }
    }
  }

  @override
  Future<void> upsertLocalWorkout(Map<String, Object?> row) async {
    _requireAthlete(row['athlete_profile_id']);
    if (row['external_uuid'] != null) {
      throw StateError('本地训练不得包含外部 UUID');
    }
    final String id = row['id']! as String;
    final Object? createdAt = driver.workouts[id]?['created_at'];
    driver.workouts[id] = Map<String, Object?>.from(row);
    if (createdAt != null) driver.workouts[id]!['created_at'] = createdAt;
  }

  @override
  Future<void> upsertScheduledWorkoutResult(
    Map<String, Object?> row,
  ) async {
    _requireAthlete(row['athlete_profile_id']);
    final Object? workoutId = row['workout_id'];
    if (workoutId != null && !driver.workouts.containsKey(workoutId)) {
      throw StateError('L1 判定引用的本地训练不存在');
    }
    final Object? scheduledWorkoutId = row['scheduled_workout_id'];
    if (scheduledWorkoutId != null &&
        !driver.scheduledWorkoutRows.containsKey(scheduledWorkoutId)) {
      throw StateError('L1 判定引用的计划项不存在');
    }
    final String id = row['id']! as String;
    final Object? manualOverride =
        driver.scheduledResultRows[id]?['manual_override_status'];
    final Object? overrideReason =
        driver.scheduledResultRows[id]?['override_reason'];
    final Object? overrideUpdatedAt =
        manualOverride != null || overrideReason != null
            ? (driver.scheduledResultRows[id]?['updated_at'])
            : null;
    driver.scheduledResultRows[id] = Map<String, Object?>.from(row)
      ..['manual_override_status'] = manualOverride
      ..['override_reason'] = overrideReason;
    if (overrideUpdatedAt != null) {
      driver.scheduledResultRows[id]!['updated_at'] = overrideUpdatedAt;
    }
  }

  @override
  Future<void> deleteUnplannedResultsForWorkout({
    required String athleteId,
    required String workoutId,
    required String exceptResultId,
  }) async {
    driver.scheduledResultRows.removeWhere(
      (String id, Map<String, Object?> row) =>
          id != exceptResultId &&
          row['athlete_profile_id'] == athleteId &&
          row['workout_id'] == workoutId &&
          row['scheduled_workout_id'] == null,
    );
  }

  @override
  Future<void> replaceStrengthSets({
    required String athleteId,
    required String workoutId,
    required List<Map<String, Object?>> rows,
  }) async {
    _requireAthlete(athleteId);
    if (!driver.workouts.containsKey(workoutId)) {
      throw StateError('力量组次引用的本地训练不存在');
    }
    driver.strengthSetRows.removeWhere(
      (String _, Map<String, Object?> row) =>
          row['athlete_profile_id'] == athleteId &&
          row['workout_id'] == workoutId,
    );
    if (driver.failStrengthSetWrite) {
      throw StateError('测试力量组次写入失败');
    }
    for (final Map<String, Object?> row in rows) {
      driver.strengthSetRows[row['id']! as String] =
          Map<String, Object?>.from(row);
    }
  }

  @override
  Future<void> beginSyncRun(Map<String, Object?> row) async {
    _requireAthlete(row['athlete_profile_id']);
    driver.syncRuns[row['id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> completeSyncRun(Map<String, Object?> row) async {
    final Map<String, Object?> current = driver.syncRuns[row['id']]!;
    current.addAll(row);
  }

  @override
  Future<StructuredFactUpsertResult> upsertWorkout(
    Map<String, Object?> row,
  ) async {
    _requireAthlete(row['athlete_profile_id']);
    final MapEntry<String, Map<String, Object?>>? existing = driver
        .workouts.entries
        .cast<MapEntry<String, Map<String, Object?>>?>()
        .firstWhere(
          (MapEntry<String, Map<String, Object?>>? entry) =>
              entry != null &&
              entry.value['athlete_profile_id'] == row['athlete_profile_id'] &&
              entry.value['source_bundle_id'] == row['source_bundle_id'] &&
              entry.value['external_uuid'] == row['external_uuid'],
          orElse: () => null,
        );
    if (existing == null) {
      driver.workouts[row['id']! as String] = Map<String, Object?>.from(row);
      return StructuredFactUpsertResult(
        sourceType: 'workouts',
        sourceId: row['id']! as String,
        changedExistingFact: false,
        localDate: row['local_date'] as String?,
        timeZoneName: row['time_zone_name'] as String?,
      );
    }
    final bool changed = existing.value['payload_json'] != row['payload_json'];
    final Object? createdAt = existing.value['created_at'];
    existing.value
      ..addAll(row)
      ..['id'] = existing.key
      ..['created_at'] = createdAt;
    return StructuredFactUpsertResult(
      sourceType: 'workouts',
      sourceId: existing.key,
      changedExistingFact: changed,
      localDate: row['local_date'] as String?,
      timeZoneName: row['time_zone_name'] as String?,
    );
  }

  @override
  Future<StructuredFactUpsertResult> upsertHealthObservation(
    Map<String, Object?> row,
  ) async {
    _requireAthlete(row['athlete_profile_id']);
    final String? existingId = driver.observations.entries
        .where((MapEntry<String, Map<String, Object?>> entry) =>
            entry.value['athlete_profile_id'] == row['athlete_profile_id'] &&
            entry.value['source_bundle_id'] == row['source_bundle_id'] &&
            entry.value['external_uuid'] == row['external_uuid'])
        .map((MapEntry<String, Map<String, Object?>> entry) => entry.key)
        .firstOrNull;
    if (existingId == null) {
      driver.observations[row['id']! as String] =
          Map<String, Object?>.from(row);
      return StructuredFactUpsertResult(
        sourceType: 'health_observations',
        sourceId: row['id']! as String,
        changedExistingFact: false,
        localDate: row['local_date'] as String?,
        timeZoneName: row['time_zone_name'] as String?,
      );
    }
    final Map<String, Object?> existing = driver.observations[existingId]!;
    final bool changed = existing['payload_json'] != row['payload_json'];
    existing.addAll(row);
    return StructuredFactUpsertResult(
      sourceType: 'health_observations',
      sourceId: existingId,
      changedExistingFact: changed,
      localDate: row['local_date'] as String?,
      timeZoneName: row['time_zone_name'] as String?,
    );
  }

  @override
  Future<List<StructuredSourceReference>> markExternalIdDeleted({
    required String athleteId,
    required String externalId,
    required DateTime deletedAt,
  }) async {
    final List<StructuredSourceReference> affected =
        <StructuredSourceReference>[];
    for (final MapEntry<String, Map<String, Object?>> entry
        in driver.workouts.entries) {
      if (entry.value['athlete_profile_id'] == athleteId &&
          entry.value['external_uuid'] == externalId) {
        entry.value['source_deleted_at'] = deletedAt.toIso8601String();
        affected.add(StructuredSourceReference(
          'workouts',
          entry.key,
          localDate: entry.value['local_date'] as String?,
          timeZoneName: entry.value['time_zone_name'] as String?,
        ));
      }
    }
    for (final MapEntry<String, Map<String, Object?>> entry
        in driver.observations.entries) {
      if (entry.value['athlete_profile_id'] == athleteId &&
          entry.value['external_uuid'] == externalId) {
        entry.value['source_deleted_at'] = deletedAt.toIso8601String();
        affected.add(StructuredSourceReference(
          'health_observations',
          entry.key,
          localDate: entry.value['local_date'] as String?,
          timeZoneName: entry.value['time_zone_name'] as String?,
        ));
      }
    }
    return affected;
  }

  @override
  Future<List<StructuredSourceReference>> markRoutePending(
    Map<String, Object?> routeRow,
  ) async =>
      const <StructuredSourceReference>[];

  @override
  Future<List<StructuredSourceReference>> markRouteDeleted({
    required String athleteId,
    required String routeExternalId,
    required DateTime deletedAt,
  }) async =>
      const <StructuredSourceReference>[];

  @override
  Future<void> invalidateSource({
    required String athleteId,
    required StructuredSourceReference source,
    required DateTime invalidatedAt,
  }) async {
    final String timestamp = invalidatedAt.toIso8601String();
    if (source.sourceType == 'workouts') {
      for (final Map<String, Object?> row in driver.analysisRows.values) {
        if (row['athlete_profile_id'] == athleteId &&
            row['workout_id'] == source.sourceId) {
          row['status'] = 'invalidated';
          row['invalidated_at'] = timestamp;
        }
      }
    }
    final Set<String> metricIds = driver.lineageRows.values
        .where((Map<String, Object?> row) =>
            row['source_table'] == source.sourceType &&
            row['source_id'] == source.sourceId &&
            row['invalidated_at'] == null)
        .map(
            (Map<String, Object?> row) => row['metric_aggregate_id']! as String)
        .toSet();
    for (final String metricId in metricIds) {
      final Map<String, Object?>? metric = driver.metricRows[metricId];
      if (metric?['athlete_profile_id'] == athleteId) {
        metric!['status'] = 'invalidated';
        metric['invalidated_at'] = timestamp;
      }
    }
    for (final Map<String, Object?> row in driver.lineageRows.values) {
      if (metricIds.contains(row['metric_aggregate_id']) &&
          row['source_table'] == source.sourceType &&
          row['source_id'] == source.sourceId) {
        row['invalidated_at'] = timestamp;
      }
    }
    for (final Map<String, Object?> row in driver.growthEvidenceRows.values) {
      if (row['athlete_profile_id'] == athleteId &&
          row['source_table'] == source.sourceType &&
          row['source_id'] == source.sourceId) {
        row['revoked_at'] = timestamp;
      }
    }
  }

  @override
  Future<void> commitAnchor(Map<String, Object?> row) async {
    if (driver.failAnchorCommit) throw StateError('测试锚点写入失败');
    final String key =
        '${row['athlete_profile_id']}|${row['object_type']}|${row['query_version']}';
    driver.anchors[key] = row['anchor_payload']! as String;
  }

  @override
  Future<Map<String, Object?>?> readAnchor({
    required String athleteId,
    required String objectType,
    required int queryVersion,
  }) async {
    final String? payload =
        driver.anchors['$athleteId|$objectType|$queryVersion'];
    return payload == null
        ? null
        : <String, Object?>{'anchor_payload': payload};
  }

  @override
  Future<void> clearAthleteData(String athleteId) async {
    void removeRows(Map<String, Map<String, Object?>> rows) {
      rows.removeWhere((String _, Map<String, Object?> row) =>
          row['athlete_profile_id'] == athleteId);
    }

    removeRows(driver.workouts);
    removeRows(driver.observations);
    removeRows(driver.syncRuns);
    removeRows(driver.analysisRows);
    removeRows(driver.metricRows);
    removeRows(driver.growthEvidenceRows);
    removeRows(driver.reportRows);
    removeRows(driver.proposalRows);
    final Set<String> planIds = driver.planVersionRows.entries
        .where((MapEntry<String, Map<String, Object?>> entry) =>
            entry.value['athlete_profile_id'] == athleteId)
        .map((MapEntry<String, Map<String, Object?>> entry) => entry.key)
        .toSet();
    driver.planVersionRows.removeWhere(
      (String id, Map<String, Object?> _) => planIds.contains(id),
    );
    driver.scheduledWorkoutRows.removeWhere(
      (String _, Map<String, Object?> row) =>
          planIds.contains(row['plan_version_id']),
    );
    removeRows(driver.scheduledResultRows);
    removeRows(driver.strengthSetRows);
    driver.lineageRows.removeWhere((String _, Map<String, Object?> row) =>
        !driver.metricRows.containsKey(row['metric_aggregate_id']));
    driver.anchors
        .removeWhere((String key, String _) => key.startsWith('$athleteId|'));
  }

  @override
  Future<List<Map<String, Object?>>> foreignKeyCheck() async {
    driver.foreignKeyCheckCount += 1;
    return driver.reportForeignKeyViolation
        ? <Map<String, Object?>>[
            <String, Object?>{'table': 'scheduled_workout_results'},
          ]
        : const <Map<String, Object?>>[];
  }

  void _requireAthlete(Object? athleteId) {
    if (!driver.athletes.contains(athleteId)) {
      throw StateError('运动员资料不存在');
    }
  }
}

Map<String, Map<String, Object?>> _rows(Object? value) {
  return Map<String, Object?>.from(value! as Map).map(
    (String key, Object? row) => MapEntry<String, Map<String, Object?>>(
      key,
      Map<String, Object?>.from(row! as Map),
    ),
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => this.isEmpty ? null : first;
}
