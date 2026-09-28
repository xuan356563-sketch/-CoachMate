import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:trainflow_ai/data/local/trainflow_database_schema.dart';
import 'package:trainflow_ai/plugins/settings/plugin_settings.dart';

void main() {
  test('SQLite legacy_documents 原样持久化v1账号级功能设置', () async {
    final ProcessResult lookup =
        await Process.run('which', <String>['sqlite3']);
    if (lookup.exitCode != 0) return;
    final String executable = (lookup.stdout as String).trim();
    final Directory directory =
        await Directory.systemTemp.createTemp('trainmate-plugin-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final String databasePath = p.join(directory.path, 'trainflow.db');
    final Process process =
        await Process.start(executable, <String>[databasePath]);
    process.stdin.writeln('.bail on');
    for (final String statement in TrainFlowDatabaseSchema.creationStatements) {
      process.stdin.writeln('$statement;');
    }
    process.stdin.writeln('''
INSERT INTO legacy_documents(storage_key, payload_json, migrated_at, updated_at)
VALUES(
  '$pluginSettingsStorageKey',
  '{"version":1,"enabledOverrides":{"feature.motion_check":false}}',
  '2026-09-04T00:00:00.000Z',
  '2026-09-04T00:00:00.000Z'
);
SELECT storage_key || '|' || payload_json FROM legacy_documents
WHERE storage_key = '$pluginSettingsStorageKey';
''');
    await process.stdin.close();
    final String stdout =
        await process.stdout.transform(const SystemEncoding().decoder).join();
    final String stderr =
        await process.stderr.transform(const SystemEncoding().decoder).join();
    final int exitCode = await process.exitCode;

    expect(exitCode, 0, reason: stderr);
    expect(stderr, isEmpty);
    expect(
      stdout.trim(),
      '$pluginSettingsStorageKey|'
      '{"version":1,"enabledOverrides":{"feature.motion_check":false}}',
    );
  });
}
