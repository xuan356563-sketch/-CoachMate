import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:trainflow_ai/data/local/coach_database_gateway.dart';
import 'package:trainflow_ai/data/local/companion_database_gateway.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/features/companion/application/coach_remote_coordinator.dart';
import 'package:trainflow_ai/features/companion/application/companion_controller.dart';
import 'package:trainflow_ai/features/companion/application/companion_database_provider.dart';
import 'package:trainflow_ai/features/companion/data/coach_api.dart';
import 'package:trainflow_ai/features/companion/data/companion_repository.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

void main() {
  late timezone.Location location;

  setUpAll(() {
    timezone_data.initializeTimeZones();
    location = timezone.getLocation('America/Los_Angeles');
  });

  test('伙伴远端结果迟到时不写回复、trace或重新安排通知', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final DateTime now = DateTime.utc(2026, 9, 4, 8);
    final _MemoryCompanionGateway companion = _MemoryCompanionGateway();
    await CompanionRepository(companion, clock: () => now).saveRelationship(
      CompanionRelationship(
        athleteProfileId: 'athlete-a',
        startedOn: now.subtract(const Duration(days: 20)),
        notificationsEnabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final _MemoryCoachGateway coach = _MemoryCoachGateway();
    final _DeferredCoachClient remote = _DeferredCoachClient();
    final _NotificationGateway notifications = _NotificationGateway(location);
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService()
      ..saveJson(coachCloudConsentStorageKey, <String, dynamic>{
        'granted': true,
      });
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      companionClockProvider.overrideWithValue(() => now),
      companionDatabaseGatewayProvider.overrideWithValue(companion),
      coachDatabaseGatewayProvider.overrideWithValue(coach),
      petControllerProvider.overrideWith(_ReadyPetController.new),
      coachCloudModeProvider.overrideWithValue(CoachCloudMode.shadow),
      coachApiProvider.overrideWithValue(CoachApi.forClient(remote)),
      companionNotificationSchedulerProvider.overrideWithValue(
        CompanionNotificationScheduler(notifications),
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(petControllerProvider.future);
    await container.read(companionControllerProvider.future);
    final ProviderSubscription<AsyncValue<CompanionFeedState>> keepAlive =
        container.listen(companionControllerProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await _waitFor(
        '初始就绪',
        () =>
            container.read(companionControllerProvider).value?.status ==
            CompanionFeedStatus.ready);

    final Future<void> pending = container
        .read(companionControllerProvider.notifier)
        .sendUserMessage('今天训练怎么安排');
    await remote.called.future;
    final int messagesBeforeDisable = companion.messages.length;
    expect(
      companion.messages.values
          .where((Map<String, Object?> row) => row['message_role'] == 'user'),
      hasLength(1),
    );
    expect(coach.traces, isEmpty);

    await runtime.disable('feature.companion');
    expect(notifications.requests, isEmpty);
    remote.response.complete(_remoteEnvelope(remote.lastPostBody!));

    await expectLater(pending, throwsStateError);
    expect(companion.messages, hasLength(messagesBeforeDisable));
    expect(
      companion.messages.values.any(
        (Map<String, Object?> row) => row['body'] == '这是一条迟到伙伴回复',
      ),
      isFalse,
    );
    expect(coach.traces, isEmpty);
    expect(notifications.requests, isEmpty);
  });

  test('伙伴停用清理训练订阅，再启用只恢复一份且不生成新消息', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final DateTime now = DateTime.utc(2026, 9, 4, 8);
    final _MemoryCompanionGateway companion = _MemoryCompanionGateway();
    await CompanionRepository(companion, clock: () => now).saveRelationship(
      CompanionRelationship(
        athleteProfileId: 'athlete-a',
        startedOn: now.subtract(const Duration(days: 20)),
        notificationsEnabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final _NotificationGateway notifications = _NotificationGateway(location);
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      companionClockProvider.overrideWithValue(() => now),
      companionDatabaseGatewayProvider.overrideWithValue(companion),
      coachDatabaseGatewayProvider.overrideWithValue(_MemoryCoachGateway()),
      petControllerProvider.overrideWith(_ReadyPetController.new),
      coachCloudModeProvider.overrideWithValue(CoachCloudMode.disabled),
      companionNotificationSchedulerProvider.overrideWithValue(
        CompanionNotificationScheduler(notifications),
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(petControllerProvider.future);
    await container.read(companionControllerProvider.future);
    final ProviderSubscription<AsyncValue<CompanionFeedState>> keepAlive =
        container.listen(companionControllerProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await _waitFor(
        '第二个测试初始就绪',
        () =>
            container.read(companionControllerProvider).value?.status ==
            CompanionFeedStatus.ready);

    final int messagesBeforePause = companion.messages.length;
    await runtime.disable('feature.companion');
    await container.pump();
    await runtime.enable('feature.companion');
    await container.pump();
    await container.read(companionControllerProvider.future);
    await _waitFor(
        '首次恢复就绪',
        () =>
            container.read(companionControllerProvider).value?.status ==
            CompanionFeedStatus.ready);
    await _pumpEvents();
    expect(companion.messages, hasLength(messagesBeforePause));

    notifications.loadCount = 0;
    await container.read(trainingLogControllerProvider.notifier).save(
          TrainingLog(
            id: 'log-1',
            workoutDayId: 'day-1',
            date: now,
            createdAt: now,
            completed: true,
            rpe: 5,
            fatigueLevel: 4,
            sleepQuality: 7,
            painNote: null,
            userNote: null,
          ),
        );
    await _waitFor('首次日志通知', () => notifications.loadCount > 0);
    expect(notifications.loadCount, 1);

    await runtime.disable('feature.companion');
    await container.pump();
    await runtime.enable('feature.companion');
    await container.pump();
    await container.read(companionControllerProvider.future);
    await _waitFor(
        '第二次恢复就绪',
        () =>
            container.read(companionControllerProvider).value?.status ==
            CompanionFeedStatus.ready);
    await _pumpEvents();
    notifications.loadCount = 0;
    await container.read(trainingLogControllerProvider.notifier).save(
          TrainingLog(
            id: 'log-2',
            workoutDayId: 'day-2',
            date: now.add(const Duration(minutes: 1)),
            createdAt: now.add(const Duration(minutes: 1)),
            completed: true,
            rpe: 5,
            fatigueLevel: 4,
            sleepQuality: 7,
            painNote: null,
            userNote: null,
          ),
        );
    await _waitFor('第二次日志通知', () => notifications.loadCount > 0);
    expect(notifications.loadCount, 1);
  });
}

Future<void> _waitFor(String label, bool Function() condition) async {
  for (int attempt = 0; attempt < 100 && !condition(); attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: label);
}

Future<void> _pumpEvents() async {
  for (int attempt = 0; attempt < 20; attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _remoteEnvelope(Map<String, dynamic> body) =>
    <String, dynamic>{
      'turn_id': body['turn_id'],
      'snapshot_id': body['snapshot_id'],
      'snapshot_digest': body['snapshot_digest'],
      'memory_set_digest': body['memory_set_digest'],
      'contract_version': coachContractVersion,
      'contract_hash': coachContractHash,
      'rule_set_version': coachRuleSetVersion,
      'allowed': <Map<String, dynamic>>[],
      'forbidden_action_ids': <String>[],
      'risk_level': 'low',
      'reason_codes': <String>['late_test'],
      'required_blocks': <String>[],
    };

class _DeferredCoachClient implements CoachApiClient {
  final Completer<void> called = Completer<void>();
  final Completer<Map<String, dynamic>> response =
      Completer<Map<String, dynamic>>();
  Map<String, dynamic>? lastPostBody;

  @override
  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async =>
      <String, dynamic>{
        'version': 1,
        'snapshot_id': body['state']['snapshot_id'],
        'snapshot_digest': body['state']['snapshot_digest'],
        'memory_set_digest': body['memory_set_digest'],
      };

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) {
    lastPostBody = body;
    called.complete();
    return response.future;
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    bool authenticated = true,
  }) async =>
      <String, dynamic>{};
}

class _NotificationGateway implements CompanionNotificationGateway {
  _NotificationGateway(this.location);

  final timezone.Location location;
  final List<CompanionNotificationRequest> requests =
      <CompanionNotificationRequest>[];
  int loadCount = 0;

  @override
  Future<void> cancelCompanionNotifications() async => requests.clear();

  @override
  Future<timezone.Location> loadLocalLocation() async {
    loadCount += 1;
    return location;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleCompanion(CompanionNotificationRequest request) async {
    requests.add(request);
  }
}

class _ReadyPetController extends PetController {
  @override
  Future<PetState> build() async {
    final DateTime now = DateTime.utc(2026, 9, 4, 8);
    final PetCompanion companion = PetCompanion(
      id: 'pet-a',
      athleteProfileId: 'athlete-a',
      species: PetSpecies.balanceRaccoon,
      nickname: '袋小满',
      unlockedAt: now.subtract(const Duration(days: 20)),
      bornAt: now.subtract(const Duration(days: 20)),
      selectedAccessoryId: null,
      selectedBadgeId: null,
      createdAt: now,
      updatedAt: now,
      totalEnergy: 0,
      stage: PetStage.sprout,
      partnerStars: 0,
      mood: PetMood.calm,
    );
    return PetState(
      status: PetStateStatus.ready,
      profile: PetProfile(
        athleteProfileId: 'athlete-a',
        activePetId: 'pet-a',
        firstEggSpecies: PetSpecies.balanceRaccoon,
        selectedShellId: null,
        createdAt: now,
        updatedAt: now,
      ),
      activeCompanion: companion,
      todayActivitySummary: null,
      todayEnergy: null,
      energyHistory: const <PetDailyEnergy>[],
      pendingSettlement: null,
      statusMessage: '测试伙伴已就绪。',
    );
  }
}

class _MemoryCompanionGateway implements CompanionDatabaseGateway {
  Map<String, Object?>? relationship;
  final Map<String, Map<String, Object?>> messages =
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>?> readRelationshipRow(
          String athleteProfileId) async =>
      relationship == null ? null : Map<String, Object?>.from(relationship!);

  @override
  Future<void> upsertRelationshipRow(Map<String, Object?> row) async {
    relationship = Map<String, Object?>.from(row);
  }

  @override
  Future<List<Map<String, Object?>>> listMessageRows({
    required String athleteProfileId,
    String? localDate,
    DateTime? createdSince,
    int? limit,
  }) async =>
      messages.values.map(Map<String, Object?>.from).toList(growable: false);

  @override
  Future<void> upsertMessageRow(Map<String, Object?> row) async {
    messages[row['message_id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<int> purgeExpiredConversationMessageRows({
    required String athleteProfileId,
    required DateTime createdBefore,
  }) async =>
      0;

  @override
  Future<void> markMessageOpened({
    required String messageId,
    required DateTime openedAt,
  }) async {}

  @override
  Future<void> recordMessageAction({
    required String messageId,
    required String actionId,
    required DateTime actedAt,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> listEventRows({
    required String athleteProfileId,
    String? kind,
  }) async =>
      const <Map<String, Object?>>[];

  @override
  Future<void> upsertEventRow(Map<String, Object?> row) async {}
}

class _MemoryCoachGateway implements CoachDatabaseGateway {
  final Map<String, Map<String, Object?>> traces =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> snapshots =
      <String, Map<String, Object?>>{};

  @override
  Future<void> upsertStateSnapshotRow(Map<String, Object?> row) async {
    snapshots[row['snapshot_id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<Map<String, Object?>?> readLatestStateSnapshotRow({
    required String athleteProfileId,
  }) async =>
      snapshots.values.isEmpty
          ? null
          : Map<String, Object?>.from(snapshots.values.first);

  @override
  Future<void> upsertTurnTraceRow(Map<String, Object?> row) async {
    traces[row['trace_id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<List<Map<String, Object?>>> listMemoryRows({
    required String athleteProfileId,
  }) async =>
      const <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> listMemorySourceRows(
          String memoryId) async =>
      const <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>?> readMemoryRow({
    required String memoryId,
    required String athleteProfileId,
  }) async =>
      null;

  @override
  Future<void> writeMemory({
    required Map<String, Object?> memoryRow,
    required List<Map<String, Object?>> sourceRows,
    String? supersedesMemoryId,
  }) async {}

  @override
  Future<void> tombstoneMemory({
    required String memoryId,
    required String athleteProfileId,
    required DateTime deletedAt,
    required DateTime tombstoneExpiresAt,
  }) async {}
}
