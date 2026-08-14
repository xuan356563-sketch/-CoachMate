import 'dart:convert';

import 'package:trainflow_ai/data/local/athlete_profile_projection.dart';
import 'package:trainflow_ai/data/local/trainflow_database_gateway.dart';
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

class LegacyMigrationResult {
  const LegacyMigrationResult({
    required this.migratedDocumentCount,
    required this.wasAlreadyCompleted,
  });

  final int migratedDocumentCount;
  final bool wasAlreadyCompleted;
}

class LegacyStorageMigrator {
  LegacyStorageMigrator({
    required this.legacyStorage,
    required this.database,
    required Iterable<String> storageKeys,
    DateTime Function()? clock,
  })  : storageKeys = Set<String>.unmodifiable(storageKeys),
        _clock = clock ?? DateTime.now;

  static const String migrationId = 'shared_preferences_to_sqlite_v1';
  static const int migrationVersion = 3;

  final LocalStorageService legacyStorage;
  final TrainFlowDatabaseGateway database;
  final Set<String> storageKeys;
  final DateTime Function() _clock;

  Future<LegacyMigrationResult> migrate() {
    return database.transaction<LegacyMigrationResult>(
      (TrainFlowDatabaseTransaction transaction) async {
        final MigrationCheckpoint? checkpoint =
            await transaction.readMigrationCheckpoint(migrationId);
        if (checkpoint != null && checkpoint.version >= migrationVersion) {
          final DateTime checkedAt = _clock().toUtc();
          await transaction.upsertAthleteProfileRow(
            AthleteProfileProjection.fromLegacyDocument(
              await transaction.readLegacyDocument(
                'trainflow.user_profile.v1',
              ),
              projectedAt: checkedAt,
            ),
          );
          await transaction.markStorageCutover(
            schemaVersion: TrainFlowDatabaseSchema.version,
            completedAt: checkedAt,
          );
          return LegacyMigrationResult(
            migratedDocumentCount: checkpoint.migratedDocumentCount,
            wasAlreadyCompleted: true,
          );
        }

        final Map<String, Map<String, dynamic>> sourceDocuments =
            <String, Map<String, dynamic>>{};
        for (final String key in storageKeys) {
          final Map<String, dynamic>? value = legacyStorage.readJson(key);
          if (value != null) {
            sourceDocuments[key] = _copyJsonMap(value);
          }
        }

        final DateTime migratedAt = _clock().toUtc();
        final Map<String, Object?> athleteProfileRow =
            AthleteProfileProjection.fromLegacyDocument(
          sourceDocuments['trainflow.user_profile.v1'],
          projectedAt: migratedAt,
        );
        for (final MapEntry<String, Map<String, dynamic>> entry
            in sourceDocuments.entries) {
          await transaction.upsertLegacyDocument(
            entry.key,
            entry.value,
            migratedAt,
          );
        }
        await transaction.upsertAthleteProfileRow(athleteProfileRow);

        for (final MapEntry<String, Map<String, dynamic>> entry
            in sourceDocuments.entries) {
          final Map<String, dynamic>? migrated =
              await transaction.readLegacyDocument(entry.key);
          if (migrated == null ||
              _canonicalJson(migrated) != _canonicalJson(entry.value)) {
            throw StateError('旧数据迁移校验失败：${entry.key}');
          }
        }

        await transaction.markMigrationCompleted(
          MigrationCheckpoint(
            migrationId: migrationId,
            version: migrationVersion,
            sourceDocumentCount: sourceDocuments.length,
            migratedDocumentCount: sourceDocuments.length,
            completedAt: migratedAt,
          ),
        );
        await transaction.markStorageCutover(
          schemaVersion: TrainFlowDatabaseSchema.version,
          completedAt: migratedAt,
        );

        return LegacyMigrationResult(
          migratedDocumentCount: sourceDocuments.length,
          wasAlreadyCompleted: false,
        );
      },
    );
  }
}

Map<String, dynamic> _copyJsonMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.from(
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>,
  );
}

String _canonicalJson(Map<String, dynamic> source) {
  return jsonEncode(_normalizeJson(source));
}

Object? _normalizeJson(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    return <String, Object?>{
      for (final String key in keys) key: _normalizeJson(value[key]),
    };
  }
  if (value is List) {
    return value.map<Object?>(_normalizeJson).toList(growable: false);
  }
  return value;
}
