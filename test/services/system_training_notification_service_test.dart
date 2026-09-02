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

  test('夏令时切换当天仍按本地墙上时间调度固定提醒', () async {
    final _FakeTrainingNotificationGateway gateway =
        _FakeTrainingNotificationGateway(location: location);
    await TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(
        enabled: true,
        followSchedule: false,
        preferredTimeLabel: '07:30',
      ),
      // 2026-03-08 是 America/Los_Angeles 的春季切换日，02:00 直接跳到 03:00。
      workouts: <ScheduledWorkout>[_workout(DateTime(2026, 3, 8))],
      now: DateTime(2026, 3, 1),
    );

    expect(gateway.requests.single.scheduledAt.hour, 7);
    expect(gateway.requests.single.scheduledAt.minute, 30);
  });

  test('提前量跨过零点时提醒落在前一天而不是当天凌晨', () async {
    final _FakeTrainingNotificationGateway gateway =
        _FakeTrainingNotificationGateway(location: location);
    await TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(enabled: true, leadMinutes: 30),
      workouts: <ScheduledWorkout>[
        _workout(DateTime(2026, 8, 1), startMinute: 20),
      ],
      now: DateTime(2026, 7, 1),
    );

    final TrainingNotificationRequest request = gateway.requests.single;
    expect(request.scheduledAt.day, 31);
    expect(request.scheduledAt.month, 7);
    expect(request.scheduledAt.hour, 23);
    expect(request.scheduledAt.minute, 50);
  });

  test('同一批提醒使用互不相同的通知 ID', () async {
    final _FakeTrainingNotificationGateway gateway =
        _FakeTrainingNotificationGateway(location: location);
    await TrainingNotificationScheduler(gateway).synchronize(
      settings: _settings(enabled: true),
      workouts: <ScheduledWorkout>[
        for (int day = 1; day <= 20; day += 1)
          _workout(DateTime(2026, 8, day), startMinute: 8 * 60),
      ],
      now: DateTime(2026, 7, 30, 12),
    );

    final Set<int> ids = gateway.requests
        .map((TrainingNotificationRequest item) => item.id)
        .toSet();
    expect(ids.length, gateway.requests.length);
  });
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
