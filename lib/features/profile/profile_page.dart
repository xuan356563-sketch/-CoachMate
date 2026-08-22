import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/trainmate_visual_mode.dart';
import '../../core/widgets/emp_system.dart';
import '../../core/widgets/flow_mascot.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/achievement.dart';
import '../../data/models/body_metric.dart';
import '../../data/models/cloud_sync.dart';
import '../../data/models/growth_evidence.dart';
import '../../data/models/health_snapshot.dart';
import '../../data/models/meal_guide.dart';
import '../../data/models/pain_log.dart';
import '../../data/models/training_log.dart';
import '../../data/models/training_schedule.dart';
import '../../data/models/user_profile.dart';
import '../../services/growth_engine.dart';
import '../auth/application/auth_controller.dart';
import '../dashboard/training_mvp_controller.dart';
import '../growth/application/growth_evidence_controller.dart';
import '../cloud_sync/application/cloud_sync_controller.dart';
import 'application/achievement_controller.dart';
import 'application/health_data_gateway_contract.dart';
import 'application/health_data_deletion_coordinator.dart';
import 'application/user_profile_controller.dart';
import 'application/training_schedule_controller.dart';
import 'application/health_sync_controller.dart';
import 'widgets/profile_showcase_header.dart';
import 'widgets/training_load_card.dart';

FlowMascotSpec selectProfileMascotSpec({
  required bool profileCompleted,
  required bool isHealthSyncing,
  required bool requiresMedicalAttention,
  required int readinessScore,
}) {
  if (!profileCompleted) {
    return const FlowMascotSpec(
      action: FlowMascotAction.beckon,
      expression: FlowMascotExpression.wink,
      semanticLabel: 'Flow 训练伙伴邀请你完善个人档案',
      durationMilliseconds: 520,
    );
  }
  if (isHealthSyncing) {
    return const FlowMascotSpec(
      action: FlowMascotAction.listen,
      expression: FlowMascotExpression.focused,
      semanticLabel: 'Flow 训练伙伴正在聆听健康数据',
      durationMilliseconds: 560,
    );
  }
  if (requiresMedicalAttention || readinessScore < 52) {
    return const FlowMascotSpec(
      action: FlowMascotAction.recover,
      expression: FlowMascotExpression.closed,
      semanticLabel: 'Flow 训练伙伴陪你静心恢复',
      durationMilliseconds: 620,
    );
  }
  return const FlowMascotSpec(
    action: FlowMascotAction.meditate,
    expression: FlowMascotExpression.calm,
    semanticLabel: 'Flow 训练伙伴陪你查看健康档案',
    durationMilliseconds: 580,
  );
}

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
    final AsyncValue<HealthSyncState> healthSync =
        ref.watch(healthSyncControllerProvider);
    final bool isHealthSyncing = switch (healthSync) {
      AsyncData<HealthSyncState>(:final value) => value.syncing,
      _ => false,
    };
    final FlowMascotSpec mascotSpec = selectProfileMascotSpec(
      profileCompleted: state.profileCompleted,
      isHealthSyncing: isHealthSyncing,
      requiresMedicalAttention: state.requiresMedicalAttention,
      readinessScore: state.readinessScore,
    );
    final AsyncValue<AuthState> auth = ref.watch(authControllerProvider);
    final bool showPilotValidation = ref.watch(localPreviewEnabledProvider) ||
        switch (auth) {
          AsyncData<AuthState>(:final value) => value.isLocalPreview,
          _ => false,
        };
    final GrowthEvidenceState growthState =
        ref.watch(growthEvidenceControllerProvider);
    final GrowthLevelProgress growthProgress =
        GrowthEngine().buildLevelProgress(
      events: growthState.events,
      previous: growthState.levelState,
    );
    final int completedSessionCount = state.logs
        .where((TrainingLog log) => log.isSessionRecord && log.completed)
        .length;
    final int trainingRecordCount =
        state.logs.where((TrainingLog log) => log.isSessionRecord).length;

    return TrainMateImmersiveHubPage(
      mode: TrainMateVisualMode.darkTraining,
      hero: ProfileShowcaseHeader(
        name: profile.name,
        trainingGoal: profile.trainingGoal,
        readinessScore: state.readinessScore,
        completedSessionCount: completedSessionCount,
        growthProgress: growthProgress,
        achievementCount: state.achievementRecords.length,
        trainingRecordCount: trainingRecordCount,
        onEditProfile: () => context.push(AppRoutes.onboarding),
        onOpenGrowthEvidence: () => context.push(AppRoutes.growthEvidence),
        onOpenWeeklyReport: () => context.push(AppRoutes.weeklyReport),
      ),
      children: [
        ProfileImmersiveOverview(
          readinessScore: state.readinessScore,
          completedSessionCount: completedSessionCount,
          growthProgress: growthProgress,
          achievementCount: state.achievementRecords.length,
          trainingRecordCount: trainingRecordCount,
          onOpenGrowthEvidence: () => context.push(AppRoutes.growthEvidence),
          onOpenWeeklyReport: () => context.push(AppRoutes.weeklyReport),
        ),
        const SizedBox(height: 20),
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          cornerCharacterAction:
              trainMateActionForFlowMascot(mascotSpec.action),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TrainFlowTokens.darkTrainingRaised,
                      border: Border.all(
                        color: TrainFlowTokens.pink,
                        width: 3,
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: TrainFlowTokens.accent,
                      size: 40,
                    ),
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
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile.trainingGoal,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: TrainFlowTokens.darkTrainingMuted,
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
                  for (int index = 0;
                      index < profile.mainSports.length;
                      index += 1)
                    ToneBadge(
                      label: index == 0
                          ? '主目标 · ${profile.mainSports[index].label}'
                          : '次目标 · ${profile.mainSports[index].label}',
                    ),
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
                      color: TrainFlowTokens.accent,
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
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                profile.workerProfileType.strategy,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '器械条件：${profile.equipmentAccessType.label}；每日选择无器械场景时会优先使用替代动作。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
            ],
          ),
        ),
        if (showPilotValidation)
          TrainFlowCard(
            tone: TrainFlowCardTone.peach,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '7–14 天假设卡验证',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('匿名记录承诺、每日履约、线下押金状态和第 14 天继续决定。'),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.push(AppRoutes.pilotValidation),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('打开内测记录'),
                  ),
                ),
              ],
            ),
          ),
        const SectionTitle(title: '账号'),
        const _AccountCard(),
        const SectionTitle(title: '训练知识'),
        TrainFlowCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.verified_outlined,
              color: TrainFlowTokens.accent,
            ),
            title: const Text('内部已审核训练知识'),
            subtitle: const Text('查看可追溯原则与模板；草稿和停用内容不会参与 AI 生成。'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.knowledge),
          ),
        ),
        const SectionTitle(title: '训练日程'),
        const _TrainingCalendarCard(),
        const SectionTitle(title: '健康管理'),
        const _AppleHealthCard(),
        _RehabStatusCard(state: state),
        _BodyDataPreviewCard(metric: state.latestBodyMetric, state: state),
        _NutritionPreviewCard(guide: state.activeMealGuide),
        const SectionTitle(title: '训练负荷'),
        TrainingLoadCard(state: state),
        const SectionTitle(title: '自用验收'),
        TrainFlowCard(
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
                      '14 天真实使用记录',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '每天记录身体数据、训练执行、反馈和阻断问题，完成后再进行人工 Gate A 验收。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push(AppRoutes.selfUseAcceptance),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开验收记录'),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle(title: '用户画像'),
        _UserInsightPreviewCard(state: state),
        const SectionTitle(title: '本周成长报告'),
        const _WeeklyReportPreviewCard(),
        const SectionTitle(title: '成就徽章'),
        _AchievementSummaryCard(
          state: state,
          onSyncRecords: () =>
              ref.read(achievementControllerProvider.notifier).sync(
                    state.achievementProgressList,
                    showNoChangeMessage: true,
                  ),
        ),
        const SectionTitle(title: '最近训练记录'),
        if (state.logs.isEmpty)
          TrainFlowCard(
            child: Text(
              '还没有训练反馈。完成今日训练后，这里会显示 RPE 和完成情况。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
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
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      ToneBadge(
                        label: 'RPE ${log.rpe}',
                        color: log.rpe >= 8
                            ? AppColors.warningDark
                            : TrainFlowTokens.accent,
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

class _TrainingCalendarCard extends ConsumerStatefulWidget {
  const _TrainingCalendarCard();

  @override
  ConsumerState<_TrainingCalendarCard> createState() =>
      _TrainingCalendarCardState();
}

class _TrainingCalendarCardState extends ConsumerState<_TrainingCalendarCard> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final TrainingScheduleState schedule =
        ref.watch(trainingScheduleControllerProvider);
    final List<TrainingAvailabilitySlot> slots =
        schedule.slotsFor(_selectedDate);
    final ScheduledWorkout? workout = schedule.workoutFor(_selectedDate);
    final DateTime today = DateTime.now();

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '安排可训练时间',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: '${schedule.workouts.length} 项已排期'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '系统会根据日期、时间长度和训练时段安排完整版、压缩版或恢复版。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          CalendarDatePicker(
            initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
            firstDate: DateTime(today.year, today.month, today.day),
            lastDate: today.add(const Duration(days: 365)),
            onDateChanged: (DateTime value) {
              setState(() => _selectedDate = value);
            },
          ),
          if (workout != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TrainFlowTokens.darkTrainingRaised,
                borderRadius: BorderRadius.circular(
                  TrainFlowTokens.mainTabControlRadius,
                ),
              ),
              child: Text(
                '已安排 ${workout.period.label} ${workout.timeLabel} · ${workout.allocatedMinutes} 分钟 · ${workout.version.label}',
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (slots.isEmpty)
            const Text('当天还没有可训练时间。')
          else
            for (final TrainingAvailabilitySlot slot in slots)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(slot.timeLabel),
                subtitle:
                    Text('${slot.period.label} · ${slot.durationMinutes} 分钟'),
                trailing: IconButton(
                  tooltip: '删除时间段',
                  onPressed: () => ref
                      .read(trainingScheduleControllerProvider.notifier)
                      .removeSlot(slot.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: slots.length >= 3 ? null : _addSlot,
              icon: const Icon(Icons.add_alarm),
              label: const Text('添加可训练时间'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            schedule.statusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _addSlot() async {
    TimeOfDay start = const TimeOfDay(hour: 18, minute: 30);
    TimeOfDay end = const TimeOfDay(hour: 19, minute: 30);
    bool repeatWeekly = false;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('添加可训练时间'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('开始时间'),
                    trailing: Text(start.format(context)),
                    onTap: () async {
                      final value = await showTimePicker(
                        context: context,
                        initialTime: start,
                      );
                      if (value != null) setDialogState(() => start = value);
                    },
                  ),
                  ListTile(
                    title: const Text('结束时间'),
                    trailing: Text(end.format(context)),
                    onTap: () async {
                      final value = await showTimePicker(
                        context: context,
                        initialTime: end,
                      );
                      if (value != null) setDialogState(() => end = value);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('每周重复 12 周'),
                    value: repeatWeekly,
                    onChanged: (bool? value) =>
                        setDialogState(() => repeatWeekly = value ?? false),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    ref.read(trainingScheduleControllerProvider.notifier).addSlot(
          date: _selectedDate,
          startMinute: start.hour * 60 + start.minute,
          endMinute: end.hour * 60 + end.minute,
          repeatWeekly: repeatWeekly,
        );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AuthState> auth = ref.watch(authControllerProvider);
    final AuthState? authState = switch (auth) {
      AsyncData<AuthState>(:final value) => value,
      _ => null,
    };
    final user = authState?.user;
    final AsyncValue<CloudSyncUiState> cloudSync =
        ref.watch(cloudSyncControllerProvider);
    final CloudSyncUiState? cloudSyncState = cloudSync.value;
    final String accountTitle = switch (user?.accountType) {
      'phone' => '旧手机号账号',
      'local' => '本地体验账号',
      _ => '邮箱账号',
    };
    final String accountLabel = user?.maskedAccountLabel ?? '邮箱信息不可用';
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: TrainFlowTokens.accent,
                foregroundColor: TrainFlowTokens.onAccent,
                child: Icon(Icons.verified_user_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$accountLabel · 训练数据保留在本机',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TrainFlowTokens.darkTrainingMuted,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '退出账号',
                onPressed: authState?.isBusy == true
                    ? null
                    : () => ref.read(authControllerProvider.notifier).logout(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          if (cloudSyncState?.available == true) ...[
            const Divider(height: 28),
            Row(
              children: [
                const Icon(Icons.cloud_sync_outlined,
                    color: TrainFlowTokens.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cloudSyncState!.enabled ? '云同步已启用' : '云同步未启用',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cloudSyncState.statusMessage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TrainFlowTokens.darkTrainingMuted,
                            ),
                      ),
                    ],
                  ),
                ),
                if (cloudSyncState.busy)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (cloudSyncState.enabled)
                  PopupMenuButton<String>(
                    tooltip: '云同步操作',
                    onSelected: (String action) {
                      if (action == 'sync') {
                        ref
                            .read(cloudSyncControllerProvider.notifier)
                            .synchronize();
                      } else {
                        ref
                            .read(cloudSyncControllerProvider.notifier)
                            .disable();
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'sync',
                        child: Text('立即同步'),
                      ),
                      PopupMenuItem<String>(
                        value: 'disable',
                        child: Text('关闭云同步'),
                      ),
                    ],
                  )
                else
                  TextButton(
                    onPressed: () => _confirmCloudSync(context, ref),
                    child: const Text('启用'),
                  ),
              ],
            ),
            if (cloudSyncState.conflictCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '有 ${cloudSyncState.conflictCount} 项冲突待确认，系统没有自动覆盖。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.warningDark,
                    ),
              ),
              if (cloudSyncState.conflicts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '当前：${_cloudSyncEntityLabel(
                    cloudSyncState.conflicts.first.entityType,
                  )}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: cloudSyncState.busy
                          ? null
                          : () => _confirmConflictResolution(
                                context,
                                ref,
                                cloudSyncState.conflicts.first,
                                CloudSyncConflictResolution.keepLocal,
                              ),
                      child: const Text('保留本机版本'),
                    ),
                    TextButton(
                      onPressed: cloudSyncState.busy
                          ? null
                          : () => _confirmConflictResolution(
                                context,
                                ref,
                                cloudSyncState.conflicts.first,
                                CloudSyncConflictResolution.useCloud,
                              ),
                      child: const Text('使用云端版本'),
                    ),
                  ],
                ),
              ],
            ],
          ],
          const Divider(height: 28),
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.privacy_tip_outlined,
                color: TrainFlowTokens.accent,
              ),
              title: const Text('数据与隐私'),
              subtitle: const Text('导出云端账号数据，管理账号删除与撤销'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.dataRights),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCloudSync(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('启用云同步？'),
        content: const Text(
          '只同步训练偏好、计划、课次、完成摘要和应用设置。'
          '姓名、身体数据、健康数据、疼痛、RPE、备注、心率、路线、图片、语音和力量重量不会上传。'
          '现有本地数据不会因登录自动上传。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不启用'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认启用'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(cloudSyncControllerProvider.notifier)
        .enable(confirmed: true);
  }

  Future<void> _confirmConflictResolution(
    BuildContext context,
    WidgetRef ref,
    CloudSyncConflict conflict,
    CloudSyncConflictResolution resolution,
  ) async {
    final bool useCloud = resolution == CloudSyncConflictResolution.useCloud;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认同步冲突选择？'),
        content: Text(
          useCloud
              ? '将使用云端的${_cloudSyncEntityLabel(conflict.entityType)}版本。'
                  '此操作只在确认后执行。'
              : '将保留本机的${_cloudSyncEntityLabel(conflict.entityType)}版本，'
                  '并在下次同步时提交。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认选择'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(cloudSyncControllerProvider.notifier).resolveConflict(
          conflictId: conflict.id,
          resolution: resolution,
          confirmed: true,
        );
  }

  String _cloudSyncEntityLabel(CloudSyncEntityType type) {
    return switch (type) {
      CloudSyncEntityType.userProfile => '用户档案',
      CloudSyncEntityType.trainingPreferences => '训练偏好',
      CloudSyncEntityType.planVersions => '计划版本',
      CloudSyncEntityType.scheduledWorkouts => '计划课次',
      CloudSyncEntityType.completionSummaries => '完成摘要',
      CloudSyncEntityType.appSettings => '应用设置',
    };
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.psychology_alt, color: TrainFlowTokens.accent),
              Text(
                '透明用户画像',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              ToneBadge(label: state.userInsightSummaryLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '把训练完成、跳过、降级、身体数据和导入记录转成有置信度的画像结论。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.userInsights),
              child: const Text('查看画像'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyReportPreviewCard extends StatelessWidget {
  const _WeeklyReportPreviewCard();

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '本地确定性周报',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const ToneBadge(label: '本地计算'),
            ],
          ),
          const SizedBox(height: 10),
          const Text('读取带版本的训练事实与指标，数据不足时明确显示积累进度。'),
          const SizedBox(height: 8),
          Text(
            '周报由设备内固定中文模板生成，不使用旧准备度或身体慢变量另算第二套口径。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.weeklyReport),
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
                      ?.copyWith(fontWeight: FontWeight.w600),
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
            '把 30 天累计成长、跟练执行、身体数据和安全降级转成可见回报。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: TrainFlowTokens.darkTrainingRaised,
              borderRadius: BorderRadius.circular(8),
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
                        color: TrainFlowTokens.darkTrainingMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '本地成就记录表',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      ToneBadge(
                        label: state.achievementRecordSummaryLabel,
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.achievementRecordStatusMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TrainFlowTokens.darkTrainingMuted,
                        ),
                  ),
                  if (records.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final AchievementRecord record in records.take(2))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${record.title} · ${record.unlockedAtLabel} · ${record.sourceLabel}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: TrainFlowTokens.darkTrainingOnSurface,
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
          color: TrainFlowTokens.darkTrainingRaised,
          borderRadius: BorderRadius.circular(
            TrainFlowTokens.mainTabControlRadius,
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
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                progress.definition.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              if (savedRecord != null) ...[
                const SizedBox(height: 6),
                Text(
                  '本地记录：${savedRecord.unlockedAtLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  EmpProgressRing(
                    progress: progress.progress,
                    size: 40,
                    strokeWidth: 5,
                    color: color,
                    trackColor: color.withValues(alpha: 0.15),
                  ),
                  const SizedBox(width: 10),
                  EmpBadge(
                    label: badgeLabel,
                    tone: _achievementBadgeTone(progress.unlocked),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleHealthCard extends ConsumerWidget {
  const _AppleHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HealthSyncState> asyncState =
        ref.watch(healthSyncControllerProvider);
    final HealthSyncState? state = asyncState.value;
    final String healthStatusMessage = asyncState.hasError
        ? '健康同步初始化失败，后台批次已保留，可重试或删除本地健康数据。'
        : state?.statusMessage ?? '正在检查系统健康能力…';
    final HealthSnapshot? snapshot = state?.latest;
    final bool supported = state?.supported == true;
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Apple 健康',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(
                label: !supported
                    ? '当前不可用'
                    : state?.connected == true
                        ? '已有本机数据'
                        : '尚未读取',
                color: state?.connected == true
                    ? AppColors.success
                    : TrainFlowTokens.darkTrainingMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '每一阶段都会先说明用途，再由你主动请求。Apple 健康无法可靠区分“拒绝读取”和“没有数据”，这里不会宣称逐项已授权。',
          ),
          if (snapshot != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (snapshot.sleepHours != null)
                  ToneBadge(
                      label: '睡眠 ${snapshot.sleepHours!.toStringAsFixed(1)} h'),
                if (snapshot.hrvMs != null)
                  ToneBadge(label: 'HRV ${snapshot.hrvMs} ms'),
                if (snapshot.restingHeartRate != null)
                  ToneBadge(label: '静息心率 ${snapshot.restingHeartRate}'),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _HealthPermissionStageTile(
            title: '同步训练记录',
            purpose: '用于读取训练、距离和能量，建立 L1 训练完成事实。',
            buttonLabel: '同步训练记录',
            stage: HealthPermissionStage.workout,
            state: state,
            onPressed: supported && state?.syncing != true
                ? () => ref
                    .read(healthSyncControllerProvider.notifier)
                    .connectAndSync(stage: HealthPermissionStage.workout)
                : null,
          ),
          const SizedBox(height: 10),
          _HealthPermissionStageTile(
            title: '进步分析',
            purpose: '用于读取心率、静息心率、HRV、VO2max 和路线，只生成本地 L2/L3 指标。',
            buttonLabel: '读取进步分析数据',
            stage: HealthPermissionStage.analysis,
            state: state,
            onPressed: supported && state?.syncing != true
                ? () => ref
                    .read(healthSyncControllerProvider.notifier)
                    .connectAndSync(stage: HealthPermissionStage.analysis)
                : null,
          ),
          const SizedBox(height: 10),
          _HealthPermissionStageTile(
            title: '身体追踪（可选）',
            purpose: '仅在你主动开启后读取体重和体脂；这些慢变量只用于月报和主动查看页。',
            buttonLabel: '开启身体追踪',
            stage: HealthPermissionStage.body,
            state: state,
            onPressed: supported && state?.syncing != true
                ? () => ref
                    .read(healthSyncControllerProvider.notifier)
                    .connectAndSync(stage: HealthPermissionStage.body)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            healthStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          if (supported) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: state?.syncing == true
                    ? null
                    : () async {
                        try {
                          await ref
                              .read(healthSyncControllerProvider.notifier)
                              .drainPendingBackgroundBatches();
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('后台健康数据写入失败，批次已保留，请稍后重试。'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('重试后台批次'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: state?.syncing == true
                  ? null
                  : () async {
                      final bool confirmed = await _confirmHealthDataDeletion(
                        context,
                      );
                      if (!confirmed) return;
                      try {
                        await ref
                            .read(healthDataDeletionCoordinatorProvider)
                            .clearCurrentAthleteData();
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('清除本地健康数据失败，未完成的步骤可安全重试。'),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除本地健康数据'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthPermissionStageTile extends StatelessWidget {
  const _HealthPermissionStageTile({
    required this.title,
    required this.purpose,
    required this.buttonLabel,
    required this.stage,
    required this.state,
    required this.onPressed,
  });

  final String title;
  final String purpose;
  final String buttonLabel;
  final HealthPermissionStage stage;
  final HealthSyncState? state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TrainFlowTokens.darkTrainingRaised,
        borderRadius: BorderRadius.circular(
          TrainFlowTokens.mainTabControlRadius,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(
                label: _healthStageStatusLabel(state, stage),
                color: _healthStageStatusColor(state, stage),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            purpose,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: state?.syncing == true
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

String _healthStageStatusLabel(
  HealthSyncState? state,
  HealthPermissionStage stage,
) {
  if (state == null) return '正在检查';
  if (!state.supported) return '不可用';
  final HealthAuthorizationState authorization = state.authorizationFor(stage);
  if (authorization == HealthAuthorizationState.notRequested) return '未请求';
  if (authorization == HealthAuthorizationState.unavailable) return '不可用';
  if (authorization == HealthAuthorizationState.failed) return '请求失败';
  if (state.lastSyncByStage[stage] != null) {
    return state.connected ? '已读取本机数据' : '可读取或暂无数据';
  }
  return '不可判定';
}

Color _healthStageStatusColor(
  HealthSyncState? state,
  HealthPermissionStage stage,
) {
  final String label = _healthStageStatusLabel(state, stage);
  if (label == '已读取本机数据') return AppColors.success;
  if (label == '请求失败') return AppColors.danger;
  return TrainFlowTokens.darkTrainingMuted;
}

Future<bool> _confirmHealthDataDeletion(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('删除本地健康数据？'),
          content: const Text(
            '这会清除当前运动员的健康事实、指标、报告修订、成长证据、同步锚点和待处理批次。此操作不会删除 Apple 健康中的原始数据。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      ) ??
      false;
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
              const Icon(
                Icons.health_and_safety_outlined,
                color: TrainFlowTokens.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '康复状态',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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
            painLog == null ? '暂无结构化疼痛记录' : painLog.bodyPart,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            painLog == null
                ? '记录疼痛后，系统会把今日训练切换为恢复版或停止训练提示。'
                : '疼痛 ${painLog.painLevel}/10 · ${painLog.timing.label}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.rehab),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('打开康复记录'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyDataPreviewCard extends StatelessWidget {
  final BodyMetric? metric;
  final TrainingMvpState state;

  const _BodyDataPreviewCard({
    required this.metric,
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
              const Icon(Icons.monitor_heart, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '身体数据',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const ToneBadge(label: '7 日趋势'),
            ],
          ),
          const SizedBox(height: 10),
          if (metric == null)
            const Text('还没有身体数据，先完成一次 10 秒快录。')
          else
            Text(
              '${metric!.measuredDateLabel} · 体重 ${metric!.weightKg.toStringAsFixed(1)} kg · HRV ${metric!.hrvMs} ms · 睡眠 ${metric!.sleepHours.toStringAsFixed(1)} h',
            ),
          const SizedBox(height: 8),
          Text(
            '7 日均值：体重 ${state.averageWeight7d.toStringAsFixed(1)} kg，静息心率 ${state.averageRestingHr7d.round()} bpm。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push(AppRoutes.dataCenter),
              icon: const Icon(Icons.open_in_new),
              label: const Text('查看身体数据'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionPreviewCard extends StatelessWidget {
  final MealGuide guide;

  const _NutritionPreviewCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日营养建议',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: guide.scenario.label),
            ],
          ),
          const SizedBox(height: 10),
          Text(guide.instruction),
          const SizedBox(height: 8),
          Text(
            guide.formula,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push(AppRoutes.mealGuide),
              icon: const Icon(Icons.open_in_new),
              label: const Text('查看照吃指令'),
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
      return TrainFlowTokens.accent;
    case AchievementCategory.execution:
      return TrainFlowTokens.accent;
    case AchievementCategory.bodyData:
      return AppColors.success;
    case AchievementCategory.safety:
      return AppColors.warningDark;
  }
}

EmpBadgeTone _achievementBadgeTone(bool unlocked) {
  return unlocked ? EmpBadgeTone.mint : EmpBadgeTone.neutral;
}
