import 'dart:convert';
import 'dart:math' as math;

import '../../features/profile/application/health_data_gateway_contract.dart';
import '../models/training_metrics.dart';

/// TrainMate 结构化事实、指标和报告的持久化边界。
///
/// 该边界刻意不暴露 SQLite 对象，避免计算层和界面层绕过事务、账号隔离
/// 与不可变报告修订约束。
abstract interface class TrainMateStructuredDatabaseGateway {
  /// 原子投影当前 L1 计划、计划项、训练事实与系统判定。
  Future<L1ScheduleProjectionWriteResult> saveL1ScheduleProjection(
    L1ScheduleProjectionWrite write,
  );

  /// 原子写入一条本地训练事实、L1 判定和对应力量组次。
  Future<LocalTrainingFactWriteResult> saveLocalTrainingFact(
    LocalTrainingFactWrite write,
  );

  /// 按运动员和本地日期读取当前有效的 L1 判定事实。
  Future<List<StructuredScheduledWorkoutResult>> listScheduledWorkoutResults({
    required String athleteProfileId,
    required DateTime startLocalDate,
    required DateTime endExclusiveLocalDate,
  });

  /// 写入人工覆盖；系统判定字段保持不变。
  Future<StructuredScheduledWorkoutResult> setScheduledWorkoutResultOverride({
    required String athleteProfileId,
    required String resultId,
    required WorkoutCompletionStatus status,
    required String reason,
    required DateTime overriddenAt,
  });

  /// 清除人工覆盖并保留清除原因和时间；系统判定重新成为有效判定。
  Future<StructuredScheduledWorkoutResult> clearScheduledWorkoutResultOverride({
    required String athleteProfileId,
    required String resultId,
    required String reason,
    required DateTime clearedAt,
  });

  Future<HealthSyncApplyResult> applyHealthSyncBatch(
    HealthSyncBatch batch, {
    String syncMode = 'background',
  });

  Future<void> clearAthleteStructuredData(String athleteId);

  Future<Map<String, Object?>?> readHealthSyncAnchor({
    required String athleteId,
    required String objectType,
    required int queryVersion,
  });

  Future<Map<String, Object?>?> readAthleteProfileRow(
    String athleteProfileId,
  );

  Future<Map<String, Object?>?> readWorkoutFactRow({
    required String athleteProfileId,
    required String workoutId,
  });

  Future<Map<String, Object?>?> findWorkoutFactRowByExternalId({
    required String athleteProfileId,
    required String sourceBundleId,
    required String externalUuid,
  });

  Future<List<Map<String, Object?>>> listWorkoutFactRows({
    required String athleteProfileId,
    required String startedAtOrAfter,
    required String startedBefore,
  });

  Future<List<Map<String, Object?>>> listStrengthSetRows({
    required String athleteProfileId,
    required String localDateOnOrAfter,
    required String localDateBefore,
  });

  Future<List<Map<String, Object?>>> listAthletePrimaryExerciseRows({
    required String athleteProfileId,
  });

  Future<void> setAthletePrimaryExercise({
    required String athleteProfileId,
    required String exerciseKey,
    required String displayName,
    required bool isActive,
    required DateTime updatedAt,
  });

  Future<List<Map<String, Object?>>> listHealthObservationFactRows({
    required String athleteProfileId,
    required String observedAtOrAfter,
    required String observedBefore,
  });

  Future<void> saveWorkoutAnalysisRunRow(
    Map<String, Object?> row, {
    bool markRouteAvailable = false,
  });

  Future<List<Map<String, Object?>>> listWorkoutAnalysisRunRows({
    required String athleteProfileId,
    required String workoutStartedAtOrAfter,
    required String workoutStartedBefore,
  });

  Future<void> saveMetricAggregateRow(Map<String, Object?> row);

  Future<List<Map<String, Object?>>> listMetricAggregateRows({
    required String athleteProfileId,
    String? periodType,
    String? periodStartLocal,
    required bool includeInvalidated,
  });

  Future<void> saveMetricLineageRow(Map<String, Object?> row);

  Future<List<Map<String, Object?>>> listMetricLineageRows({
    required String metricId,
  });

  Future<List<String>> invalidateMetricRowsBySource({
    required String athleteProfileId,
    required String sourceType,
    required String sourceId,
    required String invalidatedAt,
  });

  Future<void> saveReportRevisionRow(Map<String, Object?> row);

  Future<List<Map<String, Object?>>> listReportRevisionRows({
    required String athleteProfileId,
    required String reportType,
    required String periodKey,
  });

  Future<void> saveAdjustmentProposalRow(Map<String, Object?> row);

  Future<List<Map<String, Object?>>> listAdjustmentProposalRows({
    required String athleteProfileId,
  });
}

/// HealthKit 跑步只提供 `.running`，公路/越野上下文必须由用户明确确认。
///
/// 单独定义能力接口，避免 Web/测试桩伪造可用的 HealthKit 分类功能。
abstract interface class RunContextDatabaseGateway {
  Future<List<Map<String, Object?>>> listRunningWorkoutsNeedingContext({
    required String athleteProfileId,
    int limit = 20,
  });

  Future<void> confirmRunningWorkoutContext({
    required String athleteProfileId,
    required String workoutId,
    required String runContext,
    required DateTime confirmedAt,
  });
}

class L1ScheduleProjectionWrite {
  const L1ScheduleProjectionWrite({
    required this.planVersionRow,
    required this.scheduledWorkoutRows,
    required this.localTrainingFacts,
    required this.unmatchedScheduledResultRows,
  });

  final Map<String, Object?> planVersionRow;
  final List<Map<String, Object?>> scheduledWorkoutRows;
  final List<LocalTrainingFactWrite> localTrainingFacts;
  final List<Map<String, Object?>> unmatchedScheduledResultRows;
}

class L1ScheduleProjectionWriteResult {
  const L1ScheduleProjectionWriteResult({
    required this.planVersionId,
    required this.scheduledWorkoutCount,
    required this.workoutCount,
    required this.resultCount,
    required this.strengthSetCount,
  });

  final String planVersionId;
  final int scheduledWorkoutCount;
  final int workoutCount;
  final int resultCount;
  final int strengthSetCount;
}

class StructuredScheduledWorkoutResult {
  const StructuredScheduledWorkoutResult({
    required this.id,
    required this.athleteProfileId,
    required this.scheduledWorkoutId,
    required this.sourceScheduledWorkoutId,
    required this.workoutId,
    required this.localDate,
    required this.systemStatus,
    required this.systemCompletionRatio,
    required this.manualOverrideStatus,
    required this.overrideReason,
    required this.matchingBasis,
    required this.systemDecidedAt,
    required this.overrideUpdatedAt,
  });

  final String id;
  final String athleteProfileId;
  final String? scheduledWorkoutId;
  final String? sourceScheduledWorkoutId;
  final String? workoutId;
  final DateTime localDate;
  final WorkoutCompletionStatus systemStatus;
  final double? systemCompletionRatio;
  final WorkoutCompletionStatus? manualOverrideStatus;
  final String? overrideReason;
  final String matchingBasis;
  final DateTime systemDecidedAt;
  final DateTime? overrideUpdatedAt;

  WorkoutCompletionStatus get effectiveStatus =>
      manualOverrideStatus ?? systemStatus;

  ScheduledWorkoutResult toDomainResult() => ScheduledWorkoutResult(
        planItemId: sourceScheduledWorkoutId,
        workoutId: workoutId,
        status: systemStatus,
        completionRatio: systemCompletionRatio,
        evaluatedAt: systemDecidedAt,
        algorithmVersion: 'trainmate-l1-completion-v1',
        reason: matchingBasis,
        manualStatus: manualOverrideStatus,
        manualReason: overrideReason,
      );
}

class LocalTrainingFactWrite {
  const LocalTrainingFactWrite({
    required this.workoutRow,
    required this.scheduledWorkoutResultRow,
    this.strengthSetRows = const <Map<String, Object?>>[],
  });

  final Map<String, Object?> workoutRow;
  final Map<String, Object?> scheduledWorkoutResultRow;
  final List<Map<String, Object?>> strengthSetRows;
}

class LocalTrainingFactWriteResult {
  const LocalTrainingFactWriteResult({
    required this.workoutId,
    required this.scheduledWorkoutResultId,
    required this.strengthSetCount,
  });

  final String workoutId;
  final String scheduledWorkoutResultId;
  final int strengthSetCount;
}

class HealthSyncApplyResult {
  const HealthSyncApplyResult({
    required this.batchId,
    required this.upsertCount,
    required this.deletedCount,
    required this.invalidatedSourceIds,
    this.invalidatedSources = const <StructuredSourceReference>[],
  });

  final String batchId;
  final int upsertCount;
  final int deletedCount;
  final List<String> invalidatedSourceIds;
  final List<StructuredSourceReference> invalidatedSources;
}

class StructuredSourceReference {
  const StructuredSourceReference(
    this.sourceType,
    this.sourceId, {
    this.localDate,
    this.timeZoneName,
  });

  final String sourceType;
  final String sourceId;
  final String? localDate;
  final String? timeZoneName;

  @override
  bool operator ==(Object other) =>
      other is StructuredSourceReference &&
      other.sourceType == sourceType &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(sourceType, sourceId);
}

class StructuredFactUpsertResult extends StructuredSourceReference {
  const StructuredFactUpsertResult({
    required String sourceType,
    required String sourceId,
    required this.changedExistingFact,
    String? localDate,
    String? timeZoneName,
  }) : super(
          sourceType,
          sourceId,
          localDate: localDate,
          timeZoneName: timeZoneName,
        );

  final bool changedExistingFact;
}

/// 将批次编排与具体 SQLite 调用分开，确保生产实现和事务测试共用同一套规则。
abstract interface class StructuredStorageDriver {
  Future<T> runStructuredTransaction<T>(
    Future<T> Function(StructuredStorageTransaction transaction) action,
  );
}

abstract interface class StructuredStorageTransaction {
  Future<void> upsertTrainingPlanVersion(Map<String, Object?> row);

  Future<void> upsertScheduledWorkout(Map<String, Object?> row);

  Future<void> supersedeMissingScheduledWorkouts({
    required String planVersionId,
    required List<String> activeScheduledWorkoutIds,
    required String updatedAt,
  });

  Future<void> upsertLocalWorkout(Map<String, Object?> row);

  Future<void> upsertScheduledWorkoutResult(Map<String, Object?> row);

  Future<void> deleteUnplannedResultsForWorkout({
    required String athleteId,
    required String workoutId,
    required String exceptResultId,
  });

  Future<void> replaceStrengthSets({
    required String athleteId,
    required String workoutId,
    required List<Map<String, Object?>> rows,
  });

  Future<void> beginSyncRun(Map<String, Object?> row);

  Future<void> completeSyncRun(Map<String, Object?> row);

  Future<StructuredFactUpsertResult> upsertWorkout(
    Map<String, Object?> row,
  );

  Future<StructuredFactUpsertResult> upsertHealthObservation(
    Map<String, Object?> row,
  );

  Future<List<StructuredSourceReference>> markExternalIdDeleted({
    required String athleteId,
    required String externalId,
    required DateTime deletedAt,
  });

  Future<List<StructuredSourceReference>> markRoutePending(
    Map<String, Object?> routeRow,
  );

  Future<List<StructuredSourceReference>> markRouteDeleted({
    required String athleteId,
    required String routeExternalId,
    required DateTime deletedAt,
  });

  Future<void> invalidateSource({
    required String athleteId,
    required StructuredSourceReference source,
    required DateTime invalidatedAt,
  });

  Future<Map<String, Object?>?> readAnchor({
    required String athleteId,
    required String objectType,
    required int queryVersion,
  });

  Future<void> commitAnchor(Map<String, Object?> row);

  Future<void> clearAthleteData(String athleteId);

  Future<List<Map<String, Object?>>> foreignKeyCheck();
}

/// 在一个底层事务内投影完整的当前 L1 计划快照。
class StructuredL1ScheduleCoordinator {
  const StructuredL1ScheduleCoordinator(this._driver);

  final StructuredStorageDriver _driver;

  Future<L1ScheduleProjectionWriteResult> apply(
    L1ScheduleProjectionWrite write,
  ) async {
    _validate(write);
    final String planVersionId = write.planVersionRow['id']! as String;
    final String athleteId =
        write.planVersionRow['athlete_profile_id']! as String;
    final List<Map<String, Object?>> allResults = <Map<String, Object?>>[
      ...write.localTrainingFacts
          .map((LocalTrainingFactWrite item) => item.scheduledWorkoutResultRow),
      ...write.unmatchedScheduledResultRows,
    ];
    return _driver.runStructuredTransaction<L1ScheduleProjectionWriteResult>(
      (StructuredStorageTransaction transaction) async {
        await transaction.upsertTrainingPlanVersion(write.planVersionRow);
        for (final Map<String, Object?> row in write.scheduledWorkoutRows) {
          await transaction.upsertScheduledWorkout(row);
        }
        await transaction.supersedeMissingScheduledWorkouts(
          planVersionId: planVersionId,
          activeScheduledWorkoutIds: write.scheduledWorkoutRows
              .map((Map<String, Object?> row) => row['id']! as String)
              .toList(growable: false),
          updatedAt: write.planVersionRow['activated_at']! as String,
        );

        int strengthSetCount = 0;
        for (final LocalTrainingFactWrite fact in write.localTrainingFacts) {
          await transaction.upsertLocalWorkout(fact.workoutRow);
          await transaction.replaceStrengthSets(
            athleteId: athleteId,
            workoutId: fact.workoutRow['id']! as String,
            rows: fact.strengthSetRows,
          );
          strengthSetCount += fact.strengthSetRows.length;
        }

        for (final Map<String, Object?> row in allResults) {
          final String? scheduledWorkoutId =
              row['scheduled_workout_id'] as String?;
          final String? workoutId = row['workout_id'] as String?;
          if (scheduledWorkoutId != null && workoutId != null) {
            await transaction.deleteUnplannedResultsForWorkout(
              athleteId: athleteId,
              workoutId: workoutId,
              exceptResultId: row['id']! as String,
            );
          }
          await transaction.upsertScheduledWorkoutResult(row);
        }
        final List<Map<String, Object?>> violations =
            await transaction.foreignKeyCheck();
        if (violations.isNotEmpty) {
          throw StateError('L1 计划投影写入后的外键校验失败。');
        }
        return L1ScheduleProjectionWriteResult(
          planVersionId: planVersionId,
          scheduledWorkoutCount: write.scheduledWorkoutRows.length,
          workoutCount: write.localTrainingFacts.length,
          resultCount: allResults.length,
          strengthSetCount: strengthSetCount,
        );
      },
    );
  }

  void _validate(L1ScheduleProjectionWrite write) {
    final Map<String, Object?> plan = write.planVersionRow;
    final String? planVersionId = plan['id'] as String?;
    final String? athleteId = plan['athlete_profile_id'] as String?;
    if (planVersionId == null || planVersionId.trim().isEmpty) {
      throw const FormatException('L1 计划投影缺少计划版本 ID。');
    }
    if (athleteId == null || athleteId.trim().isEmpty) {
      throw const FormatException('L1 计划投影缺少运动员资料 ID。');
    }
    final Set<String> scheduledIds = <String>{};
    for (final Map<String, Object?> row in write.scheduledWorkoutRows) {
      final String? id = row['id'] as String?;
      if (id == null || id.trim().isEmpty || !scheduledIds.add(id)) {
        throw const FormatException('L1 计划项 ID 为空或重复。');
      }
      if (row['plan_version_id'] != planVersionId) {
        throw const FormatException('L1 计划项与计划版本不一致。');
      }
    }
    final List<Map<String, Object?>> results = <Map<String, Object?>>[];
    for (final LocalTrainingFactWrite fact in write.localTrainingFacts) {
      _validateLocalTrainingWrite(fact);
      if (fact.workoutRow['athlete_profile_id'] != athleteId) {
        throw const FormatException('本地训练事实与 L1 计划运动员不一致。');
      }
      results.add(fact.scheduledWorkoutResultRow);
    }
    results.addAll(write.unmatchedScheduledResultRows);
    final Set<String> resultIds = <String>{};
    final Set<String> resultScheduledIds = <String>{};
    for (final Map<String, Object?> row in results) {
      final String? id = row['id'] as String?;
      if (id == null || id.trim().isEmpty || !resultIds.add(id)) {
        throw const FormatException('L1 判定 ID 为空或重复。');
      }
      if (row['athlete_profile_id'] != athleteId) {
        throw const FormatException('L1 判定与计划运动员不一致。');
      }
      final String? scheduledId = row['scheduled_workout_id'] as String?;
      if (scheduledId != null) {
        if (!scheduledIds.contains(scheduledId) ||
            !resultScheduledIds.add(scheduledId)) {
          throw const FormatException('L1 判定引用了无效或重复的计划项。');
        }
      }
      if (row['manual_override_status'] != null ||
          row['override_reason'] != null) {
        throw const FormatException('系统投影不得写入人工覆盖状态。');
      }
    }
    if (resultScheduledIds.length != scheduledIds.length ||
        !resultScheduledIds.containsAll(scheduledIds)) {
      throw const FormatException('每个 L1 计划项都必须保存一条系统判定。');
    }
  }
}

/// 在一个底层事务内保存本地训练事实及其 L1 判定。
///
/// 该协调器不计算业务结果，只校验应用层生成的行之间是否一致，确保任何一步
/// 失败时都不会留下孤立 workout、判定或力量组次。
class StructuredLocalTrainingCoordinator {
  const StructuredLocalTrainingCoordinator(this._driver);

  final StructuredStorageDriver _driver;

  Future<LocalTrainingFactWriteResult> apply(
    LocalTrainingFactWrite write,
  ) async {
    _validateLocalTrainingWrite(write);
    final String athleteId = write.workoutRow['athlete_profile_id']! as String;
    final String workoutId = write.workoutRow['id']! as String;
    final String resultId = write.scheduledWorkoutResultRow['id']! as String;
    return _driver.runStructuredTransaction<LocalTrainingFactWriteResult>(
      (StructuredStorageTransaction transaction) async {
        await transaction.upsertLocalWorkout(write.workoutRow);
        await transaction.upsertScheduledWorkoutResult(
          write.scheduledWorkoutResultRow,
        );
        await transaction.replaceStrengthSets(
          athleteId: athleteId,
          workoutId: workoutId,
          rows: write.strengthSetRows,
        );
        final List<Map<String, Object?>> violations =
            await transaction.foreignKeyCheck();
        if (violations.isNotEmpty) {
          throw StateError('本地训练事实写入后的外键校验失败。');
        }
        return LocalTrainingFactWriteResult(
          workoutId: workoutId,
          scheduledWorkoutResultId: resultId,
          strengthSetCount: write.strengthSetRows.length,
        );
      },
    );
  }
}

void _validateLocalTrainingWrite(LocalTrainingFactWrite write) {
  final Map<String, Object?> workout = write.workoutRow;
  final Map<String, Object?> result = write.scheduledWorkoutResultRow;
  final Object? athleteId = workout['athlete_profile_id'];
  final Object? workoutId = workout['id'];
  if (athleteId is! String || athleteId.trim().isEmpty) {
    throw const FormatException('本地训练事实缺少运动员资料 ID。');
  }
  if (workoutId is! String || workoutId.trim().isEmpty) {
    throw const FormatException('本地训练事实缺少 workout ID。');
  }
  if (workout['external_uuid'] != null) {
    throw const FormatException('本地训练事实不得伪造外部 UUID。');
  }
  if (result['athlete_profile_id'] != athleteId ||
      result['workout_id'] != workoutId) {
    throw const FormatException('L1 判定与本地训练事实的账号或 workout 不一致。');
  }
  if (result['id'] is! String || (result['id']! as String).trim().isEmpty) {
    throw const FormatException('L1 判定缺少结果 ID。');
  }
  if (result['matching_basis'] is! String ||
      (result['matching_basis']! as String).trim().isEmpty) {
    throw const FormatException('L1 判定缺少匹配依据。');
  }
  if (result['manual_override_status'] != null ||
      result['override_reason'] != null) {
    throw const FormatException('系统同步不得写入人工覆盖状态。');
  }
  for (final Map<String, Object?> row in write.strengthSetRows) {
    if (row['athlete_profile_id'] != athleteId ||
        row['workout_id'] != workoutId) {
      throw const FormatException('力量组次与本地训练事实的账号或 workout 不一致。');
    }
    if (row['rpe'] != null) {
      throw const FormatException('不得用整场 RPE 冒充单组 RPE。');
    }
  }
}

/// 在一个底层事务中应用 HealthKit 批次。
///
/// 锚点永远最后写入；任一步失败时，底层事务必须回滚事实、删除传播、失效记录、
/// 同步运行和锚点。
class StructuredHealthSyncCoordinator {
  const StructuredHealthSyncCoordinator(this._driver);

  final StructuredStorageDriver _driver;

  Future<HealthSyncApplyResult> apply(
    HealthSyncBatch batch, {
    String syncMode = 'background',
  }) async {
    _validateBatch(batch);
    final DateTime changedAt = batch.createdAt.toUtc();
    return _driver.runStructuredTransaction<HealthSyncApplyResult>(
      (StructuredStorageTransaction transaction) async {
        await transaction.beginSyncRun(<String, Object?>{
          'id': batch.batchId,
          'athlete_profile_id': batch.athleteId,
          'object_type': batch.objectType,
          'query_version': batch.queryVersion,
          'sync_mode': syncMode,
          'started_at': changedAt.toIso8601String(),
          'completed_at': null,
          'upsert_count': 0,
          'deleted_count': 0,
          'status': 'running',
          'error_message': null,
        });

        final Set<StructuredSourceReference> invalidated =
            <StructuredSourceReference>{};
        for (int index = 0; index < batch.upserts.length; index += 1) {
          final Map<String, Object?> raw = batch.upserts[index];
          final _StructuredRecordKind kind = _recordKind(batch, raw);
          if (kind == _StructuredRecordKind.route) {
            final List<StructuredSourceReference> affected =
                await transaction.markRoutePending(
              _routeRow(batch: batch, raw: raw),
            );
            invalidated.addAll(affected);
            continue;
          }

          final StructuredFactUpsertResult result =
              kind == _StructuredRecordKind.workout
                  ? await transaction.upsertWorkout(
                      _workoutRow(batch: batch, raw: raw),
                    )
                  : await transaction.upsertHealthObservation(
                      _observationRow(batch: batch, raw: raw),
                    );
          if (result.changedExistingFact) invalidated.add(result);
        }

        int deletedCount = 0;
        final bool routeBatch = _isRouteObjectType(batch.objectType);
        for (final String externalId
            in batch.deletedExternalIds.toSet().toList()..sort()) {
          if (externalId.trim().isEmpty) {
            throw const FormatException('健康数据删除对象缺少外部 UUID。');
          }
          final List<StructuredSourceReference> affected = routeBatch
              ? await transaction.markRouteDeleted(
                  athleteId: batch.athleteId,
                  routeExternalId: externalId,
                  deletedAt: changedAt,
                )
              : await transaction.markExternalIdDeleted(
                  athleteId: batch.athleteId,
                  externalId: externalId,
                  deletedAt: changedAt,
                );
          invalidated.addAll(affected);
          deletedCount += 1;
        }

        final List<StructuredSourceReference> orderedInvalidated = invalidated
            .toList()
          ..sort((StructuredSourceReference first,
                  StructuredSourceReference second) =>
              '${first.sourceType}\u0000${first.sourceId}'.compareTo(
                '${second.sourceType}\u0000${second.sourceId}',
              ));
        for (final StructuredSourceReference source in orderedInvalidated) {
          await transaction.invalidateSource(
            athleteId: batch.athleteId,
            source: source,
            invalidatedAt: changedAt,
          );
        }

        await transaction.completeSyncRun(<String, Object?>{
          'id': batch.batchId,
          'completed_at': changedAt.toIso8601String(),
          'upsert_count': batch.upserts.length,
          'deleted_count': deletedCount,
          'status': 'completed',
          'error_message': null,
        });
        final String? nextAnchor = batch.nextAnchor;
        if (nextAnchor != null && nextAnchor.isNotEmpty) {
          await transaction.commitAnchor(<String, Object?>{
            'athlete_profile_id': batch.athleteId,
            'object_type': batch.objectType,
            'query_version': batch.queryVersion,
            'anchor_payload': nextAnchor,
            'committed_at': changedAt.toIso8601String(),
          });
        }
        final DateTime? coverageStart = batch.coverageStart;
        final DateTime? coverageEnd = batch.coverageEnd;
        if (coverageStart != null && coverageEnd != null) {
          if (!coverageStart.isBefore(coverageEnd)) {
            throw const FormatException('健康数据覆盖范围无效。');
          }
          final String coverageObjectType = 'coverage:${batch.objectType}';
          final Map<String, Object?>? existingCoverage =
              await transaction.readAnchor(
            athleteId: batch.athleteId,
            objectType: coverageObjectType,
            queryVersion: batch.queryVersion,
          );
          final _HealthCoverageRange mergedCoverage = _mergeCoverageRange(
            existingPayload: existingCoverage?['anchor_payload'],
            incomingStart: coverageStart,
            incomingEnd: coverageEnd,
          );
          await transaction.commitAnchor(<String, Object?>{
            'athlete_profile_id': batch.athleteId,
            'object_type': coverageObjectType,
            'query_version': batch.queryVersion,
            'anchor_payload': jsonEncode(<String, Object?>{
              'start': mergedCoverage.start.toIso8601String(),
              'end': mergedCoverage.end.toIso8601String(),
            }),
            'committed_at': changedAt.toIso8601String(),
          });
        }

        return HealthSyncApplyResult(
          batchId: batch.batchId,
          upsertCount: batch.upserts.length,
          deletedCount: deletedCount,
          invalidatedSourceIds: List<String>.unmodifiable(
            orderedInvalidated
                .map((StructuredSourceReference source) => source.sourceId),
          ),
          invalidatedSources:
              List<StructuredSourceReference>.unmodifiable(orderedInvalidated),
        );
      },
    );
  }

  Future<void> clearAthleteData(String athleteId) async {
    if (athleteId.trim().isEmpty) {
      throw ArgumentError.value(athleteId, 'athleteId', '运动员标识不能为空');
    }
    await _driver.runStructuredTransaction<void>(
      (StructuredStorageTransaction transaction) async {
        await transaction.clearAthleteData(athleteId);
        final List<Map<String, Object?>> violations =
            await transaction.foreignKeyCheck();
        if (violations.isNotEmpty) {
          throw StateError('清理运动员结构化数据后的外键校验失败。');
        }
      },
    );
  }
}

class _HealthCoverageRange {
  const _HealthCoverageRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

_HealthCoverageRange _mergeCoverageRange({
  required Object? existingPayload,
  required DateTime incomingStart,
  required DateTime incomingEnd,
}) {
  DateTime start = incomingStart.toUtc();
  DateTime end = incomingEnd.toUtc();
  try {
    final Object? decoded = existingPayload is String
        ? jsonDecode(existingPayload)
        : existingPayload;
    if (decoded is Map) {
      final Map<String, Object?> value = Map<String, Object?>.from(decoded);
      final DateTime? existingStart =
          DateTime.tryParse(value['start'] as String? ?? '')?.toUtc();
      final DateTime? existingEnd =
          DateTime.tryParse(value['end'] as String? ?? '')?.toUtc();
      if (existingStart != null && existingStart.isBefore(start)) {
        start = existingStart;
      }
      if (existingEnd != null && existingEnd.isAfter(end)) {
        end = existingEnd;
      }
    }
  } catch (_) {
    // 旧覆盖载荷不可解析时不沿用，使用本次已验证的覆盖范围安全重建。
  }
  return _HealthCoverageRange(start: start, end: end);
}

enum _StructuredRecordKind { workout, observation, route }

_StructuredRecordKind _recordKind(
  HealthSyncBatch batch,
  Map<String, Object?> raw,
) {
  final String kind = (raw['kind'] as String? ?? '').toLowerCase();
  if (kind == 'workoutroute' || _isRouteObjectType(batch.objectType)) {
    return _StructuredRecordKind.route;
  }
  if (kind == 'workout' ||
      batch.objectType.toLowerCase().contains('workouttypeidentifier')) {
    return _StructuredRecordKind.workout;
  }
  if (kind == 'observation' || kind == 'category' || raw['value'] is num) {
    return _StructuredRecordKind.observation;
  }
  throw FormatException('不支持的健康数据记录类型：${raw['kind'] ?? batch.objectType}');
}

bool _isRouteObjectType(String objectType) =>
    objectType.toLowerCase().contains('workoutroute');

void _validateBatch(HealthSyncBatch batch) {
  if (batch.batchId.trim().isEmpty) {
    throw const FormatException('健康数据批次标识不能为空。');
  }
  if (batch.athleteId.trim().isEmpty) {
    throw const FormatException('健康数据批次缺少运动员标识。');
  }
  if (batch.objectType.trim().isEmpty) {
    throw const FormatException('健康数据批次缺少对象类型。');
  }
  if (batch.queryVersion <= 0) {
    throw const FormatException('健康数据查询版本必须为正整数。');
  }
}

Map<String, Object?> _workoutRow({
  required HealthSyncBatch batch,
  required Map<String, Object?> raw,
}) {
  final String externalUuid = _requiredExternalUuid(raw);
  final DateTime startedAt = _requiredInstant(raw, 'startTime', '训练开始时间');
  final DateTime endedAt = _requiredInstant(raw, 'endTime', '训练结束时间');
  if (endedAt.isBefore(startedAt)) {
    throw const FormatException('健康训练结束时间不能早于开始时间。');
  }
  final String sourceBundleId = (raw['sourceBundleId'] as String? ?? '').trim();
  final int offsetMinutes = _integer(raw['timeZoneOffsetMinutes']) ?? 0;
  final DateTime localStartedAt =
      startedAt.toUtc().add(Duration(minutes: offsetMinutes));
  final int elapsedSeconds = _integer(raw['durationSeconds']) ??
      endedAt.difference(startedAt).inSeconds;
  final _HeartRateIngestSummary heartRateSummary = _summarizeHeartRateSamples(
    raw['heartRateSamples'],
    workoutStart: startedAt,
    workoutEnd: endedAt,
  );
  final _RouteIngestSummary routeSummary = _summarizeRoutes(raw['routes']);
  final Map<String, Object?> safePayload =
      Map<String, Object?>.from(_withoutRawHealthDetails(raw) as Map)
        ..['heartRateSummary'] = heartRateSummary.toMap()
        ..['routeSummary'] = routeSummary.toMap();
  final bool suppliedHeartRateSamples = raw.containsKey('heartRateSamples');
  final bool suppliedRoutes = raw.containsKey('routes');
  final String timestamp = batch.createdAt.toUtc().toIso8601String();
  return <String, Object?>{
    'id': _factId('workout', batch.athleteId, sourceBundleId, externalUuid),
    'athlete_profile_id': batch.athleteId,
    'external_uuid': externalUuid,
    'source_bundle_id': sourceBundleId,
    'source_product_type': raw['deviceModel'] as String?,
    'source_kind': 'healthKit',
    'discipline': raw['discipline'] as String? ?? 'other',
    'run_context': raw['runContext'] as String?,
    'started_at_utc': startedAt.toUtc().toIso8601String(),
    'ended_at_utc': endedAt.toUtc().toIso8601String(),
    'local_date': _dateKey(localStartedAt),
    'time_zone_name': raw['timeZoneName'] as String? ?? 'UTC',
    'utc_offset_minutes': offsetMinutes,
    'active_duration_seconds': _integer(raw['activeDurationSeconds']),
    'elapsed_duration_seconds': elapsedSeconds,
    'distance_meters':
        _number(raw['totalDistanceMeters']) ?? routeSummary.distanceMeters,
    'energy_kcal': _number(raw['totalEnergyKilocalories']),
    'elevation_gain_meters':
        _number(raw['elevationGainMeters']) ?? routeSummary.elevationGainMeters,
    'average_heart_rate': suppliedHeartRateSamples
        ? heartRateSummary.averageHeartRate
        : _number(raw['averageHeartRate']),
    'maximum_heart_rate': suppliedHeartRateSamples
        ? heartRateSummary.maximumHeartRate
        : _number(raw['maximumHeartRate']),
    'heart_rate_sample_count': suppliedHeartRateSamples
        ? heartRateSummary.rawSampleCount
        : _integer(raw['heartRateSampleCount']) ?? 0,
    'heart_rate_coverage': suppliedHeartRateSamples
        ? heartRateSummary.coverage
        : _number(raw['heartRateCoverage']) ?? 0.0,
    'route_status':
        suppliedRoutes ? routeSummary.status : raw['routeStatus'] as String?,
    'route_external_uuid': suppliedRoutes
        ? routeSummary.primaryRouteExternalUuid
        : raw['routeExternalUuid'] as String?,
    'payload_json': _canonicalJson(safePayload),
    'source_deleted_at': null,
    'created_at': timestamp,
    'updated_at': timestamp,
  };
}

Map<String, Object?> _observationRow({
  required HealthSyncBatch batch,
  required Map<String, Object?> raw,
}) {
  final String externalUuid = _requiredExternalUuid(raw);
  final DateTime observedAt = _requiredInstant(raw, 'startTime', '健康样本时间');
  final num? rawValue = raw['value'] as num?;
  if (rawValue == null || !rawValue.toDouble().isFinite) {
    throw const FormatException('健康样本缺少有效数值。');
  }
  final String sourceBundleId = (raw['sourceBundleId'] as String? ?? '').trim();
  final int offsetMinutes = _integer(raw['timeZoneOffsetMinutes']) ?? 0;
  final DateTime localObservedAt =
      observedAt.toUtc().add(Duration(minutes: offsetMinutes));
  final String timestamp = batch.createdAt.toUtc().toIso8601String();
  return <String, Object?>{
    'id': _factId('observation', batch.athleteId, sourceBundleId, externalUuid),
    'athlete_profile_id': batch.athleteId,
    'external_uuid': externalUuid,
    'source_bundle_id': sourceBundleId,
    'observation_kind': raw['healthKitType'] as String? ?? batch.objectType,
    'observed_at_utc': observedAt.toUtc().toIso8601String(),
    'local_date': _dateKey(localObservedAt),
    'time_zone_name': raw['timeZoneName'] as String? ?? 'UTC',
    'value': rawValue.toDouble(),
    'unit': raw['unit'] as String? ?? '',
    'payload_json': _canonicalJson(raw),
    'source_deleted_at': null,
    'created_at': timestamp,
    'updated_at': timestamp,
  };
}

Map<String, Object?> _routeRow({
  required HealthSyncBatch batch,
  required Map<String, Object?> raw,
}) {
  return <String, Object?>{
    'athlete_profile_id': batch.athleteId,
    'external_uuid': _requiredExternalUuid(raw),
    'source_bundle_id': raw['sourceBundleId'] as String? ?? '',
    'started_at_utc':
        _requiredInstant(raw, 'startTime', '路线开始时间').toIso8601String(),
    'ended_at_utc':
        _requiredInstant(raw, 'endTime', '路线结束时间').toIso8601String(),
    'payload_json': _canonicalJson(raw),
    'updated_at': batch.createdAt.toUtc().toIso8601String(),
  };
}

String _requiredExternalUuid(Map<String, Object?> raw) {
  final String value = (raw['uuid'] as String? ?? '').trim();
  if (value.isEmpty) throw const FormatException('健康数据记录缺少外部 UUID。');
  return value;
}

DateTime _requiredInstant(
  Map<String, Object?> raw,
  String key,
  String label,
) {
  final Object? value = raw[key];
  final DateTime? parsed = switch (value) {
    num milliseconds => DateTime.fromMillisecondsSinceEpoch(
        milliseconds.round(),
        isUtc: true,
      ),
    String text => DateTime.tryParse(text)?.toUtc(),
    _ => null,
  };
  if (parsed == null) throw FormatException('$label无效。');
  return parsed;
}

int? _integer(Object? value) => value is num ? value.round() : null;

double? _number(Object? value) {
  if (value is! num) return null;
  final double result = value.toDouble();
  return result.isFinite ? result : null;
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _factId(
  String prefix,
  String athleteId,
  String sourceBundleId,
  String externalUuid,
) {
  final String encoded = base64Url
      .encode(utf8.encode('$athleteId\u0000$sourceBundleId\u0000$externalUuid'))
      .replaceAll('=', '');
  return '$prefix:$encoded';
}

String _canonicalJson(Map<String, Object?> value) =>
    jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalValue(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map<Object?>(_canonicalValue).toList(growable: false);
  }
  return value;
}

const double _minimumValidHeartRate = 30;
const double _maximumValidHeartRate = 240;
const int _maximumHeartRateSupportGapSeconds = 10;
const double _maximumHorizontalAccuracyMeters = 50;
const double _maximumVerticalAccuracyMeters = 30;
const int _maximumRoutePointGapSeconds = 30;

class _HeartRateIngestSummary {
  const _HeartRateIngestSummary({
    required this.rawSampleCount,
    required this.validSampleCount,
    required this.rejectedSampleCount,
    required this.supportedDurationSeconds,
    required this.coverage,
    required this.averageHeartRate,
    required this.maximumHeartRate,
  });

  final int rawSampleCount;
  final int validSampleCount;
  final int rejectedSampleCount;
  final int supportedDurationSeconds;
  final double coverage;
  final double? averageHeartRate;
  final double? maximumHeartRate;

  Map<String, Object?> toMap() => <String, Object?>{
        'algorithmVersion': 'health-ingest-summary-v1',
        'rawSampleCount': rawSampleCount,
        'validSampleCount': validSampleCount,
        'rejectedSampleCount': rejectedSampleCount,
        'supportedDurationSeconds': supportedDurationSeconds,
        'coverage': coverage,
        'averageHeartRate': averageHeartRate,
        'maximumHeartRate': maximumHeartRate,
        'validRangeBpm': <String, Object?>{
          'minimum': _minimumValidHeartRate,
          'maximum': _maximumValidHeartRate,
        },
        'maximumSupportGapSeconds': _maximumHeartRateSupportGapSeconds,
      };
}

class _TimedHeartRate {
  const _TimedHeartRate(this.timestamp, this.bpm);

  final DateTime timestamp;
  final double bpm;
}

_HeartRateIngestSummary _summarizeHeartRateSamples(
  Object? rawSamples, {
  required DateTime workoutStart,
  required DateTime workoutEnd,
}) {
  final List<Object?> samples =
      rawSamples is List ? List<Object?>.from(rawSamples) : const <Object?>[];
  final List<_TimedHeartRate> valid = <_TimedHeartRate>[];
  for (final Object? rawSample in samples) {
    if (rawSample is! Map) continue;
    final Map<String, Object?> sample = Map<String, Object?>.from(rawSample);
    final double? bpm = _number(sample['value'] ?? sample['bpm']);
    final DateTime? timestamp = _optionalInstant(
      sample['startTime'] ?? sample['timestamp'],
    );
    if (bpm == null ||
        bpm < _minimumValidHeartRate ||
        bpm > _maximumValidHeartRate ||
        timestamp == null ||
        timestamp.isBefore(workoutStart) ||
        timestamp.isAfter(workoutEnd)) {
      continue;
    }
    valid.add(_TimedHeartRate(timestamp, bpm));
  }
  valid.sort((_TimedHeartRate first, _TimedHeartRate second) =>
      first.timestamp.compareTo(second.timestamp));

  int supportedSeconds = 0;
  for (int index = 1; index < valid.length; index += 1) {
    final int gap =
        valid[index].timestamp.difference(valid[index - 1].timestamp).inSeconds;
    if (gap > 0 && gap <= _maximumHeartRateSupportGapSeconds) {
      supportedSeconds += gap;
    }
  }
  final int workoutDurationSeconds =
      math.max(0, workoutEnd.difference(workoutStart).inSeconds);
  final double coverage = workoutDurationSeconds == 0
      ? 0
      : (supportedSeconds / workoutDurationSeconds).clamp(0.0, 1.0).toDouble();
  final double? average = valid.isEmpty
      ? null
      : valid.fold<double>(
              0, (double sum, _TimedHeartRate item) => sum + item.bpm) /
          valid.length;
  final double? maximum = valid.isEmpty
      ? null
      : valid.map((_TimedHeartRate item) => item.bpm).reduce(math.max);
  return _HeartRateIngestSummary(
    rawSampleCount: samples.length,
    validSampleCount: valid.length,
    rejectedSampleCount: samples.length - valid.length,
    supportedDurationSeconds: supportedSeconds,
    coverage: coverage,
    averageHeartRate: average,
    maximumHeartRate: maximum,
  );
}

class _RouteIngestSummary {
  const _RouteIngestSummary({
    required this.status,
    required this.routeExternalUuids,
    required this.rawLocationCount,
    required this.validLocationCount,
    required this.distanceMeters,
    required this.elevationGainMeters,
  });

  final String status;
  final List<String> routeExternalUuids;
  final int rawLocationCount;
  final int validLocationCount;
  final double? distanceMeters;
  final double? elevationGainMeters;

  String? get primaryRouteExternalUuid =>
      routeExternalUuids.isEmpty ? null : routeExternalUuids.first;

  Map<String, Object?> toMap() => <String, Object?>{
        'algorithmVersion': 'health-ingest-summary-v1',
        'status': status,
        'routeCount': routeExternalUuids.length,
        'routeExternalUuids': routeExternalUuids,
        'rawLocationCount': rawLocationCount,
        'validLocationCount': validLocationCount,
        'distanceMeters': distanceMeters,
        'elevationGainMeters': elevationGainMeters,
        'maximumHorizontalAccuracyMeters': _maximumHorizontalAccuracyMeters,
        'maximumVerticalAccuracyMeters': _maximumVerticalAccuracyMeters,
        'maximumPointGapSeconds': _maximumRoutePointGapSeconds,
      };
}

class _RoutePoint {
  const _RoutePoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.verticalAccuracy,
  });

  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? verticalAccuracy;

  bool get hasValidElevation =>
      altitude != null &&
      verticalAccuracy != null &&
      verticalAccuracy! >= 0 &&
      verticalAccuracy! <= _maximumVerticalAccuracyMeters;
}

_RouteIngestSummary _summarizeRoutes(Object? rawRoutes) {
  final List<Object?> routes =
      rawRoutes is List ? List<Object?>.from(rawRoutes) : const <Object?>[];
  final Set<String> routeExternalUuids = <String>{};
  int rawLocationCount = 0;
  int validLocationCount = 0;
  double distanceMeters = 0;
  double elevationGainMeters = 0;
  int distanceSegmentCount = 0;
  int elevationSegmentCount = 0;

  for (final Object? rawRoute in routes) {
    if (rawRoute is! Map) continue;
    final Map<String, Object?> route = Map<String, Object?>.from(rawRoute);
    final String routeUuid = (route['uuid'] as String? ?? '').trim();
    if (routeUuid.isNotEmpty) routeExternalUuids.add(routeUuid);
    final List<Object?> locations = route['locations'] is List
        ? List<Object?>.from(route['locations']! as List)
        : const <Object?>[];
    rawLocationCount += locations.length;
    final List<_RoutePoint> validPoints = <_RoutePoint>[];
    for (final Object? rawLocation in locations) {
      if (rawLocation is! Map) continue;
      final Map<String, Object?> location =
          Map<String, Object?>.from(rawLocation);
      final double? latitude = _number(location['latitude']);
      final double? longitude = _number(location['longitude']);
      final double? horizontalAccuracy =
          _number(location['horizontalAccuracy']);
      final DateTime? timestamp = _optionalInstant(location['timestamp']);
      if (latitude == null ||
          longitude == null ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180 ||
          horizontalAccuracy == null ||
          horizontalAccuracy < 0 ||
          horizontalAccuracy > _maximumHorizontalAccuracyMeters ||
          timestamp == null) {
        continue;
      }
      validPoints.add(
        _RoutePoint(
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
          altitude: _number(location['altitude']),
          verticalAccuracy: _number(location['verticalAccuracy']),
        ),
      );
    }
    validPoints.sort((_RoutePoint first, _RoutePoint second) =>
        first.timestamp.compareTo(second.timestamp));
    validLocationCount += validPoints.length;
    for (int index = 1; index < validPoints.length; index += 1) {
      final _RoutePoint previous = validPoints[index - 1];
      final _RoutePoint current = validPoints[index];
      final int gap =
          current.timestamp.difference(previous.timestamp).inSeconds;
      if (gap <= 0 || gap > _maximumRoutePointGapSeconds) continue;
      distanceMeters += _haversineMeters(previous, current);
      distanceSegmentCount += 1;
      if (previous.hasValidElevation && current.hasValidElevation) {
        final double gain = current.altitude! - previous.altitude!;
        if (gain > 0) elevationGainMeters += gain;
        elevationSegmentCount += 1;
      }
    }
  }

  final List<String> orderedUuids = routeExternalUuids.toList()..sort();
  return _RouteIngestSummary(
    status: orderedUuids.isEmpty ? 'unavailable' : 'available',
    routeExternalUuids: List<String>.unmodifiable(orderedUuids),
    rawLocationCount: rawLocationCount,
    validLocationCount: validLocationCount,
    distanceMeters: distanceSegmentCount == 0 ? null : distanceMeters,
    elevationGainMeters:
        elevationSegmentCount == 0 ? null : elevationGainMeters,
  );
}

double _haversineMeters(_RoutePoint first, _RoutePoint second) {
  const double earthRadiusMeters = 6371000;
  final double latitudeDelta = _radians(second.latitude - first.latitude);
  final double longitudeDelta = _radians(second.longitude - first.longitude);
  final double firstLatitude = _radians(first.latitude);
  final double secondLatitude = _radians(second.latitude);
  final double a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(firstLatitude) *
          math.cos(secondLatitude) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180;

DateTime? _optionalInstant(Object? value) => switch (value) {
      num milliseconds => DateTime.fromMillisecondsSinceEpoch(
          milliseconds.round(),
          isUtc: true,
        ),
      String text => DateTime.tryParse(text)?.toUtc(),
      _ => null,
    };

Object? _withoutRawHealthDetails(Object? value) {
  if (value is Map) {
    const Set<String> forbiddenKeys = <String>{
      'heartRateSamples',
      'routes',
      'locations',
      'latitude',
      'longitude',
      'altitude',
      'speed',
      'horizontalAccuracy',
      'verticalAccuracy',
      'speedAccuracy',
    };
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (!forbiddenKeys.contains('${entry.key}'))
          '${entry.key}': _withoutRawHealthDetails(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map<Object?>(_withoutRawHealthDetails).toList(growable: false);
  }
  return value;
}
