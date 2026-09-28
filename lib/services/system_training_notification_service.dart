import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../core/constants/app_brand.dart';
import '../data/models/training_reminder.dart';
import '../data/models/training_schedule.dart';

const int _trainingNotificationIdStart = 410000000;
const int _trainingNotificationIdEnd = 410999999;
const int _companionNotificationIdStart = 411000000;
const int _companionNotificationIdEnd = 411999999;
const int _maximumScheduledNotifications = 32;
const int _maximumScheduledCompanionNotifications = 2;
const String trainingNotificationBody = '打开${AppBrand.shortName}查看今日安排。';

/// 单条本地训练通知，不包含健康原因或用户自由文本。
class TrainingNotificationRequest {
  final int id;
  final timezone.TZDateTime scheduledAt;

  const TrainingNotificationRequest({
    required this.id,
    required this.scheduledAt,
  });
}

/// 系统通知能力边界，便于在测试中替换平台插件。
abstract class TrainingNotificationGateway {
  Future<bool> requestPermission();

  Future<timezone.Location> loadLocalLocation();

  Future<void> cancelTrainingNotifications();

  Future<void> schedule(TrainingNotificationRequest request);
}

/// 系统通知同步结果。
enum TrainingNotificationSyncStatus {
  disabled,
  permissionDenied,
  scheduled,
  unavailable,
}

class TrainingNotificationSyncResult {
  final TrainingNotificationSyncStatus status;
  final int scheduledCount;

  const TrainingNotificationSyncResult({
    required this.status,
    this.scheduledCount = 0,
  });
}

/// 权限和时区查询可并发，平台取消、安排和迟到清理必须按顺序完成。
class _NotificationMutations {
  int generation = 0;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() mutate) {
    final Future<T> result = _tail.then((_) => mutate());
    // 单次失败仍返回调用者，但不阻断之后的停用清理或重开。
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}

/// 只负责计算和替换训练提醒；异常不会阻断训练主流程。
class TrainingNotificationScheduler {
  final TrainingNotificationGateway _gateway;

  TrainingNotificationScheduler(this._gateway);

  final _NotificationMutations _mutations = _NotificationMutations();

  Future<void> cancel() {
    _mutations.generation += 1;
    return _mutations.run(_gateway.cancelTrainingNotifications);
  }

  Future<TrainingNotificationSyncResult> synchronize({
    required TrainingReminderSettings settings,
    required List<ScheduledWorkout> workouts,
    bool requestPermission = false,
    DateTime? now,
    bool Function()? isActive,
  }) async {
    final int generation = ++_mutations.generation;
    bool active() =>
        generation == _mutations.generation && (isActive?.call() ?? true);
    Future<void> cancelIfCurrent() => _mutations.run(() async {
          if (generation == _mutations.generation) {
            await _gateway.cancelTrainingNotifications();
          }
        });
    Future<TrainingNotificationSyncResult> stop() async {
      await cancelIfCurrent();
      return const TrainingNotificationSyncResult(
        status: TrainingNotificationSyncStatus.disabled,
      );
    }

    try {
      if (!settings.enabled || !active()) return await stop();
      if (requestPermission) {
        final bool granted = await _gateway.requestPermission();
        if (!active()) return await stop();
        if (!granted) {
          await cancelIfCurrent();
          return const TrainingNotificationSyncResult(
            status: TrainingNotificationSyncStatus.permissionDenied,
          );
        }
      }

      final timezone.Location location = await _gateway.loadLocalLocation();
      if (!active()) return await stop();
      final timezone.TZDateTime localNow = now == null
          ? timezone.TZDateTime.now(location)
          : timezone.TZDateTime.from(now, location);
      final List<TrainingNotificationRequest> requests = _buildRequests(
        settings: settings,
        workouts: workouts,
        location: location,
        now: localNow,
      );
      return await _mutations.run(() async {
        if (!active()) {
          if (generation == _mutations.generation) {
            await _gateway.cancelTrainingNotifications();
          }
          return const TrainingNotificationSyncResult(
            status: TrainingNotificationSyncStatus.disabled,
          );
        }
        try {
          await _gateway.cancelTrainingNotifications();
          for (final TrainingNotificationRequest request in requests) {
            if (!active()) break;
            await _gateway.schedule(request);
          }
          if (!active()) {
            return const TrainingNotificationSyncResult(
              status: TrainingNotificationSyncStatus.disabled,
            );
          }
          return TrainingNotificationSyncResult(
            status: TrainingNotificationSyncStatus.scheduled,
            scheduledCount: requests.length,
          );
        } finally {
          // 新代变更尚未进入队列；此处可安全清除旧 schedule 的迟到产物。
          if (!active()) await _gateway.cancelTrainingNotifications();
        }
      });
    } catch (_) {
      return const TrainingNotificationSyncResult(
        status: TrainingNotificationSyncStatus.unavailable,
      );
    }
  }

  List<TrainingNotificationRequest> _buildRequests({
    required TrainingReminderSettings settings,
    required List<ScheduledWorkout> workouts,
    required timezone.Location location,
    required timezone.TZDateTime now,
  }) {
    final List<TrainingNotificationRequest> requests =
        <TrainingNotificationRequest>[];
    for (final ScheduledWorkout workout in workouts) {
      final int minute = settings.followSchedule
          ? workout.startMinute - settings.leadMinutes
          : _parseMinute(settings.preferredTimeLabel);
      final timezone.TZDateTime dayStart = timezone.TZDateTime(
        location,
        workout.scheduledDate.year,
        workout.scheduledDate.month,
        workout.scheduledDate.day,
      );
      final timezone.TZDateTime scheduledAt =
          dayStart.add(Duration(minutes: minute));
      if (!scheduledAt.isAfter(now)) continue;
      requests.add(
        TrainingNotificationRequest(
          id: _notificationId('${workout.id}|${scheduledAt.toIso8601String()}'),
          scheduledAt: scheduledAt,
        ),
      );
    }
    requests.sort(
      (TrainingNotificationRequest first, TrainingNotificationRequest second) =>
          first.scheduledAt.compareTo(second.scheduledAt),
    );
    return requests.take(_maximumScheduledNotifications).toList();
  }

  int _parseMinute(String value) {
    final List<String> parts = value.trim().split(':');
    if (parts.length != 2) return 20 * 60 + 30;
    final int? hour = int.tryParse(parts.first);
    final int? minute = int.tryParse(parts.last);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return 20 * 60 + 30;
    }
    return hour * 60 + minute;
  }

  int _notificationId(String value) {
    int hash = 2166136261;
    for (final int codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return _trainingNotificationIdStart +
        hash % (_trainingNotificationIdEnd - _trainingNotificationIdStart + 1);
  }
}

/// 单条运动搭子通知。调用方必须在传入前完成内容脱敏和隐私等级判定。
class CompanionNotificationRequest {
  const CompanionNotificationRequest({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime scheduledAt;
  final String title;
  final String body;
  final String payload;
}

/// 运动搭子通知与训练通知共享平台权限、时区和插件初始化，但使用独立 ID 段。
abstract interface class CompanionNotificationGateway {
  Future<bool> requestPermission();

  Future<timezone.Location> loadLocalLocation();

  Future<void> cancelCompanionNotifications();

  Future<void> scheduleCompanion(CompanionNotificationRequest request);
}

enum CompanionNotificationSyncStatus {
  disabled,
  permissionDenied,
  scheduled,
  unavailable,
}

class CompanionNotificationSyncResult {
  const CompanionNotificationSyncResult({
    required this.status,
    this.scheduledCount = 0,
  });

  final CompanionNotificationSyncStatus status;
  final int scheduledCount;
}

/// 仅做本地通知的取消后重排；不读取或写入训练、健康与云端数据。
class CompanionNotificationScheduler {
  CompanionNotificationScheduler(this._gateway);

  final _NotificationMutations _mutations = _NotificationMutations();

  final CompanionNotificationGateway _gateway;

  Future<void> cancel() {
    _mutations.generation += 1;
    return _mutations.run(_gateway.cancelCompanionNotifications);
  }

  Future<CompanionNotificationSyncResult> synchronize({
    required bool enabled,
    required Iterable<CompanionNotificationRequest> requests,
    bool requestPermission = false,
    DateTime? now,
    bool Function()? isActive,
  }) async {
    final int generation = ++_mutations.generation;
    bool active() =>
        generation == _mutations.generation && (isActive?.call() ?? true);
    Future<void> cancelIfCurrent() => _mutations.run(() async {
          if (generation == _mutations.generation) {
            await _gateway.cancelCompanionNotifications();
          }
        });
    Future<CompanionNotificationSyncResult> stop() async {
      await cancelIfCurrent();
      return const CompanionNotificationSyncResult(
        status: CompanionNotificationSyncStatus.disabled,
      );
    }

    try {
      if (!enabled || !active()) return await stop();
      if (requestPermission) {
        final bool granted = await _gateway.requestPermission();
        if (!active()) return await stop();
        if (!granted) {
          await cancelIfCurrent();
          return const CompanionNotificationSyncResult(
            status: CompanionNotificationSyncStatus.permissionDenied,
          );
        }
      }
      final timezone.Location location = await _gateway.loadLocalLocation();
      if (!active()) return await stop();
      final timezone.TZDateTime localNow = now == null
          ? timezone.TZDateTime.now(location)
          : timezone.TZDateTime.from(now, location);
      final List<CompanionNotificationRequest> upcoming = requests
          .where((CompanionNotificationRequest request) =>
              timezone.TZDateTime.from(request.scheduledAt, location)
                  .isAfter(localNow))
          .toList()
        ..sort(
          (CompanionNotificationRequest first,
                  CompanionNotificationRequest second) =>
              first.scheduledAt.compareTo(second.scheduledAt),
        );
      return await _mutations.run(() async {
        if (!active()) {
          if (generation == _mutations.generation) {
            await _gateway.cancelCompanionNotifications();
          }
          return const CompanionNotificationSyncResult(
            status: CompanionNotificationSyncStatus.disabled,
          );
        }
        try {
          await _gateway.cancelCompanionNotifications();
          for (final CompanionNotificationRequest request
              in upcoming.take(_maximumScheduledCompanionNotifications)) {
            if (!active()) break;
            await _gateway.scheduleCompanion(request);
          }
          if (!active()) {
            return const CompanionNotificationSyncResult(
              status: CompanionNotificationSyncStatus.disabled,
            );
          }
          return CompanionNotificationSyncResult(
            status: CompanionNotificationSyncStatus.scheduled,
            scheduledCount:
                upcoming.take(_maximumScheduledCompanionNotifications).length,
          );
        } finally {
          // 旧代清理持有同一变更队列，不会取消新代已成功安排的提醒。
          if (!active()) await _gateway.cancelCompanionNotifications();
        }
      });
    } catch (_) {
      return const CompanionNotificationSyncResult(
        status: CompanionNotificationSyncStatus.unavailable,
      );
    }
  }
}

/// 使用消息主键生成稳定的运动搭子通知 ID，不与训练提醒的 ID 段重叠。
int companionNotificationId(String messageId) {
  int hash = 2166136261;
  for (final int codeUnit in messageId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return _companionNotificationIdStart +
      hash % (_companionNotificationIdEnd - _companionNotificationIdStart + 1);
}

/// `flutter_local_notifications` 的最小封装。
class SystemTrainingNotificationGateway
    implements TrainingNotificationGateway, CompanionNotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _timezoneInitialized = false;

  SystemTrainingNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final bool? granted = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        return granted ?? true;
      case TargetPlatform.iOS:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      case TargetPlatform.macOS:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }

  @override
  Future<timezone.Location> loadLocalLocation() async {
    if (!_timezoneInitialized) {
      timezone_data.initializeTimeZones();
      _timezoneInitialized = true;
    }
    try {
      final String identifier =
          (await FlutterTimezone.getLocalTimezone()).identifier;
      final timezone.Location location = timezone.getLocation(identifier);
      timezone.setLocalLocation(location);
      return location;
    } catch (_) {
      return timezone.local;
    }
  }

  @override
  Future<void> cancelTrainingNotifications() async {
    if (!_supportsNotifications) return;
    await _ensureInitialized();
    final List<PendingNotificationRequest> pending =
        await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest request in pending) {
      if (request.id >= _trainingNotificationIdStart &&
          request.id <= _trainingNotificationIdEnd) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  @override
  Future<void> cancelCompanionNotifications() async {
    if (!_supportsNotifications) return;
    await _ensureInitialized();
    final List<PendingNotificationRequest> pending =
        await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest request in pending) {
      if (request.id >= _companionNotificationIdStart &&
          request.id <= _companionNotificationIdEnd) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  @override
  Future<void> schedule(TrainingNotificationRequest request) async {
    await _ensureInitialized();
    await _plugin.zonedSchedule(
      id: request.id,
      title: '训练提醒',
      body: trainingNotificationBody,
      scheduledDate: request.scheduledAt,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'trainmate_training_reminders',
          '训练提醒',
          channelDescription: '按已确认的训练日程发送本地提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '/daily-check-in',
    );
  }

  @override
  Future<void> scheduleCompanion(CompanionNotificationRequest request) async {
    await _ensureInitialized();
    final timezone.Location location = await loadLocalLocation();
    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      scheduledDate: timezone.TZDateTime.from(request.scheduledAt, location),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'trainmate_companion_messages',
          '运动搭子',
          channelDescription: '按用户主动开启的本地搭子通知发送',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: request.payload,
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (!_supportsNotifications) {
      throw UnsupportedError('当前平台不支持系统训练提醒。');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  bool get _supportsNotifications =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
}
