import 'package:trainflow_ai/features/companion/domain/companion_models.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

/// 将本地消息转换为系统通知请求。内容在这里强制执行锁屏隐私边界。
CompanionNotificationRequest? notificationRequestForCompanionMessage(
  CompanionMessage message,
) {
  final DateTime? scheduledAt = message.scheduledAt;
  if (scheduledAt == null ||
      message.openedAt != null ||
      message.deliveryKind != CompanionDeliveryKind.proactive) {
    return null;
  }
  final bool neutral = message.privacyLevel == PrivacyLevel.l0 ||
      message.intent.isStrictL0 ||
      message.facts.any((CompanionFact fact) => fact.isSensitive);
  final String title =
      neutral ? 'TrainMate' : (message.notificationTitle ?? '衡衡狸');
  final String body = neutral
      ? '你的运动搭子有一条新消息。'
      : (message.notificationBody ?? '打开 TrainMate 查看搭子消息。');
  return CompanionNotificationRequest(
    id: message.notificationId ?? companionNotificationId(message.messageId),
    scheduledAt: scheduledAt,
    title: title,
    body: body,
    payload:
        '/companion?messageId=${Uri.encodeQueryComponent(message.messageId)}',
  );
}

/// 在关系设置启用后，以已仲裁的消息重新安排本机通知。
/// 该函数不申请权限，权限只应在用户主动打开开关时申请。
Future<CompanionNotificationSyncResult> rescheduleCompanionNotifications({
  required CompanionNotificationScheduler scheduler,
  required CompanionRelationship relationship,
  required Iterable<CompanionMessage> messages,
  required DateTime now,
  bool requestPermission = false,
}) {
  final List<CompanionNotificationRequest> requests = messages
      .map(notificationRequestForCompanionMessage)
      .whereType<CompanionNotificationRequest>()
      .toList(growable: false);
  return scheduler.synchronize(
    enabled: relationship.notificationsEnabled,
    requests: requests,
    requestPermission: requestPermission,
    now: now,
  );
}
