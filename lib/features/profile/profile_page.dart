import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/achievement.dart';
import '../../data/models/pain_log.dart';
import '../../data/models/training_log.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/weekly_report.dart';
import '../dashboard/training_mvp_controller.dart';
import 'application/achievement_controller.dart';
import 'application/user_profile_controller.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final UserProfile profile = ref.watch(
      userProfileControllerProvider.select(
        (UserProfileState state) => state.profile,
      ),
    );

    return TrainFlowPage(
      title: '我的',
      subtitle: '个人资料、训练偏好和最近反馈。',
      action: IconButton(
        tooltip: '编辑资料',
        onPressed: () => context.go(AppRoutes.onboarding),
        icon: const Icon(Icons.edit_note),
      ),
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.primaryLightest,
                    child: Icon(Icons.person, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile.trainingGoal,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final MainSport sport in profile.mainSports)
                    ToneBadge(label: sport.label),
                  ToneBadge(label: profile.workScheduleType.label),
                  ToneBadge(label: profile.equipmentAccessType.label),
                  ToneBadge(label: profile.workerProfileType.label),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: MetricPill(
                      label: '每周训练',
                      value: '${profile.weeklyTrainingDays} 天',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricPill(
                      label: '单次可用',
                      value: '${profile.dailyAvailableMinutes} 分钟',
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '当前分型策略',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                profile.workerProfileType.strategy,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '器械条件：${profile.equipmentAccessType.label}；每日选择无器械场景时会优先使用替代动作。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        const SectionTitle(title: '自用验收'),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_outlined,
                      color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '14 天真实使用记录',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '每天记录身体数据、训练执行、反馈和阻断问题，完成后再进行人工 Gate A 验收。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.go(AppRoutes.selfUseAcceptance),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开验收记录'),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle(title: '用户画像'),
        _UserInsightPreviewCard(state: state),
        const SectionTitle(title: '自动周报'),
        _WeeklyReportPreviewCard(report: state.weeklyReport),
        const SectionTitle(title: '成就徽章'),
        _AchievementSummaryCard(
          state: state,
          onSyncRecords: () =>
              ref.read(achievementControllerProvider.notifier).sync(
                    state.achievementProgressList,
                    showNoChangeMessage: true,
                  ),
        ),
        const SectionTitle(title: '康复状态'),
        _RehabStatusCard(state: state),
        const SectionTitle(title: '最近训练记录'),
        if (state.logs.isEmpty)
          TrainFlowCard(
            child: Text(
              '还没有训练反馈。完成今日训练后，这里会显示 RPE 和完成情况。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          )
        else
          for (final TrainingLog log in state.logs)
            TrainFlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          log.completed ? '已完成训练' : '未完成训练',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      ToneBadge(
                        label: 'RPE ${log.rpe}',
                        color: log.rpe >= 8
                            ? AppColors.warningDark
                            : AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(log.userNote ?? '无备注'),
                ],
              ),
            ),
      ],
    );
  }
}

class _UserInsightPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _UserInsightPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '透明用户画像',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: state.userInsightSummaryLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '把训练完成、跳过、降级、身体数据和导入记录转成有置信度的画像结论。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.userInsights),
              child: const Text('查看画像'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyReportPreviewCard extends StatelessWidget {
  final WeeklyReport report;

  const _WeeklyReportPreviewCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '自动周报 Agent Mock',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: report.completionRateLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${report.weekLabel} · 完成 ${report.completedWorkouts}/${report.plannedWorkouts} · ${report.loadTrendLabel}',
          ),
          const SizedBox(height: 8),
          Text(
            '生成完成率、负荷趋势、决策回顾和下周重点，可导出 Markdown 和 PNG 图片卡片。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.weeklyReport),
              child: const Text('打开周报'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementSummaryCard extends StatelessWidget {
  final TrainingMvpState state;
  final VoidCallback onSyncRecords;

  const _AchievementSummaryCard({
    required this.state,
    required this.onSyncRecords,
  });

  @override
  Widget build(BuildContext context) {
    final List<AchievementProgress> achievements =
        state.achievementProgressList;
    final List<AchievementRecord> records = state.achievementRecords;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '成就体系',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: state.achievementSummaryLabel,
                color: AppColors.warningDark,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '把 30 天连击、跟练执行、身体数据和安全降级转成可见回报。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.grayLightest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.storage_outlined,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '本地成就记录表',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      ToneBadge(
                        label: state.achievementRecordSummaryLabel,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.achievementRecordStatusMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  if (records.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final AchievementRecord record in records.take(2))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${record.title} · ${record.unlockedAtLabel} · ${record.sourceLabel}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onSyncRecords,
                      icon: const Icon(Icons.sync),
                      label: const Text('同步成就记录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final AchievementProgress achievement in achievements)
            _AchievementTile(
              progress: achievement,
              record: state.achievementRecordFor(achievement.definition.id),
            ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final AchievementProgress progress;
  final AchievementRecord? record;

  const _AchievementTile({
    required this.progress,
    required this.record,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = _achievementColor(progress.definition.category);
    final AchievementRecord? savedRecord = record;
    final String badgeLabel = savedRecord != null
        ? '已入库'
        : progress.unlocked
            ? '已解锁'
            : progress.progressLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: progress.unlocked ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: progress.unlocked
                ? color.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    progress.unlocked
                        ? Icons.workspace_premium
                        : Icons.lock_outline,
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      progress.definition.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  ToneBadge(
                    label: badgeLabel,
                    color: color,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                progress.definition.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (savedRecord != null) ...[
                const SizedBox(height: 6),
                Text(
                  '本地记录：${savedRecord.unlockedAtLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress.progress,
                minHeight: 7,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RehabStatusCard extends StatelessWidget {
  final TrainingMvpState state;

  const _RehabStatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final PainLog? painLog = state.latestPainLog;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  painLog == null ? '暂无结构化疼痛记录' : painLog.bodyPart,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (painLog != null)
                ToneBadge(
                  label: painLog.requiresMedicalAttention ? '就医红线' : '降级参考',
                  color: painLog.requiresMedicalAttention
                      ? AppColors.danger
                      : AppColors.warningDark,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            painLog == null
                ? '记录疼痛后，系统会把今日训练切换为恢复版或停止训练提示。'
                : '疼痛 ${painLog.painLevel}/10 · ${painLog.timing.label}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.rehab),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('打开康复记录'),
            ),
          ),
        ],
      ),
    );
  }
}

Color _achievementColor(AchievementCategory category) {
  switch (category) {
    case AchievementCategory.consistency:
      return AppColors.primary;
    case AchievementCategory.execution:
      return AppColors.secondary;
    case AchievementCategory.bodyData:
      return AppColors.success;
    case AchievementCategory.safety:
      return AppColors.warningDark;
  }
}
