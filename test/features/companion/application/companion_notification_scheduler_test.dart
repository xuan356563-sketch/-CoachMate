import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'package:trainflow_ai/core/constants/app_brand.dart';
import 'package:trainflow_ai/features/companion/application/companion_notification_scheduler.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

void main() {
  late timezone.Location location;

  setUpAll(() {
    timezone_data.initializeTimeZones();
    location = timezone.getLocation('America/Los_Angeles');
  });

  test('默认 L0 通知不泄露事实，并深链到指定本机消息', () {
    final CompanionNotificationRequest request =
        notificationRequestForCompanionMessage(
      _message(
        messageId: 'message with space',
        privacyLevel: PrivacyLevel.l0,
        scheduledAt: DateTime(2026, 8, 12, 9),
      ),
    )!;

    expect(request.title, AppBrand.shortName);
    expect(request.body, '你的运动搭子有一条新消息。');
    expect(request.payload, '/companion?messageId=message+with+space');
    expect(request.id, companionNotificationId('message with space'));
  });

  test('用户明确开启详细内容后仅使用已仲裁的非敏感文案', () {
    final CompanionNotificationRequest request =
        notificationRequestForCompanionMessage(
      _message(
        privacyLevel: PrivacyLevel.l1,
        scheduledAt: DateTime(2026, 8, 12, 9),
        notificationTitle: '衡衡狸',
        notificationBody: '今天的计划已准备好。',
      ),
    )!;

    expect(request.title, '袋小满');
    expect(request.body, '今天的计划已准备好。');
  });

  test('敏感事实和伤病关怀即使传入详细等级也强制回退 L0', () {
    final CompanionNotificationRequest request =
        notificationRequestForCompanionMessage(
      CompanionMessage(
        messageId: 'pain-message',
        athleteProfileId: 'athlete-1',
        localDate: '2026-08-12',
        intent: CompanionIntent.injuryCare,
        copyVariantId: 'injury-7',
        relationshipState: RelationshipState.injured,
        deliveryKind: CompanionDeliveryKind.proactive,
        privacyLevel: PrivacyLevel.l2,
        body: '疼痛记录需要关注。',
        scheduledAt: DateTime(2026, 8, 12, 9),
        notificationTitle: '疼痛 8/10',
        notificationBody: '请查看记录。',
        facts: const <CompanionFact>[
          CompanionFact(
            label: '疼痛记录',
            value: '8/10',
            source: CompanionFactSource.manualEntry,
            isSensitive: true,
          ),
        ],
        createdAt: DateTime(2026, 8, 11, 9),
      ),
    )!;

    expect(request.title, AppBrand.shortName);
    expect(request.body, '你的运动搭子有一条新消息。');
  });

  test('关闭搭子通知时仅取消，不请求权限也不保留队列', () async {
    final _FakeCompanionNotificationGateway gateway =
        _FakeCompanionNotificationGateway(location: location);
    final CompanionNotificationSyncResult result =
        await CompanionNotificationScheduler(gateway).synchronize(
      enabled: false,
      requestPermission: true,
      requests: <CompanionNotificationRequest>[
        _request('message-1', DateTime(2026, 8, 12, 9)),
      ],
      now: DateTime(2026, 8, 11, 9),
    );

    expect(result.status, CompanionNotificationSyncStatus.disabled);
    expect(gateway.cancelCount, 1);
    expect(gateway.permissionRequestCount, 0);
    expect(gateway.requests, isEmpty);
  });

  test('重排只保留最近两条未来通知，并拒绝权限时清空搭子 ID 段', () async {
    final _FakeCompanionNotificationGateway gateway =
        _FakeCompanionNotificationGateway(location: location);
    final CompanionNotificationScheduler scheduler =
        CompanionNotificationScheduler(gateway);
    final DateTime now = DateTime(2026, 8, 11, 9);
    final CompanionNotificationSyncResult scheduled =
        await scheduler.synchronize(
      enabled: true,
      requests: <CompanionNotificationRequest>[
        _request('message-3', DateTime(2026, 8, 13, 9)),
        _request('message-1', DateTime(2026, 8, 11, 8)),
        _request('message-2', DateTime(2026, 8, 12, 9)),
        _request('message-4', DateTime(2026, 8, 14, 9)),
      ],
      now: now,
    );

    expect(scheduled.status, CompanionNotificationSyncStatus.scheduled);
    expect(scheduled.scheduledCount, 2);
    expect(
      gateway.requests.map((CompanionNotificationRequest item) => item.payload),
      <String>[
        '/companion?messageId=message-2',
        '/companion?messageId=message-3',
      ],
    );

    gateway.permissionGranted = false;
    final CompanionNotificationSyncResult denied = await scheduler.synchronize(
      enabled: true,
      requestPermission: true,
      requests: <CompanionNotificationRequest>[
        _request('message-5', DateTime(2026, 8, 15, 9)),
      ],
      now: now,
    );
    expect(denied.status, CompanionNotificationSyncStatus.permissionDenied);
    expect(gateway.requests, isEmpty);
  });

  for (final String waitAt in ['权限', '时区']) {
    test('伙伴旧$waitAt返回不能删除新一代已安排提醒', () async {
      final gateway = _ReorderedCompanionGateway(location: location, waitAt: waitAt);
      final scheduler = CompanionNotificationScheduler(gateway);
      bool oldActive = true;
      Future<CompanionNotificationSyncResult> sync(int day, {bool old = false}) =>
          scheduler.synchronize(
        enabled: true,
        requests: [_request('message-$day', DateTime(2026, 9, day, 9))],
        requestPermission: old,
        now: DateTime(2026, 9, 4),
        isActive: () => !old || oldActive,
      );
      final pending = sync(6, old: true);
      await gateway.entered.future;
      oldActive = false;
      await scheduler.cancel();
      final newer = await sync(7);
      expect(newer.status, CompanionNotificationSyncStatus.scheduled);
      final newRequests = List.of(gateway.requests);
      expect(newRequests, hasLength(1));
      gateway.released.complete();
      expect((await pending).status, CompanionNotificationSyncStatus.disabled);
      expect(gateway.requests, orderedEquals(newRequests));
    });
  }

  test('伙伴停用等待旧安排返回并清理后才允许新代替换', () async {
    final gateway = _ReorderedCompanionGateway(location: location, waitAt: '安排');
    final scheduler = CompanionNotificationScheduler(gateway);
    Future<CompanionNotificationSyncResult> sync(int day) => scheduler.synchronize(
      enabled: true,
        requests: [_request('message-$day', DateTime(2026, 9, day, 9))],
      now: DateTime(2026, 9, 4),
    );
    final pending = sync(6);
    await gateway.entered.future;
    bool stopped = false;
    final stopping = scheduler.cancel().then((_) => stopped = true);
    final newer = sync(7);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse, reason: '平台旧安排未返回前不能误报资源已经停止。');
    gateway.released.complete();
    expect((await pending).status, CompanionNotificationSyncStatus.disabled);
    await stopping;
    expect((await newer).status, CompanionNotificationSyncStatus.scheduled);
    expect(gateway.requests, hasLength(1));
    expect(gateway.requests.single.scheduledAt.day, 7);
  });

  test('停用期间迟到的时区结果只清理伙伴提醒且不再调度', () async {
    final Completer<timezone.Location> deferred =
        Completer<timezone.Location>();
    final _DeferredCompanionGateway gateway =
        _DeferredCompanionGateway(deferred);
    bool active = true;
    final Future<CompanionNotificationSyncResult> pending =
        CompanionNotificationScheduler(gateway).synchronize(
      enabled: true,
      requests: <CompanionNotificationRequest>[
        _request('late', DateTime(2026, 8, 12, 9)),
      ],
      now: DateTime(2026, 8, 11, 9),
      isActive: () => active,
    );
    await gateway.called.future;
    active = false;
    deferred.complete(location);

    final CompanionNotificationSyncResult result = await pending;
    expect(result.status, CompanionNotificationSyncStatus.disabled);
    expect(gateway.cancelCount, 1);
    expect(gateway.requests, isEmpty);
  });
}

class _DeferredCompanionGateway implements CompanionNotificationGateway {
  _DeferredCompanionGateway(this.location);

  final Completer<timezone.Location> location;
  final Completer<void> called = Completer<void>();
  final List<CompanionNotificationRequest> requests =
      <CompanionNotificationRequest>[];
  int cancelCount = 0;

  @override
  Future<void> cancelCompanionNotifications() async {
    cancelCount += 1;
    requests.clear();
  }

  @override
  Future<timezone.Location> loadLocalLocation() {
    called.complete();
    return location.future;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleCompanion(CompanionNotificationRequest request) async {
    requests.add(request);
  }
}

CompanionMessage _message({
  String messageId = 'message-1',
  PrivacyLevel privacyLevel = PrivacyLevel.l0,
  DateTime? scheduledAt,
  String? notificationTitle,
  String? notificationBody,
}) {
  return CompanionMessage(
    messageId: messageId,
    athleteProfileId: 'athlete-1',
    localDate: '2026-08-12',
    intent: CompanionIntent.morningBrief,
    copyVariantId: 'mb-02',
    relationshipState: RelationshipState.steady,
    deliveryKind: CompanionDeliveryKind.proactive,
    privacyLevel: privacyLevel,
    body: '今天按计划来？',
    scheduledAt: scheduledAt,
    notificationTitle: notificationTitle,
    notificationBody: notificationBody,
    createdAt: DateTime(2026, 8, 11, 9),
  );
}

CompanionNotificationRequest _request(String messageId, DateTime scheduledAt) {
  return CompanionNotificationRequest(
    id: companionNotificationId(messageId),
    scheduledAt: scheduledAt,
    title: 'TrainMate',
    body: '你的运动搭子有一条新消息。',
    payload: '/companion?messageId=$messageId',
  );
}

class _FakeCompanionNotificationGateway
    implements CompanionNotificationGateway {
  _FakeCompanionNotificationGateway({
    required this.location,
  }) : permissionGranted = true;

  final timezone.Location location;
  bool permissionGranted;
  final List<CompanionNotificationRequest> requests =
      <CompanionNotificationRequest>[];
  int cancelCount = 0;
  int permissionRequestCount = 0;

  @override
  Future<void> cancelCompanionNotifications() async {
    cancelCount += 1;
    requests.clear();
  }

  @override
  Future<timezone.Location> loadLocalLocation() async => location;

  @override
  Future<bool> requestPermission() async {
    permissionRequestCount += 1;
    return permissionGranted;
  }

  @override
  Future<void> scheduleCompanion(CompanionNotificationRequest request) async {
    requests.add(request);
  }
}

class _ReorderedCompanionGateway extends _FakeCompanionNotificationGateway {
  _ReorderedCompanionGateway({required super.location, required this.waitAt});
  final String waitAt;
  final entered = Completer<void>();
  final released = Completer<void>();
  bool _waited = false;

  Future<void> _wait(String phase) async {
    if (waitAt != phase || _waited) return;
    _waited = true;
    entered.complete();
    await released.future;
  }

  @override
  Future<bool> requestPermission() async {
    await _wait('权限');
    return super.requestPermission();
  }

  @override
  Future<timezone.Location> loadLocalLocation() async {
    await _wait('时区');
    return location;
  }

  @override
  Future<void> scheduleCompanion(CompanionNotificationRequest request) async {
    await _wait('安排');
    await super.scheduleCompanion(request);
  }
}
