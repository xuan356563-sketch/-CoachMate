import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:trainflow_ai/data/local/sqflite_companion_database_gateway.dart';

void main() {
  test('搭子关系接受 YYYY-MM-DD 日期并进入数据库写入边界', () async {
    final _RecordingDatabase database = _RecordingDatabase();
    final SqfliteCompanionDatabaseGateway gateway =
        SqfliteCompanionDatabaseGateway(database);

    await gateway.upsertRelationshipRow(<String, Object?>{
      'athlete_profile_id': 'athlete-1',
      'companion_name': null,
      'started_on': '2026-08-12',
      'created_at': '2026-08-12T16:00:00.000Z',
      'updated_at': '2026-08-12T16:00:00.000Z',
    });

    expect(database.insertedTable, 'companion_relationship');
    expect(database.insertedValues?['started_on'], '2026-08-12');
    expect(database.conflictAlgorithm, ConflictAlgorithm.replace);
  });
}

class _RecordingDatabase implements Database {
  String? insertedTable;
  Map<String, Object?>? insertedValues;
  ConflictAlgorithm? conflictAlgorithm;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #insert) {
      insertedTable = invocation.positionalArguments[0] as String;
      insertedValues = Map<String, Object?>.from(
        invocation.positionalArguments[1] as Map,
      );
      conflictAlgorithm = invocation.namedArguments[#conflictAlgorithm]
          as ConflictAlgorithm?;
      return Future<int>.value(1);
    }
    return super.noSuchMethod(invocation);
  }
}
