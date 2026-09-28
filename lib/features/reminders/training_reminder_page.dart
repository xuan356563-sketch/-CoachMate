import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/training_reminder.dart';
import '../dashboard/training_mvp_controller.dart';
import 'application/reminder_settings_controller.dart';

class TrainingReminderPage extends ConsumerWidget {
  const TrainingReminderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);

    return TrainFlowPage(
      title: '提醒编排',
      subtitle: '本地提醒 Mock：固定时间当天安排、睡眠差轻松版确认、恢复检查和周报提醒。',
      children: [
        _ReminderSettingsCard(state: state),
        for (final TrainingReminder reminder in state.trainingReminders)
          _ReminderCard(reminder: reminder),
      ],
    );
  }
}

class _ReminderSettingsCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _ReminderSettingsCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '主动服务设置',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(
                label: state.remindersEnabled ? '已启用' : '已暂停',
                color: state.remindersEnabled
                    ? AppColors.primary
                    : AppColors.warningDark,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: state.reminderTimeLabel,
            decoration: const InputDecoration(labelText: '固定提醒时间'),
            items: const [
              DropdownMenuItem<String>(
                value: '07:30',
                child: Text('07:30 早晨'),
              ),
              DropdownMenuItem<String>(
                value: '12:30',
                child: Text('12:30 午间'),
              ),
              DropdownMenuItem<String>(
                value: '20:30',
                child: Text('20:30 下班后'),
              ),
            ],
            onChanged: (String? value) async {
              if (value != null) {
                await _runReminderAction(
                  context,
                  ref
                      .read(reminderSettingsControllerProvider.notifier)
                      .setReminderTimeLabelAsync(value),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          Text(
            state.reminderStatusMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _runReminderAction(
                  context,
                  ref
                      .read(reminderSettingsControllerProvider.notifier)
                      .toggleTrainingRemindersAsync(),
                );
              },
              icon: Icon(
                state.remindersEnabled
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
              ),
              label: Text(state.remindersEnabled ? '暂停提醒' : '开启提醒'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _runReminderAction(
  BuildContext context,
  Future<void> action,
) async {
  try {
    await action;
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提醒设置操作失败：$error')),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final TrainingReminder reminder;

  const _ReminderCard({required this.reminder});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconForReminder(reminder.type),
                color: reminder.enabled
                    ? AppColors.primary
                    : TrainFlowTokens.darkTrainingMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reminder.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(
                label: reminder.priorityLabel,
                color: reminder.enabled
                    ? AppColors.primary
                    : TrainFlowTokens.darkTrainingMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '时间', value: reminder.timeLabel),
          InfoRow(label: '状态', value: reminder.statusLabel),
          const SizedBox(height: 4),
          Text(reminder.reason),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(_routeForReminder(reminder.type)),
              child: Text(reminder.actionLabel),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForReminder(TrainingReminderType type) {
    switch (type) {
      case TrainingReminderType.dailyPlan:
        return Icons.today_outlined;
      case TrainingReminderType.starterProgram:
        return Icons.flag_circle_outlined;
      case TrainingReminderType.formalPlan:
        return Icons.route_outlined;
      case TrainingReminderType.recoveryCheck:
        return Icons.health_and_safety_outlined;
      case TrainingReminderType.proactiveDeload:
        return Icons.battery_saver_outlined;
      case TrainingReminderType.weeklyReport:
        return Icons.summarize_outlined;
    }
  }

  String _routeForReminder(TrainingReminderType type) {
    switch (type) {
      case TrainingReminderType.dailyPlan:
      case TrainingReminderType.recoveryCheck:
      case TrainingReminderType.proactiveDeload:
        return AppRoutes.dashboard;
      case TrainingReminderType.starterProgram:
        return AppRoutes.starterProgram;
      case TrainingReminderType.formalPlan:
        return AppRoutes.plans;
      case TrainingReminderType.weeklyReport:
        return AppRoutes.weeklyReport;
    }
  }
}
