import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ai_artifact.dart';
import '../../../data/models/generated_training_plan.dart';
import '../../../data/models/adaptation_signals.dart';
import '../../../data/models/plan_revision_proposal.dart';
import '../../../data/models/plan_revision_trigger_snapshot.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/models/weekly_report.dart';
import '../../../data/repositories/weekly_report_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../ai_center/application/ai_artifact_controller.dart';
import '../../ai_center/data/plan_revision_api_models.dart';
import '../../first_run_onboarding/application/first_run_onboarding_controller.dart';
import '../../first_run_onboarding/application/membership_controller.dart';
import '../../profile/application/training_schedule_controller.dart';
import '../../profile/application/user_profile_controller.dart';
import '../../training_log/application/training_log_controller.dart';
import 'four_week_plan_controller.dart';

final planRevisionControllerProvider =
    NotifierProvider<PlanRevisionController, PlanRevisionState>(
  PlanRevisionController.new,
);

class PlanRevisionState {
  final PlanRevisionProposal? proposal;
  final PlanRevisionTriggerSnapshot? triggerSnapshot;
  final bool isBusy;
  final String statusMessage;

  const PlanRevisionState({
    required this.proposal,
    required this.triggerSnapshot,
    required this.isBusy,
    required this.statusMessage,
  });

  const PlanRevisionState.initial()
      : proposal = null,
        triggerSnapshot = null,
        isBusy = false,
        statusMessage = '仅连续漏练、两天以上日程变化、器械变化或周期冲突才会请求云端重排。';

  PlanRevisionState copyWith({
    PlanRevisionProposal? proposal,
    PlanRevisionTriggerSnapshot? triggerSnapshot,
    bool clearProposal = false,
    bool? isBusy,
    String? statusMessage,
  }) =>
      PlanRevisionState(
        proposal: clearProposal ? null : proposal ?? this.proposal,
        triggerSnapshot: triggerSnapshot ?? this.triggerSnapshot,
        isBusy: isBusy ?? this.isBusy,
        statusMessage: statusMessage ?? this.statusMessage,
      );
}

class PlanRevisionController extends Notifier<PlanRevisionState> {
  @override
  PlanRevisionState build() {
    bindFeatureController(ref, 'feature.training_plan', 'revision', this);
    final FourWeekPlanState planState =
        ref.watch(fourWeekPlanControllerProvider);
    final GeneratedPlanVersion? activeVersion = planState.history
        .where(
            (GeneratedPlanVersion item) => item.id == planState.activeVersionId)
        .firstOrNull;
    if (activeVersion == null) return const PlanRevisionState.initial();
    final UserProfile profile =
        ref.watch(userProfileControllerProvider).profile;
    final LocalStorageService storage = ref.watch(localStorageServiceProvider);
    final List<WeeklyReport> reports =
        PersistedWeeklyReportRepository(storage).listReports();
    final PlanRevisionTriggerSnapshot snapshot =
        const PlanRevisionTriggerService().evaluate(
      activeVersion: activeVersion,
      schedule: ref.watch(trainingScheduleControllerProvider).workouts,
      logs: ref.watch(trainingLogControllerProvider),
      currentEquipmentCodes: _equipmentCodes(profile.equipmentAccessType),
      currentRace: planState.activeRace,
      latestWeeklyReport: reports.firstOrNull,
      now: DateTime.now(),
    );
    return PlanRevisionState(
      proposal: null,
      triggerSnapshot: snapshot,
      isBusy: false,
      statusMessage: snapshot.localSafetyOnly
          ? '检测到疼痛红线或保护性周报：仅生成本地暂停高强度与恢复建议，不上传云端。'
          : snapshot.shouldSuggest
              ? '已生成待处理重排建议；点击后才会消耗 Token。'
              : '当前没有达到结构性重排阈值。',
    );
  }

  Future<bool> propose({
    int? missedSessions,
    int? changedScheduleDays,
    bool? equipmentChanged,
    bool? remainingCycleConflict,
  }) async {
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.training_plan', dependencies: [
      'feature.ai_center',
      ...ref
          .read(fourWeekPlanControllerProvider)
          .generation
          .pluginRefs
          .map((source) => source.id)
    ]);
    if (state.isBusy) return false;
    if (paidPlanGenerationGateEnabled) {
      final MembershipUiState membership =
          await ref.read(membershipControllerProvider.future);
      operation.checkActive();
      if (!membership.entitlement.canGeneratePlan) {
        state = state.copyWith(
          statusMessage: '动态重排需要有效会员；当前计划不会改变。',
        );
        return false;
      }
    }
    final PlanRevisionTriggerSnapshot? trigger = state.triggerSnapshot;
    final int actualMissed = trigger?.missedSessions ?? missedSessions ?? 0;
    final int actualScheduleChanges =
        trigger?.changedScheduleDays ?? changedScheduleDays ?? 0;
    final bool actualEquipmentChanged =
        trigger?.equipmentChanged ?? equipmentChanged ?? false;
    final bool actualCycleConflict =
        trigger?.remainingCycleConflict ?? remainingCycleConflict ?? false;
    if (trigger?.localSafetyOnly ?? false) {
      state = state.copyWith(
        statusMessage: '安全红线已在本机处理：暂停高强度并优先恢复，未向云端发送任何健康内容。',
      );
      return false;
    }
    if (actualMissed < 2 &&
        actualScheduleChanges < 2 &&
        !actualEquipmentChanged &&
        !actualCycleConflict) {
      state = state.copyWith(
        statusMessage: '当前变化可由本地单日调整处理，不需要消耗 Token。',
      );
      return false;
    }
    final FourWeekPlanState planState =
        ref.read(fourWeekPlanControllerProvider);
    final GeneratedPlanVersion? activeVersion = planState.history
        .where(
          (GeneratedPlanVersion item) => item.id == planState.activeVersionId,
        )
        .firstOrNull;
    final currentPrescription = activeVersion?.prescription;
    if (activeVersion == null || currentPrescription == null) {
      state = state.copyWith(
        statusMessage: '当前计划缺少可验证的结构化处方，请重新生成计划后再使用周期重排。',
      );
      return false;
    }
    final DateTime today = DateTime.now();
    final List<DateTime> remainingDates = ref
        .read(trainingScheduleControllerProvider)
        .workouts
        .map((item) => item.scheduledDate)
        .where((DateTime item) => !item.isBefore(DateTime(
              today.year,
              today.month,
              today.day,
            )))
        .toSet()
        .toList(growable: false)
      ..sort();
    if (remainingDates.length < 2) {
      state = state.copyWith(
        statusMessage: '剩余日程不足两天，请先完善可训练时间；当前计划不会改变。',
      );
      return false;
    }
    final UserProfile profile = ref.read(userProfileControllerProvider).profile;
    final List<String> safetyCodes = <String>[
      ...?trigger?.safetyConstraintCodes,
      if (trigger == null) 'keep_recovery_spacing',
      if (trigger == null && (actualMissed >= 2 || actualCycleConflict))
        'no_increase',
    ];
    state = state.copyWith(
      isBusy: true,
      clearProposal: true,
      statusMessage: '正在生成剩余周期差异…',
    );
    PlanRevisionProposal? proposal;
    try {
      proposal = await readFeatureController<AiArtifactController>(
              ref,
              'feature.ai_center',
              'controller',
              () => ref.read(aiArtifactControllerProvider.notifier))
          .generatePlanRevision(
        PlanRevisionRequest(
          clientContextDigest:
              currentPrescription.generationMeta.clientContextDigest,
          remainingDates: remainingDates,
          completedSessions: (trigger?.completedSessions ?? 0).clamp(0, 28),
          missedSessions: actualMissed.clamp(0, 28),
          scheduleChangeDates: trigger?.changedScheduleDates ??
              remainingDates.take(actualScheduleChanges.clamp(0, 14)).toList(),
          availableMinutes: profile.dailyAvailableMinutes,
          equipmentAccess: _equipmentCodes(profile.equipmentAccessType),
          equipmentChanged: actualEquipmentChanged,
          safetyConstraintCodes: safetyCodes,
          adaptationSignals: trigger == null
              ? null
              : AdaptationSignals(
                  completionRateBand: trigger.completionRateBand,
                  loadTrendCode: trigger.loadTrendCode,
                  recoveryRiskCode: trigger.recoveryRiskCode,
                  selectedDirectionCode: trigger.selectedDirectionCode,
                ),
          currentPrescription: currentPrescription,
        ),
        sourceOperation: operation,
      );
      operation.checkActive();
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          isBusy: false,
          statusMessage: _revisionFailureMessage(error, action: '生成重排'),
        );
      }
      return false;
    }
    if (proposal == null) {
      state = state.copyWith(
        isBusy: false,
        statusMessage: ref.read(aiArtifactControllerProvider).statusMessage,
      );
      return false;
    }
    try {
      await readFeatureController<FourWeekPlanController>(
          ref,
          'feature.training_plan',
          'fourWeek',
          () => ref.read(fourWeekPlanControllerProvider.notifier)).createDraft(
        prescription: proposal.revisedPrescription,
        artifact: proposal.artifact,
        sourceOperation: operation,
      );
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          isBusy: false,
          statusMessage: _revisionFailureMessage(error, action: '保存重排草稿'),
        );
      }
      return false;
    }
    state = state.copyWith(
      proposal: proposal,
      isBusy: false,
      statusMessage: '已生成新旧差异；确认前当前计划不会改变。',
    );
    return true;
  }

  Future<bool> confirm() async {
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.training_plan', dependencies: [
      'feature.ai_center',
      ...ref
          .read(fourWeekPlanControllerProvider)
          .generation
          .pluginRefs
          .map((source) => source.id)
    ]);
    final PlanRevisionProposal? proposal = state.proposal;
    if (proposal == null || state.isBusy) return false;
    state = state.copyWith(isBusy: true, statusMessage: '正在确认并激活重排版本…');
    AiArtifact? accepted;
    try {
      accepted = await operation.commit(() =>
          readFeatureController<AiArtifactController>(
              ref,
              'feature.ai_center',
              'controller',
              () => ref.read(aiArtifactControllerProvider.notifier)).decide(
            artifact: proposal.artifact,
            decision: AiArtifactDecision.accepted,
          ));
      operation.checkActive();
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          isBusy: false,
          statusMessage: _revisionFailureMessage(error, action: '确认重排'),
        );
      }
      return false;
    }
    if (accepted == null ||
        accepted.id != proposal.artifact.id ||
        accepted.artifactType != 'plan_revision_v1' ||
        accepted.schemaVersion != 1 ||
        accepted.decision != AiArtifactDecision.accepted ||
        jsonEncode(accepted.payload) != jsonEncode(proposal.artifact.payload)) {
      state = state.copyWith(
        isBusy: false,
        statusMessage: '服务端确认结果与重排草稿不一致，当前计划不会改变。',
      );
      return false;
    }
    bool activated;
    try {
      activated = await ref
          .read(fourWeekPlanControllerProvider.notifier)
          .activateDraft(artifactId: accepted.id);
      operation.checkActive();
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          isBusy: false,
          statusMessage: _revisionFailureMessage(error, action: '激活重排'),
        );
      }
      return false;
    }
    state = state.copyWith(
      isBusy: false,
      clearProposal: activated,
      statusMessage: activated
          ? '重排版本已激活，原计划已保留在版本历史中。'
          : ref.read(fourWeekPlanControllerProvider).statusMessage,
    );
    return activated;
  }

  Future<void> reject() async {
    final operation = ref
        .read(featureAccessProvider)
        .beginOperation('feature.training_plan', dependencies: [
      'feature.ai_center',
      ...ref
          .read(fourWeekPlanControllerProvider)
          .generation
          .pluginRefs
          .map((source) => source.id)
    ]);
    final PlanRevisionProposal? proposal = state.proposal;
    if (proposal == null || state.isBusy) return;
    state = state.copyWith(isBusy: true, statusMessage: '正在拒绝重排草稿…');
    AiArtifact? rejected;
    try {
      rejected = await operation.commit(() =>
          readFeatureController<AiArtifactController>(
              ref,
              'feature.ai_center',
              'controller',
              () => ref.read(aiArtifactControllerProvider.notifier)).decide(
            artifact: proposal.artifact,
            decision: AiArtifactDecision.rejected,
          ));
      operation.checkActive();
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          isBusy: false,
          statusMessage: _revisionFailureMessage(error, action: '拒绝重排'),
        );
      }
      return;
    }
    if (rejected == null) {
      state = state.copyWith(
        isBusy: false,
        statusMessage: ref.read(aiArtifactControllerProvider).statusMessage,
      );
      return;
    }
    final bool matches = rejected.id == proposal.artifact.id &&
        rejected.artifactType == proposal.artifact.artifactType &&
        rejected.schemaVersion == proposal.artifact.schemaVersion &&
        rejected.contextDigest == proposal.artifact.contextDigest &&
        rejected.decision == AiArtifactDecision.rejected &&
        jsonEncode(rejected.payload) == jsonEncode(proposal.artifact.payload);
    if (!matches) {
      state = state.copyWith(
        isBusy: false,
        statusMessage: '服务端拒绝结果与当前重排草稿不一致，草稿已保留，请重试。',
      );
      return;
    }
    try {
      await readFeatureController<FourWeekPlanController>(
          ref,
          'feature.training_plan',
          'fourWeek',
          () => ref.read(fourWeekPlanControllerProvider.notifier)).rejectDraft(
        artifactId: proposal.artifact.id,
        sourceOperation: operation,
      );
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          isBusy: false,
          statusMessage: _revisionFailureMessage(error, action: '清理重排草稿'),
        );
      }
      return;
    }
    state = state.copyWith(
      clearProposal: true,
      isBusy: false,
      statusMessage: '已拒绝重排草稿，当前计划未改变。',
    );
  }
}

String _revisionFailureMessage(Object error, {required String action}) {
  if (error is StateError) {
    return '${error.message}；$action未完成，请重新操作。';
  }
  return '$action失败，重排草稿与当前计划均已保留，请重试。';
}

List<String> _equipmentCodes(EquipmentAccessType value) => switch (value) {
      EquipmentAccessType.none => const <String>['bodyweight'],
      EquipmentAccessType.basicHome => const <String>[
          'bodyweight',
          'dumbbell',
        ],
      EquipmentAccessType.gym || EquipmentAccessType.mixed => const <String>[
          'bodyweight',
          'dumbbell',
          'barbell',
          'kettlebell',
          'machines',
          'cardio_machines',
        ],
    };
