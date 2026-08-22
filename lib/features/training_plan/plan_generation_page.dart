import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_brand.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/ai_artifact.dart';
import '../../data/models/generated_training_plan.dart';
import '../../data/models/pre_exercise_clearance.dart';
import '../../data/models/training_plan.dart';
import '../../data/models/training_rule_audit.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/workout_day.dart';
import '../../services/training_prescription_safety_audit_service.dart';
import '../profile/application/user_profile_controller.dart';
import '../ai_center/data/training_prescription_api_models.dart';
import 'application/four_week_plan_controller.dart';
import 'application/official_clearance_link_launcher.dart';
import 'application/pre_exercise_clearance_controller.dart';
import 'application/training_plan_generation_controller.dart';

class PlanGenerationPage extends ConsumerStatefulWidget {
  const PlanGenerationPage({super.key});

  @override
  ConsumerState<PlanGenerationPage> createState() => _PlanGenerationPageState();
}

class _PlanGenerationPageState extends ConsumerState<PlanGenerationPage> {
  PreExerciseClearanceStatus _selectedClearanceStatus =
      PreExerciseClearanceStatus.notCompleted;
  bool _currentInjuryOrRestriction = false;
  bool _clearanceFormInitialized = false;
  String? _selectedPopulationTemplateId;

  @override
  Widget build(BuildContext context) {
    final UserProfileState profileState =
        ref.watch(userProfileControllerProvider);
    final AsyncValue<PreExerciseClearanceState> clearanceAsync =
        ref.watch(preExerciseClearanceControllerProvider);
    final AsyncValue<TrainingPlanGenerationUiState> generationAsync =
        ref.watch(trainingPlanGenerationControllerProvider);
    final FourWeekPlanState planState =
        ref.watch(fourWeekPlanControllerProvider);
    final PreExerciseClearanceState? clearanceState = clearanceAsync.value;
    if (!_clearanceFormInitialized && clearanceState != null) {
      _selectedClearanceStatus = clearanceState.clearance.status;
      _currentInjuryOrRestriction =
          clearanceState.clearance.currentInjuryOrRestriction;
      _clearanceFormInitialized = true;
    }
    final List<String> blockers = _eligibilityBlockers(
      profileState: profileState,
      clearance: clearanceState?.clearance,
      now: ref.watch(preExerciseClearanceRealtimeClockProvider)(),
    );
    final List<PopulationTemplateOption> populationTemplates =
        generationAsync.value?.knowledgeCatalog?.populationTemplates ??
            const <PopulationTemplateOption>[];
    final String recommendedPopulationTemplateId =
        _recommendPopulationTemplate(profileState.profile);
    final String? selectedPopulationTemplateId = populationTemplates.any(
      (PopulationTemplateOption item) =>
          item.id == _selectedPopulationTemplateId,
    )
        ? _selectedPopulationTemplateId
        : populationTemplates
                .where(
                  (PopulationTemplateOption item) =>
                      item.id == recommendedPopulationTemplateId,
                )
                .firstOrNull
                ?.id ??
            populationTemplates.firstOrNull?.id;

    return TrainFlowPage(
      title: '生成四周训练计划',
      layout: TrainFlowPageLayout.form,
      subtitle: 'AI 只生成结构化处方，本地编译和安全审计通过后才能确认激活。',
      eyebrow: 'SKILL 计划',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.plans,
      ),
      children: <Widget>[
        _ProfilePreflightCard(profileState: profileState),
        _ClearanceCard(
          clearanceAsync: clearanceAsync,
          selectedStatus: _selectedClearanceStatus,
          currentInjuryOrRestriction: _currentInjuryOrRestriction,
          onStatusChanged: (PreExerciseClearanceStatus? value) {
            if (value == null) return;
            setState(() => _selectedClearanceStatus = value);
          },
          onInjuryChanged: (bool value) {
            setState(() => _currentInjuryOrRestriction = value);
          },
          onOpenOfficial: _openOfficialClearance,
          onSave: _saveClearance,
        ),
        _PopulationModeCard(
          options: populationTemplates,
          selectedId: selectedPopulationTemplateId,
          recommendedId: recommendedPopulationTemplateId,
          onChanged: (String value) {
            setState(() => _selectedPopulationTemplateId = value);
          },
        ),
        _OutboundSummaryCard(profile: profileState.profile),
        if (planState.executionLocked || planState.updateAvailable)
          _PlanStatusNotice(planState: planState),
        _GenerationGateCard(
          blockers: blockers,
          generationAsync: generationAsync,
          onGenerate: selectedPopulationTemplateId == null
              ? null
              : () => ref
                  .read(trainingPlanGenerationControllerProvider.notifier)
                  .generate(
                    populationTemplateId: selectedPopulationTemplateId,
                  ),
          onUseLocalPlan: _useLocalPlan,
        ),
        if (planState.draft == null &&
            generationAsync.value?.artifact?.decision ==
                AiArtifactDecision.accepted)
          _AcceptedRecoveryCard(onRetry: _confirmActivation),
        if (planState.draft != null) ...<Widget>[
          _PlanPreviewCard(draft: planState.draft!),
          _PlanAuditCard(planState: planState),
          _PlanDifferenceCard(
            activePlan: planState.activePlan,
            draftPlan: planState.draft!.plan,
          ),
          _DraftDecisionCard(
            generationAsync: generationAsync,
            canActivate: planState.canActivateDraft,
            onConfirm: _confirmActivation,
            onReject: () => ref
                .read(trainingPlanGenerationControllerProvider.notifier)
                .reject(),
          ),
        ],
        if (planState.history.isNotEmpty)
          _PlanHistoryCard(
            versions: planState.history,
            activeVersionId: planState.activeVersionId,
            onRollback: _confirmRollback,
          ),
      ],
    );
  }

  Future<void> _openOfficialClearance() async {
    bool opened = false;
    try {
      opened = await ref.read(officialClearanceLinkLauncherProvider).open();
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    await Clipboard.setData(
      const ClipboardData(text: PreExerciseClearance.officialSourceUrl),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开官方页面，链接已复制，请在浏览器中打开。')),
    );
  }

  Future<void> _saveClearance() async {
    if (_selectedClearanceStatus == PreExerciseClearanceStatus.notCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择官方流程给出的结果。')),
      );
      return;
    }
    final bool saved =
        await ref.read(preExerciseClearanceControllerProvider.notifier).record(
              status: _selectedClearanceStatus,
              currentInjuryOrRestriction: _currentInjuryOrRestriction,
            );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? '筛查状态已安全保存在本机。' : '筛查状态保存失败，请重试。')),
    );
  }

  void _useLocalPlan() {
    ref.read(fourWeekPlanControllerProvider.notifier).regenerate();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已继续使用本地规则计划，不会标记为 Skill 生成。')),
    );
  }

  Future<void> _confirmActivation() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认激活新的四周计划？'),
        content: const Text('当前计划会作为历史版本保留，可在版本历史中回退。未完成确认前不会改变现有计划。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认激活'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(trainingPlanGenerationControllerProvider.notifier)
        .confirmAndActivate();
  }

  Future<void> _confirmRollback(String versionId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('回退到这个计划版本？'),
        content: const Text('旧版本会先按当前资料重新执行本地安全复核；不通过时不会切换。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认回退'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(trainingPlanGenerationControllerProvider.notifier)
        .rollback(versionId);
  }
}

String _recommendPopulationTemplate(UserProfile profile) {
  if (profile.mainSports.contains(MainSport.hyrox)) return 'hyrox_hybrid';
  if (profile.mainSports.any(
    (MainSport item) =>
        item == MainSport.marathon || item == MainSport.trailRunning,
  )) {
    return 'running_entry_or_race';
  }
  if (profile.mainSports.contains(MainSport.strength) &&
      profile.trainingExperienceLevel != TrainingExperienceLevel.beginner) {
    return 'strength_progression';
  }
  if (profile.mainSports.contains(MainSport.fatLoss)) {
    return 'low_impact_fat_loss';
  }
  return 'sedentary_beginner';
}

class _PlanStatusNotice extends StatelessWidget {
  const _PlanStatusNotice({required this.planState});

  final FourWeekPlanState planState;

  @override
  Widget build(BuildContext context) {
    final bool locked = planState.executionLocked;
    return TrainFlowCard(
      tone: locked ? TrainFlowCardTone.paper : TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            locked ? 'Skill 计划已暂停执行' : '当前计划有更新可用',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            locked
                ? '${planState.clearanceBlockingReason ?? '筛查状态当前无效。'}已自动切换到本地安全计划，历史版本仍保留。'
                : '档案、赛事或 Skill 版本发生变化；当前计划不会被自动替换，请重新生成并确认。',
          ),
        ],
      ),
    );
  }
}

class _ProfilePreflightCard extends ConsumerWidget {
  const _ProfilePreflightCard({required this.profileState});

  final UserProfileState profileState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserProfile profile = profileState.profile;
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '1. 资料预检',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InfoRow(
              label: '建档状态', value: profileState.isCompleted ? '已完成' : '尚未确认'),
          InfoRow(
              label: '年龄门槛', value: profile.age >= 18 ? '符合成人内测范围' : '未满 18 岁'),
          InfoRow(
            label: '主运动',
            value: profile.mainSports.isEmpty
                ? '未选择'
                : profile.mainSports
                    .map((MainSport item) => item.label)
                    .join('、'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<TrainingExperienceLevel>(
            initialValue: profile.trainingExperienceLevel ==
                    TrainingExperienceLevel.unknown
                ? null
                : profile.trainingExperienceLevel,
            decoration: const InputDecoration(
              labelText: '训练经验（生成前必填）',
              helperText: '只用于本地安全分级和枚举化 AI 请求。',
            ),
            items: TrainingExperienceLevel.values
                .where(
                  (TrainingExperienceLevel item) =>
                      item != TrainingExperienceLevel.unknown,
                )
                .map(
                  (TrainingExperienceLevel item) => DropdownMenuItem(
                    value: item,
                    child: Text(item.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (TrainingExperienceLevel? value) {
              if (value == null) return;
              ref.read(userProfileControllerProvider.notifier).save(
                    profile.copyWith(
                      trainingExperienceLevel: value,
                      updatedAt: DateTime.now(),
                    ),
                  );
            },
          ),
        ],
      ),
    );
  }
}

class _ClearanceCard extends StatelessWidget {
  const _ClearanceCard({
    required this.clearanceAsync,
    required this.selectedStatus,
    required this.currentInjuryOrRestriction,
    required this.onStatusChanged,
    required this.onInjuryChanged,
    required this.onOpenOfficial,
    required this.onSave,
  });

  final AsyncValue<PreExerciseClearanceState> clearanceAsync;
  final PreExerciseClearanceStatus selectedStatus;
  final bool currentInjuryOrRestriction;
  final ValueChanged<PreExerciseClearanceStatus?> onStatusChanged;
  final ValueChanged<bool> onInjuryChanged;
  final VoidCallback onOpenOfficial;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final bool isSaving = clearanceAsync.value?.isSaving == true;
    return TrainFlowCard(
      tone: TrainFlowCardTone.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '2. 官方运动前筛查',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '${AppBrand.displayName} 不复制 PAR-Q+ 题目，也不保存答案或许可文件。'
            '请在官方页面完成流程后，只记录结果状态。',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenOfficial,
              icon: const Icon(Icons.open_in_new),
              label: const Text('打开 PAR-Q+ / ePARmed-X+ 官方页面'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PreExerciseClearanceStatus>(
            initialValue:
                selectedStatus == PreExerciseClearanceStatus.notCompleted
                    ? null
                    : selectedStatus,
            decoration: const InputDecoration(labelText: '官方流程结果'),
            items: PreExerciseClearanceStatus.values
                .where(
                  (PreExerciseClearanceStatus item) =>
                      item != PreExerciseClearanceStatus.notCompleted,
                )
                .map(
                  (PreExerciseClearanceStatus item) => DropdownMenuItem(
                    value: item,
                    child: Text(item.label),
                  ),
                )
                .toList(growable: false),
            onChanged: isSaving ? null : onStatusChanged,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: currentInjuryOrRestriction,
            onChanged: isSaving
                ? null
                : (bool? value) => onInjuryChanged(value ?? false),
            title: const Text('目前存在伤病、急性不适或专业人员训练限制'),
            subtitle: const Text('只保存一个本机布尔状态，不上传具体健康信息。'),
          ),
          Text(
            clearanceAsync.when(
              data: (PreExerciseClearanceState value) => value.statusMessage,
              loading: () => '正在读取本机筛查状态…',
              error: (_, __) => '无法读取本机筛查状态，请重试。',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isSaving ? null : onSave,
              child: Text(isSaving ? '正在保存…' : '保存本机筛查状态'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopulationModeCard extends StatelessWidget {
  const _PopulationModeCard({
    required this.options,
    required this.selectedId,
    required this.recommendedId,
    required this.onChanged,
  });

  final List<PopulationTemplateOption> options;
  final String? selectedId;
  final String recommendedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '3. 选择训练模式',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('本机根据档案给出推荐；你可以改选。模式只决定候选模板，不会跳过安全审计。'),
          const SizedBox(height: 12),
          if (options.isEmpty)
            const Text('已审核训练模式目录暂不可用，请使用本地规则计划。')
          else
            for (final PopulationTemplateOption option in options) ...<Widget>[
              Semantics(
                selected: option.id == selectedId,
                button: true,
                label:
                    '${option.title}${option.id == recommendedId ? '，本机推荐' : ''}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(option.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          option.id == selectedId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: option.id == selectedId
                              ? Theme.of(context).colorScheme.primary
                              : TrainFlowTokens.darkTrainingMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                option.id == recommendedId
                                    ? '${option.title} · 本机推荐'
                                    : option.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _populationModeDescription(option.id),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: TrainFlowTokens.darkTrainingMuted,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

String _populationModeDescription(String id) {
  return switch (id) {
    'sedentary_beginner' => '面向久坐办公或训练基础较少的成人，以建立习惯和基础动作为主。',
    'low_impact_fat_loss' => '采用低冲击有氧与基础力量，避免把减脂等同于持续高强度。',
    'strength_progression' => '面向已有训练经验的人群，以力量或增肌的渐进负荷为主。',
    'running_entry_or_race' => '覆盖跑步入门或备赛，结合剩余日期安排跑量与恢复。',
    'hyrox_hybrid' => '组合跑步、力量和 HYROX 专项能力，并保留负荷与技术边界。',
    _ => '使用已审核模板生成候选计划。',
  };
}

class _OutboundSummaryCard extends StatelessWidget {
  const _OutboundSummaryCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final int trainingDays = profile.weeklyTrainingDays.clamp(1, 6);
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '3. 将发送给 AI 的字段',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('发送前会转换为白名单代码，不发送姓名、年龄、身体数据、伤病史、筛查结果、疼痛、HealthKit 或训练日志。'),
          const SizedBox(height: 10),
          InfoRow(label: '训练目标', value: '枚举化目标代码'),
          InfoRow(
            label: '运动项目',
            value: profile.mainSports.isEmpty
                ? '未选择'
                : profile.mainSports
                    .take(2)
                    .map((MainSport item) => item.label)
                    .join('、'),
          ),
          InfoRow(label: '训练经验', value: profile.trainingExperienceLevel.label),
          InfoRow(
            label: '每周训练',
            value: '$trainingDays 天（即使可用 7 天，仍最多安排 6 练并保留休息日）',
          ),
          InfoRow(label: '单次时间', value: '${profile.dailyAvailableMinutes} 分钟'),
          InfoRow(label: '器械', value: profile.equipmentAccessType.label),
        ],
      ),
    );
  }
}

class _GenerationGateCard extends StatelessWidget {
  const _GenerationGateCard({
    required this.blockers,
    required this.generationAsync,
    required this.onGenerate,
    required this.onUseLocalPlan,
  });

  final List<String> blockers;
  final AsyncValue<TrainingPlanGenerationUiState> generationAsync;
  final VoidCallback? onGenerate;
  final VoidCallback onUseLocalPlan;

  @override
  Widget build(BuildContext context) {
    final TrainingPlanGenerationUiState? generation = generationAsync.value;
    final bool serviceEnabled = generation?.capabilities.enabled == true;
    final bool isBusy = generation?.isGenerating == true;
    final bool canGenerate =
        blockers.isEmpty && serviceEnabled && !isBusy && onGenerate != null;
    return TrainFlowCard(
      tone:
          blockers.isEmpty ? TrainFlowCardTone.peach : TrainFlowCardTone.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            blockers.isEmpty ? '资料与筛查已就绪' : '暂时不能生成 Skill 计划',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (blockers.isEmpty)
            Text(
              serviceEnabled
                  ? '下一步将生成结构化处方，并在本机编译与安全审计。'
                  : 'Skill 服务当前不可用，现有计划不会改变。',
            )
          else
            for (final String blocker in blockers) Text('· $blocker'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canGenerate ? onGenerate : null,
              icon: isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(isBusy ? '正在生成并审计…' : '生成四周计划预览'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onUseLocalPlan,
              child: const Text('使用本地规则计划'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            generationAsync.when(
              data: (TrainingPlanGenerationUiState value) =>
                  value.statusMessage,
              loading: () => '正在读取 Skill 能力…',
              error: (_, __) => 'Skill 能力读取失败，现有计划不会改变。',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlanPreviewCard extends StatelessWidget {
  const _PlanPreviewCard({required this.draft});

  final PlanGenerationDraft draft;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '4. 四周计划预览',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InfoRow(
              label: 'Skill',
              value:
                  '${draft.skillRef.displayName} v${draft.skillRef.version}'),
          InfoRow(
            label: '源文件哈希',
            value: _shortHash(draft.skillRef.sourceSha256),
          ),
          InfoRow(label: '运行时哈希', value: draft.skillRef.shortRuntimeHash),
          if (draft.skillRef.fragmentSha256 != null)
            InfoRow(
              label: '专项片段哈希',
              value: _shortHash(draft.skillRef.fragmentSha256!),
            ),
          InfoRow(label: '覆盖范围', value: draft.skillRef.coverage),
          InfoRow(label: '选择原因', value: draft.skillRef.selectionReason),
          InfoRow(label: '模型', value: draft.prescription.generationMeta.model),
          InfoRow(
            label: 'Token 用量',
            value:
                '${draft.prescription.generationMeta.inputTokens} 输入 + ${draft.prescription.generationMeta.outputTokens} 输出',
          ),
          InfoRow(
            label: '处方契约',
            value:
                'v${draft.prescription.generationMeta.contractVersion} · ${draft.prescription.generationMeta.promptContractVersion}',
          ),
          InfoRow(
            label: '缓存状态',
            value: draft.prescription.generationMeta.cacheHit ? '命中缓存' : '本次生成',
          ),
          const SizedBox(height: 4),
          Text(
            '以上哈希只用于 Skill 来源溯源，不代表科学证据。训练依据仍只使用本地 EvidenceSource。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 10),
          for (int week = 1; week <= 4; week += 1)
            _WeekPreview(
              week: week,
              phase: draft.weekPhases.length >= week
                  ? draft.weekPhases[week - 1]
                  : '',
              workouts: draft.plan.workoutDays
                  .where((WorkoutDay item) => item.weekIndex == week)
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

String _shortHash(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

class _AcceptedRecoveryCard extends StatelessWidget {
  const _AcceptedRecoveryCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '处方已确认但尚未激活',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('应用会从已确认的结构化处方重建本地草稿，并先联网复核 Skill 与开关状态。'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onRetry,
              child: const Text('重建草稿并重试激活'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekPreview extends StatelessWidget {
  const _WeekPreview({
    required this.week,
    required this.phase,
    required this.workouts,
  });

  final int week;
  final String phase;
  final List<WorkoutDay> workouts;

  @override
  Widget build(BuildContext context) {
    final List<WorkoutDay> active = workouts
        .where((WorkoutDay item) => item.trainingType != TrainingType.rest)
        .toList(growable: false);
    final int minutes = active.fold<int>(
      0,
      (int sum, WorkoutDay item) => sum + item.estimatedMinutes,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '第 $week 周 · ${_phaseLabel(phase)} · ${active.length} 练 / $minutes 分钟',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            active.isEmpty
                ? '本周仅安排恢复与休息。'
                : active
                    .map(
                      (WorkoutDay item) =>
                          '${item.trainingType.label} ${item.estimatedMinutes} 分钟',
                    )
                    .join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlanAuditCard extends StatelessWidget {
  const _PlanAuditCard({required this.planState});

  final FourWeekPlanState planState;

  @override
  Widget build(BuildContext context) {
    final TrainingRuleAuditReport? report = planState.auditReport;
    final TrainingPrescriptionSafetyAuditReport? prescriptionReport =
        planState.prescriptionAuditReport;
    return TrainFlowCard(
      tone: planState.canActivateDraft
          ? TrainFlowCardTone.outline
          : TrainFlowCardTone.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '5. 本地安全审计',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: planState.canActivateDraft ? '可确认' : '已阻断'),
            ],
          ),
          const SizedBox(height: 8),
          if (report != null)
            for (final TrainingRuleAuditItem item in report.items)
              Text(
                  '${item.severity.label} · ${item.title}：${item.description}'),
          if (prescriptionReport != null) ...<Widget>[
            for (final String warning in prescriptionReport.warnings)
              Text('提醒 · $warning'),
            for (final String failure in prescriptionReport.failures)
              Text('阻断 · $failure'),
          ],
          if (planState.staleReason != null)
            const Text('阻断 · 生成后档案、赛事或当前版本已变化，请重新生成。'),
        ],
      ),
    );
  }
}

class _PlanDifferenceCard extends StatelessWidget {
  const _PlanDifferenceCard({
    required this.activePlan,
    required this.draftPlan,
  });

  final TrainingPlan activePlan;
  final TrainingPlan draftPlan;

  @override
  Widget build(BuildContext context) {
    final int activeSessions = _activeSessionCount(activePlan);
    final int draftSessions = _activeSessionCount(draftPlan);
    final int activeMinutes = _activeMinutes(activePlan);
    final int draftMinutes = _activeMinutes(draftPlan);
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '6. 与当前计划的差异',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InfoRow(
              label: '计划名称', value: '${activePlan.title} → ${draftPlan.title}'),
          InfoRow(label: '四周训练次数', value: '$activeSessions → $draftSessions'),
          InfoRow(label: '四周训练分钟', value: '$activeMinutes → $draftMinutes'),
        ],
      ),
    );
  }
}

class _DraftDecisionCard extends StatelessWidget {
  const _DraftDecisionCard({
    required this.generationAsync,
    required this.canActivate,
    required this.onConfirm,
    required this.onReject,
  });

  final AsyncValue<TrainingPlanGenerationUiState> generationAsync;
  final bool canActivate;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final TrainingPlanGenerationUiState? generation = generationAsync.value;
    final AiArtifact? artifact = generation?.artifact;
    final bool isBusy = generation?.isGenerating == true;
    final bool accepted = artifact?.decision == AiArtifactDecision.accepted;
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            accepted ? '处方已确认，等待本地激活' : '7. 确认或拒绝',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            generation?.statusMessage ?? '生成结果尚未就绪。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: canActivate && !isBusy ? onConfirm : null,
                  child: Text(accepted ? '重试本地激活' : '确认并激活'),
                ),
              ),
              if (!accepted) ...<Widget>[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed:
                      !isBusy && artifact?.isPending == true ? onReject : null,
                  child: const Text('拒绝'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanHistoryCard extends StatelessWidget {
  const _PlanHistoryCard({
    required this.versions,
    required this.activeVersionId,
    required this.onRollback,
  });

  final List<GeneratedPlanVersion> versions;
  final String? activeVersionId;
  final ValueChanged<String> onRollback;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '8. 版本历史',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final GeneratedPlanVersion version in versions) ...<Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(version.plan.title),
              subtitle: Text(
                '${_sourceLabel(version.source)} · ${_dateLabel(version.activatedAt)}',
              ),
              trailing: version.id == activeVersionId
                  ? const ToneBadge(label: '当前')
                  : TextButton(
                      onPressed: () => onRollback(version.id),
                      child: const Text('回退'),
                    ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

List<String> _eligibilityBlockers({
  required UserProfileState profileState,
  required PreExerciseClearance? clearance,
  required DateTime now,
}) {
  final UserProfile profile = profileState.profile;
  return <String>[
    if (!profileState.isCompleted) '请先完成并确认训练档案。',
    if (profile.age < 18) 'V1 仅开放给 18 岁以上成人内测者。',
    if (profile.mainSports.isEmpty) '请先选择主运动。',
    if (profile.mainSports.contains(MainSport.rehab))
      '康复或受监督训练不进入 V1 Skill 计划。',
    if (profile.trainingExperienceLevel == TrainingExperienceLevel.unknown)
      '请补充训练经验等级。',
    if (profile.weeklyTrainingDays < 1) '每周至少需要 1 个可训练日。',
    if (profile.dailyAvailableMinutes < 20) '单次可用时间至少需要 20 分钟。',
    if (clearance == null)
      '正在读取本机筛查状态。'
    else if (!clearance.isValidAt(now))
      clearance.blockingReasonAt(now),
  ];
}

int _activeSessionCount(TrainingPlan plan) => plan.workoutDays
    .where((WorkoutDay item) => item.trainingType != TrainingType.rest)
    .length;

int _activeMinutes(TrainingPlan plan) => plan.workoutDays
    .where((WorkoutDay item) => item.trainingType != TrainingType.rest)
    .fold<int>(0, (int sum, WorkoutDay item) => sum + item.estimatedMinutes);

String _phaseLabel(String value) => switch (value) {
      'baseline' || 'base' => '基础期',
      'build' => '强化期',
      'specific' => '专项期',
      'deload' => '减量期',
      'taper' => '赛前减量',
      'race' => '比赛期',
      'post_race' => '赛后恢复',
      _ => '计划期',
    };

String _sourceLabel(GeneratedPlanSource source) => switch (source) {
      GeneratedPlanSource.skillAi => 'Skill AI',
      GeneratedPlanSource.localRules => '本地规则',
      GeneratedPlanSource.legacy => '旧版导入',
    };

String _dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
