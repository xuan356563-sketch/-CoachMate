import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

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

    expect(request.title, 'TrainMate');
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

    expect(request.title, '衡衡狸');
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

    expect(request.title, 'TrainMate');
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
