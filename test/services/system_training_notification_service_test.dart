import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'package:trainflow_ai/data/models/training_reminder.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

void main() {
  late timezone.Location location;

  setUpAll(() {
    timezone_data.initializeTimeZones();
    location = timezone.getLocation('America/Los_Angeles');
  });

  test('明确不支持的平台未初始化且无资源时取消是安全空操作', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final SystemTrainingNotificationGateway gateway =
        SystemTrainingNotificationGateway();

    await gateway.cancelTrainingNotifications();
    await gateway.cancelCompanionNotifications();
  });

  test('首次授权被拒绝时取消既有系统提醒且不继续调度', () async {
    final _FakeTrainingNotificationGateway gateway =
        _FakeTrainingNotificationGateway(
      location: location,
      permissionGranted: false,
    );
    final TrainingNotificationSyncResult result =
        await TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(enabled: true),
      workouts: <ScheduledWorkout>[_workout(DateTime(2026, 8, 1))],
      requestPermission: true,
      now: DateTime(2026, 7, 30, 12),
    );

    expect(result.status, TrainingNotificationSyncStatus.permissionDenied);
    expect(gateway.cancelCount, 1);
    expect(gateway.requests, isEmpty);
  });

  test('关闭提醒时只执行取消，不请求权限', () async {
    final _FakeTrainingNotificationGateway gateway =
        _FakeTrainingNotificationGateway(location: location);
    final TrainingNotificationSyncResult result =
        await TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(enabled: false),
      workouts: <ScheduledWorkout>[_workout(DateTime(2026, 8, 1))],
      now: DateTime(2026, 7, 30, 12),
    );

    expect(result.status, TrainingNotificationSyncStatus.disabled);
    expect(gateway.permissionRequestCount, 0);
    expect(gateway.cancelCount, 1);
  });

  test('计划变更时先替换旧提醒，并按训练时间减去提前量', () async {
    final _FakeTrainingNotificationGateway gateway =
        _FakeTrainingNotificationGateway(location: location);
    final TrainingNotificationSyncResult result =
        await TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(enabled: true, leadMinutes: 30),
      workouts: <ScheduledWorkout>[
        _workout(DateTime(2026, 8, 1), startMinute: 8 * 60),
        _workout(DateTime(2026, 8, 2), startMinute: 9 * 60),
      ],
      now: DateTime(2026, 7, 30, 12),
    );

    expect(result.status, TrainingNotificationSyncStatus.scheduled);
    expect(result.scheduledCount, 2);
    expect(gateway.cancelCount, 1);
    expect(gateway.requests.first.scheduledAt.hour, 7);
    expect(gateway.requests.first.scheduledAt.minute, 30);
    expect(trainingNotificationBody, '打开练搭查看今日安排。');
    expect(gateway.requests.last.scheduledAt.hour, 8);
    expect(gateway.requests.last.scheduledAt.minute, 30);
  });

  test('跨夏令时按本地墙上时间调度固定提醒', () async {
    final _FakeTrainingNotificationGateway gateway =
        _FakeTrainingNotificationGateway(location: location);
    await TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(
        enabled: true,
        followSchedule: false,
        preferredTimeLabel: '07:30',
      ),
      workouts: <ScheduledWorkout>[
        _workout(DateTime(2026, 3, 7)),
        _workout(DateTime(2026, 3, 9)),
      ],
      now: DateTime(2026, 3, 1),
    );

    expect(
      gateway.requests
          .map((TrainingNotificationRequest item) => item.scheduledAt.hour),
      everyElement(7),
    );
    expect(
      gateway.requests
          .map((TrainingNotificationRequest item) => item.scheduledAt.minute),
      everyElement(30),
    );
    expect(
      gateway.requests.first.scheduledAt.timeZoneOffset,
      isNot(gateway.requests.last.scheduledAt.timeZoneOffset),
    );
  });

  for (final String waitAt in ['权限', '时区']) {
    test('训练旧$waitAt返回不能删除新一代已安排提醒', () async {
      final gateway = _ReorderedTrainingGateway(location: location, waitAt: waitAt);
      final scheduler = TrainingNotificationScheduler(gateway);
      bool oldActive = true;
      Future<TrainingNotificationSyncResult> sync(int day, {bool old = false}) =>
          scheduler.synchronize(
        settings: _settings(enabled: true),
        workouts: [_workout(DateTime(2026, 9, day))],
        requestPermission: old,
        now: DateTime(2026, 9, 4),
        isActive: () => !old || oldActive,
      );
      final pending = sync(6, old: true);
      await gateway.entered.future;
      oldActive = false;
      await scheduler.cancel();
      final newer = await sync(7);
      expect(newer.status, TrainingNotificationSyncStatus.scheduled);
      final newRequests = List.of(gateway.requests);
      expect(newRequests, hasLength(1));
      gateway.released.complete();
      expect((await pending).status, TrainingNotificationSyncStatus.disabled);
      expect(gateway.requests, orderedEquals(newRequests));
    });
  }

  test('训练停用等待旧安排返回并清理后才允许新代替换', () async {
    final gateway = _ReorderedTrainingGateway(location: location, waitAt: '安排');
    final scheduler = TrainingNotificationScheduler(gateway);
    Future<TrainingNotificationSyncResult> sync(int day) => scheduler.synchronize(
      settings: _settings(enabled: true),
        workouts: [_workout(DateTime(2026, 9, day))],
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
    expect((await pending).status, TrainingNotificationSyncStatus.disabled);
    await stopping;
    expect((await newer).status, TrainingNotificationSyncStatus.scheduled);
    expect(gateway.requests, hasLength(1));
    expect(gateway.requests.single.scheduledAt.day, 7);
  });

  test('停用期间迟到的时区结果只清理训练提醒且不再调度', () async {
    final Completer<timezone.Location> deferred =
        Completer<timezone.Location>();
    final _DeferredTrainingGateway gateway = _DeferredTrainingGateway(deferred);
    bool active = true;
    final Future<TrainingNotificationSyncResult> pending =
        TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(enabled: true),
      workouts: <ScheduledWorkout>[_workout(DateTime(2026, 8, 1))],
      now: DateTime(2026, 7, 30, 12),
      isActive: () => active,
    );
    await gateway.called.future;
    active = false;
    deferred.complete(location);

    final TrainingNotificationSyncResult result = await pending;
    expect(result.status, TrainingNotificationSyncStatus.disabled);
    expect(gateway.cancelCount, 1);
    expect(gateway.requests, isEmpty);
  });
}

class _DeferredTrainingGateway implements TrainingNotificationGateway {
  _DeferredTrainingGateway(this.location);

  final Completer<timezone.Location> location;
  final Completer<void> called = Completer<void>();
  final List<TrainingNotificationRequest> requests =
      <TrainingNotificationRequest>[];
  int cancelCount = 0;

  @override
  Future<void> cancelTrainingNotifications() async {
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
  Future<void> schedule(TrainingNotificationRequest request) async {
    requests.add(request);
  }
}

TrainingReminderSettings _settings({
  required bool enabled,
  String preferredTimeLabel = '20:30',
  bool followSchedule = true,
  int leadMinutes = 30,
}) {
  return TrainingReminderSettings(
    enabled: enabled,
    preferredTimeLabel: preferredTimeLabel,
    followSchedule: followSchedule,
    leadMinutes: leadMinutes,
  );
}

ScheduledWorkout _workout(
  DateTime date, {
  int startMinute = 8 * 60,
}) {
  return ScheduledWorkout(
    id: 'workout-${date.toIso8601String()}',
    workoutDayId: 'workout-day',
    scheduledDate: date,
    startMinute: startMinute,
    allocatedMinutes: 60,
    period: TrainingTimePeriod.morning,
    version: ScheduledWorkoutVersion.full,
  );
}

class _FakeTrainingNotificationGateway implements TrainingNotificationGateway {
  final timezone.Location location;
  final bool permissionGranted;
  final List<TrainingNotificationRequest> requests =
      <TrainingNotificationRequest>[];
  int permissionRequestCount = 0;
  int cancelCount = 0;

  _FakeTrainingNotificationGateway({
    required this.location,
    this.permissionGranted = true,
  });

  @override
  Future<void> cancelTrainingNotifications() async {
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
  Future<void> schedule(TrainingNotificationRequest request) async {
    requests.add(request);
  }
}

class _ReorderedTrainingGateway extends _FakeTrainingNotificationGateway {
  _ReorderedTrainingGateway({required super.location, required this.waitAt});
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
  Future<void> schedule(TrainingNotificationRequest request) async {
    await _wait('安排');
    await super.schedule(request);
  }
}
