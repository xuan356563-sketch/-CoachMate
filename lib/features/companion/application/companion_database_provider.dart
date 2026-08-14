import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/data/local/companion_database_gateway.dart';
import 'package:trainflow_ai/data/local/coach_database_gateway.dart';

/// 启动层仅在 SQLite v7 成功打开后覆盖；Web 与只读恢复模式保持为空。
final companionDatabaseGatewayProvider = Provider<CompanionDatabaseGateway?>(
  (Ref ref) => null,
);

/// SQLite v8 成功打开后才提供；只读恢复和 Web 环境保持为空。
final coachDatabaseGatewayProvider = Provider<CoachDatabaseGateway?>(
  (Ref ref) => null,
);
