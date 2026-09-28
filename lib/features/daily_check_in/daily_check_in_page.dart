import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_branding.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/daily_check_in.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../data/models/daily_check_in_record.dart';
import '../../data/models/training_schedule.dart';
import '../../data/models/starter_program.dart';
import '../../data/models/training_reminder.dart';
import '../data_center/application/body_metric_controller.dart';
import '../daily_adjustment/application/daily_adjustment_controller.dart';
import '../dashboard/training_mvp_controller.dart';
import '../profile/application/training_schedule_controller.dart';
import '../reminders/application/reminder_settings_controller.dart';

class DailyCheckInPage extends ConsumerWidget {
  const DailyCheckInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final BodyMetricState bodyMetricState =
        ref.watch(bodyMetricControllerProvider);
    final DailyCheckInSummary summary = state.dailyCheckInSummary;

    return TrainFlowPage(
      title: '精简签到',
      layout: TrainFlowPageLayout.form,
      subtitle: '默认值来自画像；计划恢复或安全暂停也属于持续成长。',
      eyebrow: '今天如何训练',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.dashboard,
      ),
      artwork: const TrainMateCharacterAvatar(
        action: TrainMateAction.highKnees,
      ),
      children: [
        _CheckInStreakCard(state: bodyMetricState),
        _DailyCheckInSummaryCard(
          summary: summary,
          state: state,
        ),
        _DailyCheckInPromptCard(summary: summary),
        _DailyCheckInActionCard(summary: summary),
        const _TodayScheduleCard(),
        _IntegratedReminderCard(state: state),
        if (ref.watch(featureAccessProvider).isEnabled('feature.reminders'))
          TrainFlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('恢复时间工程估算',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(state.recoveryCountdownLabel),
                const SizedBox(height: 8),
                Text(state.recoveryEvidenceSummary),
                const SizedBox(height: 8),
                Text(state.recoveryAdvice),
              ],
            ),
          ),
        _NoFailTrainingDayCard(
          day: state.activeStarterProgramDay,
          state: state,
        ),
      ],
    );
  }
}

class _CheckInStreakCard extends ConsumerWidget {
  const _CheckInStreakCard({required this.state});

  final BodyMetricState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CheckInCelebrationReceipt? celebration =
        state.checkInCelebrations.isEmpty
            ? null
            : state.checkInCelebrations.first;
    return TrainFlowCard(
      key: const ValueKey<String>('daily-check-in-streak-card'),
      tone: TrainFlowCardTone.peach,
      cornerCharacterAction: celebration == null
          ? TrainMateAction.highKnees
          : TrainMateAction.jumpingJack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_outlined,
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  celebration?.title ?? '连续成长记录',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ToneBadge(label: '连续 ${state.checkInStreak.currentStreak} 天'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '历史最长 ${state.checkInStreak.longestStreak} 天 · '
            '累计 ${state.checkInStreak.totalCheckInDays} 天',
          ),
          const SizedBox(height: 6),
          Text(
            celebration == null
                ? '只按当天明确确认计数；计划恢复和安全暂停不会伪装成训练完成。'
                : '里程碑已写入本地回执；庆祝动画不会作为训练证据。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ToneBadge(
                label: state.checkInStreak.currentStreak >= 7
                    ? '周里程碑 ✓'
                    : '连续 7 天',
                color: state.checkInStreak.currentStreak >= 7
                    ? AppColors.success
                    : TrainFlowTokens.darkTrainingMuted,
              ),
              ToneBadge(
                label: state.checkInStreak.currentStreak >= 30
                    ? '月里程碑 ✓'
                    : '连续 30 天',
                color: state.checkInStreak.currentStreak >= 30
                    ? AppColors.success
                    : TrainFlowTokens.darkTrainingMuted,
              ),
              for (final int target in <int>[60, 90, 180, 365])
                ToneBadge(
                  label: state.checkInStreak.totalCheckInDays >= target
                      ? '累计 $target 天 ✓'
                      : '累计 $target 天',
                  color: state.checkInStreak.totalCheckInDays >= target
                      ? AppColors.success
                      : TrainFlowTokens.darkTrainingMuted,
                ),
            ],
          ),
          if (celebration != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: state.isSavingBodyMetrics ? null : () async {
                  await _runCheckInAction(
                    context,
                    () => ref
                        .read(bodyMetricControllerProvider.notifier)
                        .markCheckInCelebrationSeen(celebration.id),
                  );
                },
                icon: const Icon(Icons.celebration_outlined),
                label: const Text('收下成就'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayScheduleCard extends ConsumerWidget {
  const _TodayScheduleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(trainingScheduleControllerProvider);
    final workout = schedule.workoutFor(DateTime.now());
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日训练时间',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: workout?.version.label ?? '待安排'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            workout == null
                ? '今天还没有可执行的训练时间，请在“我的”中添加可用时间。'
                : '${workout.period.label} ${workout.timeLabel} · ${workout.allocatedMinutes} 分钟',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.go(AppRoutes.profile),
              icon: const Icon(Icons.calendar_month),
              label: const Text('管理训练日程'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegratedReminderCard extends ConsumerWidget {
  final TrainingMvpState state;

  const _IntegratedReminderCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReminderSettingsState settingsState =
        ref.watch(reminderSettingsControllerProvider);
    final TrainingReminderSettings settings = settingsState.settings;
    final schedule = ref.watch(trainingScheduleControllerProvider);
    final scheduled = schedule.workoutFor(DateTime.now());
    final String reminderTime = settings.followSchedule && scheduled != null
        ? _minuteLabel(scheduled.startMinute - settings.leadMinutes)
        : settings.preferredTimeLabel;

    return TrainFlowCard(
      cornerCharacterAction: TrainMateAction.highKnees,
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
                  '主动提醒',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: settings.enabled,
                onChanged: (_) async {
                  await _runReminderSettingsAction(
                    context,
                    ref
                        .read(reminderSettingsControllerProvider.notifier)
                        .toggleTrainingRemindersAsync(),
                  );
                },
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('跟随训练日程'),
            subtitle: Text(
              scheduled == null ? '无排期时使用固定时间' : '今日提醒时间 $reminderTime',
            ),
            value: settings.followSchedule,
            onChanged: (bool value) async {
              await _runReminderSettingsAction(
                context,
                ref
                    .read(reminderSettingsControllerProvider.notifier)
                    .setFollowScheduleAsync(value),
              );
            },
          ),
          if (settings.followSchedule)
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 15, label: Text('提前 15 分')),
                ButtonSegment(value: 30, label: Text('提前 30 分')),
                ButtonSegment(value: 60, label: Text('提前 60 分')),
              ],
              selected: <int>{settings.leadMinutes},
              onSelectionChanged: (Set<int> value) async {
                await _runReminderSettingsAction(
                  context,
                  ref
                      .read(reminderSettingsControllerProvider.notifier)
                      .setLeadMinutesAsync(value.first),
                );
              },
            ),
          const SizedBox(height: 10),
          Text(settingsState.statusMessage),
          const Divider(height: 24),
          for (final TrainingReminder reminder
              in state.trainingReminders.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoRow(
                label: reminder.title,
                value: reminder.id == 'daily-plan'
                    ? reminderTime
                    : reminder.timeLabel,
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _runReminderSettingsAction(
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

String _minuteLabel(int minute) {
  final int normalized = ((minute % (24 * 60)) + (24 * 60)) % (24 * 60);
  return '${(normalized ~/ 60).toString().padLeft(2, '0')}:${(normalized % 60).toString().padLeft(2, '0')}';
}

class _NoFailTrainingDayCard extends StatelessWidget {
  final StarterProgramDay day;
  final TrainingMvpState state;

  const _NoFailTrainingDayCard({
    required this.day,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final String minimumAction = state.starterProgramRescueMode
        ? day.rescueVersion
        : day.trainingSteps.isEmpty
            ? '完成 5 分钟轻量活动'
            : day.trainingSteps.first;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_circle, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '不失败训练日',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: day.dayLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${day.title} · ${day.durationMinutes} 分钟 · 累计成长日 ${state.starterProgramStreak} 天',
          ),
          const SizedBox(height: 10),
          Text(
            '今日最小动作',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(minimumAction),
          const SizedBox(height: 8),
          Text(
            state.starterProgramStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push(AppRoutes.starterProgram),
              icon: const Icon(Icons.open_in_new),
              label: const Text('查看完整引导'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyCheckInSummaryCard extends StatelessWidget {
  final DailyCheckInSummary summary;
  final TrainingMvpState state;

  const _DailyCheckInSummaryCard({
    required this.summary,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined,
                  color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '输入递减',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: summary.modeLabel),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '今天只问',
                  value: summary.questionCountLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricPill(
                  label: '默认值',
                  value: summary.confidenceLabel,
                  color: TrainFlowTokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary.explanation),
          const SizedBox(height: 8),
          Text(
            summary.sortExplanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            state.dailyCheckInStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _DailyCheckInPromptCard extends StatelessWidget {
  final DailyCheckInSummary summary;

  const _DailyCheckInPromptCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日需要确认',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            summary.sortExplanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 10),
          for (final DailyCheckInPrompt prompt in summary.prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    prompt.required
                        ? Icons.radio_button_checked
                        : Icons.auto_awesome,
                    size: 18,
                    color: prompt.required
                        ? AppColors.primary
                        : AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'P${prompt.priorityRank} ${prompt.label}：${prompt.value} · ${prompt.sourceLabel} · ${prompt.priorityReason}',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DailyCheckInActionCard extends ConsumerWidget {
  final DailyCheckInSummary summary;

  const _DailyCheckInActionCard({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(bodyMetricControllerProvider).isSavingBodyMetrics;
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一键确认',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '“和昨天一样”表示你确认今天沿用下列昨日数据，将保存为手动记录，并保留缺失字段；这不是重新测量。恢复或暂停只保护连续成长，不生成训练完成、身体指标或训练 XP。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Text(summary.yesterdayDescription),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: summary.canUseYesterday && !busy
                  ? () async {
                      await _runCheckInAction(
                        context,
                        () => ref
                            .read(bodyMetricControllerProvider.notifier)
                            .confirmDailyCheckInSameAsYesterday(
                              expectedFingerprint: summary.yesterdayFingerprint,
                            ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.repeat),
              label: const Text('和昨天一样'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : () async {
                await _runCheckInAction(context, () async {
                  final operation = ref.read(featureAccessProvider)
                      .beginOperation('feature.daily_check_in',
                          dependencies: const ['feature.daily_adjustment']);
                  final adjustment = ref.read(dailyAdjustmentControllerProvider.notifier);
                  await ref.read(bodyMetricControllerProvider.notifier)
                      .recordTiredDailyCheckIn();
                  if (!context.mounted) return;
                  try {
                    operation.checkActive();
                    await adjustment.recordTiredCheckIn();
                  } catch (error) {
                    throw StateError('签到已保存，偏累说明未更新；请重新查看调整建议。$error');
                  }
                });
              },
              icon: const Icon(Icons.battery_saver_outlined),
              label: const Text('今天偏累，建议轻松版'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _confirmContinuityDay(
                    context,
                    ref,
                    DailyContinuityKind.plannedRest,
                  ),
                  icon: const Icon(Icons.self_improvement_outlined),
                  label: const Text('按计划恢复'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _confirmContinuityDay(
                    context,
                    ref,
                    DailyContinuityKind.safetyPause,
                  ),
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('安全暂停'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmContinuityDay(
  BuildContext context,
  WidgetRef ref,
  DailyContinuityKind continuityKind,
) async {
  await _runCheckInAction(context, () async {
    final operation = ref.read(featureAccessProvider)
        .beginOperation('feature.daily_check_in');
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          continuityKind == DailyContinuityKind.plannedRest
              ? '确认按计划恢复'
              : '确认安全暂停',
        ),
        content: Text(
          '${continuityKind.description}\n\n这会保护今天的连续成长，但不会生成训练完成、身体指标或训练 XP，也不能用于补签。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认记录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    operation.checkActive();
    await ref.read(bodyMetricControllerProvider.notifier)
        .recordContinuityDay(continuityKind);
  });
}

Future<void> _runCheckInAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('签到操作失败：$error')),
    );
  }
}
