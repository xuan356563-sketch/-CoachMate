import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/cloud_sync.dart';

void main() {
  test('云同步稳定实体 ID 保持既有 64 位指纹结果', () {
    expect(
      stableCloudSyncEntityId('workout', 'local-1'),
      '78dccd87-d421-5b9f-925c-e09d4e1bcaeb',
    );
    expect(
      stableCloudSyncEntityId('training_log', '日志-001'),
      '112733ee-3dd5-5552-a5f3-dde073aeaa4c',
    );
  });
}
