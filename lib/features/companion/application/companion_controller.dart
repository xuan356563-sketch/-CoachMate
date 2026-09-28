import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/core/constants/app_brand.dart';
import 'package:trainflow_ai/data/models/body_data_quality.dart';
import 'package:trainflow_ai/data/models/ai_chat.dart';
import 'package:trainflow_ai/data/models/pain_log.dart';
import 'package:trainflow_ai/data/models/pet.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/data/repositories/pain_log_repository.dart';
import 'package:trainflow_ai/data/repositories/ai_chat_repository.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/companion/application/companion_arbitrator.dart';
import 'package:trainflow_ai/features/companion/application/coach_turn_parser.dart';
import 'package:trainflow_ai/features/companion/application/coach_remote_coordinator.dart';
import 'package:trainflow_ai/features/companion/application/companion_database_provider.dart';
import 'package:trainflow_ai/features/companion/application/companion_notification_scheduler.dart';
import 'package:trainflow_ai/features/companion/application/companion_state_resolver.dart';
import 'package:trainflow_ai/features/companion/application/training_state_reader.dart';
import 'package:trainflow_ai/features/companion/data/coach_local_repository.dart';
import 'package:trainflow_ai/features/companion/data/coach_api.dart';
import 'package:trainflow_ai/features/companion/data/companion_repository.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/companion/domain/companion_copy_library.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/body_data_quality_service.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';
import 'package:trainflow_ai/plugins/application/feature_access.dart';
import 'package:trainflow_ai/plugins/application/feature_controller_binding.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';

final companionClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

final companionNotificationSchedulerProvider =
    Provider<CompanionNotificationScheduler>(
  (Ref ref) =>
      CompanionNotificationScheduler(SystemTrainingNotificationGateway()),
);

/// 首期默认关闭；灰度环境可覆盖为 shadow，验收后再覆盖为严格交集。
final coachCloudModeProvider =
    Provider<CoachCloudMode>((Ref ref) => CoachCloudMode.disabled);

final companionControllerProvider =
    AsyncNotifierProvider<CompanionController, CompanionFeedState>(
  CompanionController.new,
  retry: (int _, Object __) => null,
);

enum CompanionFeedStatus { loading, needsFirstEgg, unavailable, ready }

class CompanionFeedState {
  const CompanionFeedState({
    required this.status,
    required this.statusMessage,
    this.relationship,
    this.pet,
    this.relationshipState,
    this.context,
    this.messages = const <CompanionMessage>[],
    this.coachAvailable = false,
  });

  const CompanionFeedState.loading()
      : status = CompanionFeedStatus.loading,
        statusMessage = '正在读取本机训练、活动与伙伴记录。',
        relationship = null,
        pet = null,
        relationshipState = null,
        context = null,
        messages = const <CompanionMessage>[],
        coachAvailable = false;

  final CompanionFeedStatus status;
  final String statusMessage;
  final CompanionRelationship? relationship;
  final PetCompanion? pet;
  final RelationshipState? relationshipState;
  final CompanionContext? context;
  final List<CompanionMessage> messages;
  final bool coachAvailable;

  String get displayName {
    final String? localName = relationship?.companionName?.trim();
    if (localName?.isNotEmpty == true) {
      return normalizeBalanceRaccoonDisplayName(localName!);
    }
    return pet?.displayName ?? balanceRaccoonDisplayName;
  }
}

/// 把既有训练、活动、疼痛和宠物账本以只读方式组装为搭子上下文。
/// 没有可靠事实时宁可不生成普通消息，也不会补造健康指标或训练阈值。
class CompanionController extends AsyncNotifier<CompanionFeedState> {
  static const String _featureId = 'feature.companion';
  late CompanionRepository _repository;
  late DateTime Function() _clock;
  late TrainingScheduleState _schedule;
  late List<TrainingLog> _trainingLogs;
  late List<PainLog> _painLogs;
  late PetState _petState;
  late BodyDataQualityReport _bodyDataQuality;
  late String _athleteProfileId;
  late String _accountId;
  CoachLocalRepository? _coachRepository;
  CoachRemoteCoordinator? _remoteCoordinator;
  ProviderSubscription<List<TrainingLog>>? _trainingLogSubscription;
  int _notificationEpoch = 0;
  bool _resumeWithoutBuildWrites = false;

  @override
  Future<CompanionFeedState> build() async {
    _trainingLogSubscription = null;
    final bool resumeWithoutBuildWrites = _resumeWithoutBuildWrites;
    _resumeWithoutBuildWrites = false;
    final companionDatabase = ref.watch(companionDatabaseGatewayProvider);
    if (companionDatabase == null) {
      return const CompanionFeedState(
        status: CompanionFeedStatus.unavailable,
        statusMessage: '搭子本地存储暂不可用，未写入任何陪伴记录。',
      );
    }
    final coachDatabase = ref.watch(coachDatabaseGatewayProvider);
    final AsyncValue<PetState> petValue = ref.watch(petControllerProvider);
    if (!petValue.hasValue) return const CompanionFeedState.loading();
    _petState = petValue.requireValue;
    if (_petState.status == PetStateStatus.needsFirstEgg) {
      return const CompanionFeedState(
        status: CompanionFeedStatus.needsFirstEgg,
        statusMessage: '先选择袋小满，它会在已有训练和活动事实里陪你。',
      );
    }
    if (_petState.status != PetStateStatus.ready ||
        _petState.activeCompanion == null) {
      return CompanionFeedState(
        status: CompanionFeedStatus.unavailable,
        statusMessage: _petState.statusMessage,
      );
    }
    _repository = CompanionRepository(companionDatabase,
        clock: ref.watch(companionClockProvider));
    _coachRepository = coachDatabase == null
        ? null
        : CoachLocalRepository(
            coachDatabase,
            clock: ref.watch(companionClockProvider),
          );
    final CoachCloudMode cloudMode = ref.watch(coachCloudModeProvider);
    _remoteCoordinator = cloudMode == CoachCloudMode.disabled
        ? null
        : CoachRemoteCoordinator(
            ref.watch(coachApiProvider),
            mode: cloudMode,
            cloudConsentGranted: () =>
                ref
                    .read(localStorageServiceProvider)
                    .readJson(coachCloudConsentStorageKey)?['granted'] ==
                true,
          );
    _clock = ref.watch(companionClockProvider);
    _schedule = ref.watch(trainingScheduleControllerProvider);
    _trainingLogs = ref.watch(trainingLogRepositoryProvider).listLogs();
    _bodyDataQuality = BodyDataQualityService().buildReport(
      ref.watch(bodyMetricControllerProvider).metrics,
    );
    _painLogs = PersistedPainLogRepository(
      ref.watch(localStorageServiceProvider),
    ).listPainLogs();
    _athleteProfileId = _petState.activeCompanion!.athleteProfileId;
    _accountId = ref.watch(authControllerProvider).value?.user?.userId ??
        'local-preview-user';
    bindFeatureController(
      ref,
      _featureId,
      'controller',
      this,
      cleanup: _pauseResources,
      onRestore: _restoreResourcesAfterRollback,
    );
    ref.listen<bool>(featureEnabledProvider(_featureId), (_, bool enabled) {
      if (!enabled) return;
      _resumeWithoutBuildWrites = true;
      ref.invalidateSelf();
    });
    if (ref.read(featureAccessProvider).isWritable(_featureId)) {
      _startTrainingLogSubscription();
    }
    if (resumeWithoutBuildWrites ||
        !ref.read(featureAccessProvider).isWritable(_featureId)) {
      final CompanionFeedState readOnly = await _loadReadOnly();
      if (resumeWithoutBuildWrites) {
        unawaited(Future<void>.delayed(Duration.zero, _restoreResources));
      }
      return readOnly;
    }
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    await operation.commit(() async {
      await _repository.purgeExpiredConversationMessages(_athleteProfileId);
      await _importLegacyAiChat(ref.read(localStorageServiceProvider));
    });
    return _load(createTodayMessage: true, operation: operation);
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    state = const AsyncLoading<CompanionFeedState>();
    if (!ref.read(featureAccessProvider).isWritable(_featureId)) {
      state = await AsyncValue.guard(_loadReadOnly);
      return;
    }
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    state = await AsyncValue.guard(
      () => _load(createTodayMessage: true, operation: operation),
    );
  }

  Future<void> markAllRead() async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    final CompanionFeedState? current = state.value;
    if (current?.status != CompanionFeedStatus.ready) return;
    await operation.commit(() async {
      for (final CompanionMessage message in current!.messages.where(
        (CompanionMessage item) => item.isUnread,
      )) {
        await _repository.markOpened(message.messageId);
      }
      final CompanionRelationship? relationship = current.relationship;
      if (relationship != null && relationship.consecutiveUnopened != 0) {
        await _repository.saveRelationship(_copyRelationship(
          relationship,
          consecutiveUnopened: 0,
        ));
      }
    });
    if (ref.mounted) await refresh();
  }

  Future<void> dismissToday({required CompanionMessage message}) async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    if (message.actions.every(
      (CompanionAction action) => action.kind != CompanionActionKind.dismiss,
    )) {
      return;
    }
    final DateTime now = _clock();
    final List<CompanionMessage> history =
        await _repository.listMessages(_athleteProfileId, limit: 200);
    operation.checkActive();
    final CompanionCopyVariant? copy = pickCompanionCopyVariant(
      intent: CompanionIntent.missedWorkout,
      kind: CompanionCopyVariantKind.dismissAck,
      variables: const <String, String>{},
      usedVariantIds: const <String>{},
      history: history
          .map((CompanionMessage item) => CompanionCopyHistory(
                variantId: item.copyVariantId,
                createdAt: item.createdAt,
              ))
          .toList(growable: false),
      now: now,
      random: Random(now.microsecondsSinceEpoch),
    );
    await operation.commit(() async {
      await _repository.recordAction(
        messageId: message.messageId,
        actionId: 'dismiss-today',
      );
      if (copy == null) return;
      await _repository.saveMessage(CompanionMessage(
        messageId: _messageId('dismiss', now),
        athleteProfileId: _athleteProfileId,
        localDate: _localDate(now),
        intent: CompanionIntent.missedWorkout,
        copyVariantId: copy.id,
        relationshipState:
            state.value?.relationshipState ?? RelationshipState.steady,
        deliveryKind: CompanionDeliveryKind.reactive,
        privacyLevel: PrivacyLevel.l0,
        body: copy.render(const <String, String>{}),
        createdAt: now,
        deliveredAt: now,
      ));
    });
    if (ref.mounted) await refresh();
  }

  /// 页面只提交用户文本；训练快照必须在这里从结构化仓储强制读取。
  Future<void> sendUserMessage(String input) async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    final String text = input.trim();
    final CompanionFeedState? current = state.value;
    final CoachLocalRepository? coachRepository = _coachRepository;
    if (text.isEmpty ||
        current?.status != CompanionFeedStatus.ready ||
        coachRepository == null) {
      return;
    }
    final DateTime now = _clock();
    final String turnId = 'turn-${now.toUtc().microsecondsSinceEpoch}';
    final String threadId = 'coach-$_athleteProfileId';
    final CoachParsedTurn parsed = const CoachTurnParser().parse(text);
    final RelationshipState relationshipState =
        current!.relationshipState ?? RelationshipState.steady;
    await operation.commit(() => _repository.saveMessage(CompanionMessage(
          messageId: '$turnId-user',
          athleteProfileId: _athleteProfileId,
          localDate: _localDate(now),
          intent: CompanionIntent.checkinAck,
          copyVariantId: 'coach-user-v1',
          relationshipState: relationshipState,
          deliveryKind: CompanionDeliveryKind.reactive,
          privacyLevel: PrivacyLevel.l0,
          body: text,
          messageRole: CompanionMessageRole.user,
          threadId: threadId,
          turnId: turnId,
          retention: CompanionMessageRetention.conversation30Days,
          createdAt: now,
          deliveredAt: now,
          openedAt: now,
        )));

    final CoachMemoryDraft? memoryDraft = parsed.memoryDraft;
    CoachMemoryV1? writtenMemory;
    if (memoryDraft != null) {
      writtenMemory = _buildMemory(
        draft: memoryDraft,
        turnId: turnId,
        sourceText: text,
        now: now,
      );
      await operation.commit(() => coachRepository.saveMemory(writtenMemory!));
    }

    TrainingStateSnapshotV1? snapshot;
    CoachDecisionEnvelopeV1? envelope;
    CoachVerificationState verificationState = CoachVerificationState.localOnly;
    String? remoteDecisionDigest;
    String? localDecisionDigest;
    CoachRenderedReply rendered;
    List<CompanionFact> facts = const <CompanionFact>[];
    if (parsed.intent.requiresTrainingState) {
      snapshot = LocalTrainingStateReader(
        schedule: _schedule,
        trainingLogs: _trainingLogs,
        painLogs: _painLogs,
        bodyDataQuality: _bodyDataQuality,
      ).readCurrent(athleteProfileId: _athleteProfileId, now: now);
      await operation.commit(() => coachRepository.saveSnapshot(snapshot!));
      final List<CoachMemoryV1> allMemories =
          await coachRepository.listMemories(_athleteProfileId);
      final CoachMemoryRetrieval retrieval = const CoachMemoryRetriever()
          .retrieve(memories: allMemories, now: now);
      final String memorySetDigest = CoachDigest.sha256(
        retrieval.decisionMemories
            .map((CoachMemoryV1 memory) => <String, Object?>{
                  'memory_id': memory.memoryId,
                  'version': memory.version,
                  'updated_at': memory.updatedAt.toUtc().toIso8601String(),
                })
            .toList(growable: false),
      );
      final TrainingDecisionV1 decision = const CoachKernel().evaluate(
        snapshot: snapshot,
        intent: parsed.intent,
        now: now,
      );
      envelope = const CoachSafetyGate().apply(
        snapshot: snapshot,
        training: decision,
        turnId: turnId,
        memorySetDigest: memorySetDigest,
      );
      localDecisionDigest = CoachDigest.sha256(envelope.toJson());
      final CoachRemoteCoordinator? remote = _remoteCoordinator;
      if (remote != null) {
        final CoachRemoteResult remoteResult = await remote.evaluate(
          snapshot: snapshot,
          memories: allMemories,
          local: envelope,
          intent: parsed.intent,
          emotion: parsed.emotion,
        );
        operation.checkActive();
        envelope = remoteResult.envelope;
        verificationState = remoteResult.verificationState;
        remoteDecisionDigest = remoteResult.remoteDigest;
      }
      rendered = const DeterministicCompanionRenderer().render(
        envelope: envelope,
        communication: CommunicationPlanV1(
          chosenActionId:
              envelope.allowed.isEmpty ? null : envelope.allowed.first.actionId,
          tone: CoachTone.warm,
          memoryIdsToSurface: retrieval.surfaceableMemories
              .map((CoachMemoryV1 memory) => memory.memoryId)
              .toList(growable: false),
        ),
        memories: retrieval.decisionMemories,
        verificationState: verificationState,
      );
      facts = _factsForSnapshot(snapshot);
    } else {
      rendered = _renderNonTrainingTurn(
        text: text,
        parsed: parsed,
        writtenMemory: writtenMemory,
      );
    }

    final String traceId = '$turnId-trace';
    final Map<String, Object?> decisionPayload = envelope?.toJson() ??
        <String, Object?>{
          'turn_id': turnId,
          'intent': parsed.intent.storageValue,
          'memory_id': writtenMemory?.memoryId,
          'actions': rendered.actions
              .map((CoachRenderedAction action) => action.actionId)
              .toList(growable: false),
        };
    await operation.commit(() async {
      await coachRepository.saveTrace(CoachTurnTraceV1(
        traceId: traceId,
        athleteProfileId: _athleteProfileId,
        turnId: turnId,
        intent: parsed.intent,
        emotion: parsed.emotion,
        snapshotId: snapshot?.snapshotId,
        inputDigest: CoachDigest.sha256(<String, Object?>{
          'turn_id': turnId,
          'intent': parsed.intent.storageValue,
          'emotion': parsed.emotion.name,
        }),
        localDecisionDigest:
            localDecisionDigest ?? CoachDigest.sha256(decisionPayload),
        remoteDecisionDigest: remoteDecisionDigest,
        finalDecisionDigest: CoachDigest.sha256(decisionPayload),
        verificationState: verificationState,
        reasonCodes: envelope?.reasonCodes ??
            <String>[
              writtenMemory == null ? 'companion_ack' : 'memory_recorded'
            ],
        createdAt: now,
        expiresAt: now.add(const Duration(days: 90)),
      ));
      await _repository.saveMessage(CompanionMessage(
        messageId: '$turnId-companion',
        athleteProfileId: _athleteProfileId,
        localDate: _localDate(now),
        intent: CompanionIntent.checkinAck,
        copyVariantId: 'coach-static-v1',
        relationshipState: relationshipState,
        deliveryKind: CompanionDeliveryKind.reactive,
        privacyLevel: PrivacyLevel.l0,
        body: rendered.text,
        facts: facts,
        actions: rendered.actions
            .map((CoachRenderedAction action) => CompanionAction(
                  actionId: action.actionId,
                  label: action.label,
                  kind: CompanionActionKind.primary,
                  route: action.route,
                  effect: action.requiresConfirmation
                      ? CompanionActionEffect.requestExistingAdjustment
                      : CompanionActionEffect.openExistingRoute,
                ))
            .toList(growable: false),
        messageRole: CompanionMessageRole.companion,
        threadId: threadId,
        turnId: turnId,
        sourceSnapshotId: snapshot?.snapshotId,
        traceId: traceId,
        retention: CompanionMessageRetention.conversation30Days,
        verificationState: rendered.verificationState,
        createdAt: now.add(const Duration(microseconds: 1)),
        deliveredAt: now,
      ));
    });
    if (!ref.mounted) return;
    state = await AsyncValue.guard(
      () => _load(createTodayMessage: false, operation: operation),
    );
  }

  Future<void> updatePreferences({
    String? companionName,
    DisturbTier? disturbTier,
    bool? notificationsEnabled,
    bool? notificationDetailEnabled,
    Set<CompanionBoundaryTopic>? boundaries,
  }) async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    final CompanionFeedState? current = state.value;
    final CompanionRelationship? relationship = current?.relationship;
    if (current == null || relationship == null) return;
    final Set<CompanionBoundaryTopic> nextBoundaries =
        Set<CompanionBoundaryTopic>.from(boundaries ?? relationship.boundaries)
          ..add(CompanionBoundaryTopic.appearance);
    CompanionRelationship nextRelationship = _copyRelationship(
      relationship,
      companionName: companionName ?? relationship.companionName,
      disturbTier: disturbTier ?? relationship.disturbTier,
      notificationsEnabled:
          notificationsEnabled ?? relationship.notificationsEnabled,
      notificationDetailEnabled:
          notificationDetailEnabled ?? relationship.notificationDetailEnabled,
      boundaries: nextBoundaries,
    );
    await operation.commit(
      () => _repository.saveRelationship(nextRelationship),
    );
    final bool shouldRequestPermission = !relationship.notificationsEnabled &&
        nextRelationship.notificationsEnabled;
    final CompanionNotificationSyncResult notificationResult =
        await _synchronizeNotifications(
      operation: operation,
      scheduler: ref.read(companionNotificationSchedulerProvider),
      relationship: nextRelationship,
      messages: current.messages,
      now: _clock(),
      requestPermission: shouldRequestPermission,
    );
    if (notificationResult.status ==
        CompanionNotificationSyncStatus.permissionDenied) {
      nextRelationship = _copyRelationship(
        nextRelationship,
        notificationsEnabled: false,
      );
      await operation.commit(
        () => _repository.saveRelationship(nextRelationship),
      );
    }
    if (ref.mounted) await refresh();
  }

  Future<CompanionFeedState> _load({
    required bool createTodayMessage,
    required FeatureOperation operation,
  }) async {
    final PetCompanion pet = _petState.activeCompanion!;
    final DateTime now = _clock();
    late CompanionRelationship relationship;
    await operation.commit(() async {
      relationship = await _repository.ensureRelationship(
        athleteProfileId: _athleteProfileId,
        fallbackCompanionName: pet.nickname,
        startedOn: pet.unlockedAt,
      );
    });
    List<CompanionMessage> messages =
        await _repository.listMessages(_athleteProfileId, limit: 200);
    final CompanionContext context = _assembleContext(
      now: now,
      relationship: relationship,
    );
    final RelationshipState resolved = resolveState(context);
    if (relationship.lastResolvedState != resolved) {
      relationship = _copyRelationship(
        relationship,
        lastResolvedState: resolved,
        stateEnteredOn: now,
      );
      await operation.commit(
        () => _repository.saveRelationship(relationship),
      );
    }
    if (createTodayMessage &&
        !messages.any((CompanionMessage item) =>
            item.localDate == _localDate(now) &&
            item.deliveryKind == CompanionDeliveryKind.proactive)) {
      final List<CompanionCandidate> candidates = _candidates(
        now: now,
        context: context,
        relationshipState: resolved,
        history: messages,
      );
      final CompanionArbitrationResult result = arbitrateCompanionCandidates(
        context: context,
        relationshipState: resolved,
        candidates: candidates,
        history: messages,
        planningAt: now,
      );
      for (final PlannedCompanionCandidate selected in result.selected) {
        final CompanionCandidate candidate = selected.candidate;
        if (candidate.deliveryKind != CompanionDeliveryKind.proactive) continue;
        final String messageId = _messageId(candidate.intent.storageValue, now);
        await operation.commit(() => _repository.saveMessage(CompanionMessage(
              messageId: messageId,
              athleteProfileId: _athleteProfileId,
              localDate: _localDate(selected.scheduledAt),
              intent: candidate.intent,
              copyVariantId: candidate.copyVariantId,
              relationshipState: resolved,
              deliveryKind: candidate.deliveryKind,
              privacyLevel: selected.privacyLevel,
              notificationTitle: AppBrand.shortName,
              notificationBody: '你的搭子有话说',
              body: candidate.body,
              facts: candidate.facts,
              actions: candidate.actions,
              scheduledAt: selected.scheduledAt,
              deliveredAt: selected.scheduledAt.isAfter(now) ? null : now,
              notificationId: companionNotificationId(messageId),
              createdAt: now,
            )));
      }
      messages = await _repository.listMessages(_athleteProfileId, limit: 200);
    }
    if (relationship.notificationsEnabled) {
      await _synchronizeNotifications(
        operation: operation,
        scheduler: ref.read(companionNotificationSchedulerProvider),
        relationship: relationship,
        messages: messages,
        now: now,
      );
    }
    return CompanionFeedState(
      status: CompanionFeedStatus.ready,
      statusMessage: messages.isEmpty ? '今天它安静陪着。' : '已按本地事实更新消息。',
      relationship: relationship,
      pet: pet,
      relationshipState: resolved,
      context: context,
      messages: messages,
      coachAvailable: _coachRepository != null,
    );
  }

  Future<CompanionFeedState> _loadReadOnly() async {
    final PetCompanion pet = _petState.activeCompanion!;
    final DateTime now = _clock();
    final CompanionRelationship? relationship =
        await _repository.loadRelationship(_athleteProfileId);
    final List<CompanionMessage> messages =
        await _repository.listMessages(_athleteProfileId, limit: 200);
    final CompanionContext? context = relationship == null
        ? null
        : _assembleContext(now: now, relationship: relationship);
    final RelationshipState? resolved =
        context == null ? null : resolveState(context);
    return CompanionFeedState(
      status: CompanionFeedStatus.ready,
      statusMessage: '伙伴功能已暂停，现有陪伴记录仍可阅读。',
      relationship: relationship,
      pet: pet,
      relationshipState: resolved,
      context: context,
      messages: messages,
      coachAvailable: _coachRepository != null,
    );
  }

  void _startTrainingLogSubscription() {
    if (_trainingLogSubscription != null) return;
    _trainingLogSubscription = ref.listen<List<TrainingLog>>(
      trainingLogControllerProvider,
      (List<TrainingLog>? previous, List<TrainingLog> next) {
        if (previous == next ||
            !ref.read(featureAccessProvider).isWritable(_featureId)) {
          return;
        }
        unawaited(refresh());
      },
    );
  }

  Future<void> _pauseResources() async {
    _notificationEpoch++;
    _trainingLogSubscription?.close();
    _trainingLogSubscription = null;
    await ref.read(companionNotificationSchedulerProvider).cancel();
  }

  Future<void> _restoreResources() async {
    if (!ref.mounted ||
        !ref.read(featureAccessProvider).isWritable(_featureId)) {
      return;
    }
    final CompanionFeedState? current = state.value;
    final CompanionRelationship? relationship = current?.relationship;
    if (relationship?.notificationsEnabled != true) return;
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    await _synchronizeNotifications(
      operation: operation,
      scheduler: ref.read(companionNotificationSchedulerProvider),
      relationship: relationship!,
      messages: current!.messages,
      now: _clock(),
    );
  }

  Future<void> _restoreResourcesAfterRollback() async {
    if (!ref.mounted ||
        !ref.read(featureAccessProvider).isEnabled(_featureId)) {
      return;
    }
    _resumeWithoutBuildWrites = true;
    ref.invalidateSelf();
  }

  Future<CompanionNotificationSyncResult> _synchronizeNotifications({
    required FeatureOperation operation,
    required CompanionNotificationScheduler scheduler,
    required CompanionRelationship relationship,
    required Iterable<CompanionMessage> messages,
    required DateTime now,
    bool requestPermission = false,
  }) {
    final int epoch = ++_notificationEpoch;
    bool isActive() {
      if (epoch != _notificationEpoch) return false;
      try {
        operation.checkActive();
        return true;
      } on StateError {
        return false;
      }
    }

    return rescheduleCompanionNotifications(
      scheduler: scheduler,
      relationship: relationship,
      messages: messages,
      now: now,
      requestPermission: requestPermission,
      isActive: isActive,
    );
  }

  Future<void> _importLegacyAiChat(LocalStorageService storage) async {
    final DateTime now = _clock();
    final List<AiChatSession> sessions =
        PersistedAiChatRepository(storage).listSessions(_accountId, now: now);
    for (final AiChatSession session in sessions) {
      for (final AiChatMessage message in session.messages) {
        if (message.status != AiChatMessageStatus.sent ||
            message.content.trim().isEmpty ||
            message.createdAt
                .isBefore(now.subtract(const Duration(days: 30)))) {
          continue;
        }
        final CompanionMessageRole role = switch (message.role) {
          AiChatMessageRole.user => CompanionMessageRole.user,
          AiChatMessageRole.system => CompanionMessageRole.system,
          AiChatMessageRole.assistant ||
          AiChatMessageRole.local =>
            CompanionMessageRole.companion,
        };
        await _repository.saveMessage(CompanionMessage(
          messageId: 'legacy-ai-${CoachDigest.sha256(<String, Object?>{
                'session_id': session.id,
                'message_id': message.id,
              }).substring(0, 24)}',
          athleteProfileId: _athleteProfileId,
          localDate: _localDate(message.createdAt.toLocal()),
          intent: CompanionIntent.checkinAck,
          copyVariantId: 'legacy-ai-chat-v1',
          relationshipState: RelationshipState.steady,
          deliveryKind: CompanionDeliveryKind.reactive,
          privacyLevel: PrivacyLevel.l0,
          body: message.content,
          messageRole: role,
          threadId: 'legacy-ai-${session.id}',
          retention: CompanionMessageRetention.conversation30Days,
          verificationState: CoachVerificationState.localOnly,
          createdAt: message.createdAt,
          deliveredAt: message.createdAt,
          openedAt: message.createdAt,
        ));
      }
    }
  }

  CoachMemoryV1 _buildMemory({
    required CoachMemoryDraft draft,
    required String turnId,
    required String sourceText,
    required DateTime now,
  }) {
    final bool boundary = draft.category == CoachMemoryCategory.boundary;
    final bool confirmed = draft.isExplicitCommand;
    final DateTime validFrom = now.toUtc();
    return CoachMemoryV1(
      memoryId: 'memory-${CoachDigest.sha256(<String, Object?>{
            'athlete_profile_id': _athleteProfileId,
            'turn_id': turnId,
            'category': draft.category.storageValue,
          }).substring(0, 24)}',
      athleteProfileId: _athleteProfileId,
      category: draft.category,
      subject: 'athlete_preference',
      value: <String, Object?>{'statement': draft.displayText},
      displayText: draft.displayText,
      sources: <CoachSourceRef>[
        CoachSourceRef(
          sourceKind: 'user_statement',
          sourceLocalId: turnId,
          sourceDigest: CoachDigest.sha256(sourceText),
          observedAt: now,
          summaryKey: '用户在伙伴对话中的表达',
        ),
      ],
      confidenceBps: confirmed ? 10000 : 7000,
      importanceBps: 5000,
      sensitivity:
          boundary ? CoachMemorySensitivity.medium : CoachMemorySensitivity.low,
      status:
          confirmed ? CoachMemoryStatus.active : CoachMemoryStatus.candidate,
      version: 1,
      validityPolicy: boundary
          ? CoachMemoryValidityPolicy.untilRevoked
          : CoachMemoryValidityPolicy.expiresAt,
      validFrom: validFrom,
      validUntil: boundary
          ? null
          : validFrom.add(Duration(days: draft.category.defaultRetentionDays)),
      mayMention: confirmed && !boundary,
      userConfirmed: confirmed,
      syncAllowed: false,
      confirmationBasis: confirmed
          ? CoachMemoryConfirmationBasis.explicitCommand
          : CoachMemoryConfirmationBasis.none,
      createdAt: validFrom,
      updatedAt: validFrom,
    );
  }

  CoachRenderedReply _renderNonTrainingTurn({
    required String text,
    required CoachParsedTurn parsed,
    required CoachMemoryV1? writtenMemory,
  }) {
    if (writtenMemory != null) {
      return CoachRenderedReply(
        text: writtenMemory.userConfirmed
            ? '记住了。你可以随时在“记忆与来源”里查看、纠正或忘记。'
            : '我先把这条放进待确认记忆；你确认前，它不会参与建议或同步。',
        actions: const <CoachRenderedAction>[
          CoachRenderedAction(
            actionId: 'open-coach-memories',
            label: '看记忆',
            route: '/companion/memories',
            requiresConfirmation: false,
          ),
        ],
        verificationState: CoachVerificationState.localOnly,
      );
    }
    if (text.contains('忘记') || parsed.intent == CoachIntent.manageMemory) {
      return const CoachRenderedReply(
        text: '可以。为避免误删，请在记忆列表里选择具体内容并再次确认。',
        actions: <CoachRenderedAction>[
          CoachRenderedAction(
            actionId: 'open-coach-memories',
            label: '去管理',
            route: '/companion/memories',
            requiresConfirmation: false,
          ),
        ],
        verificationState: CoachVerificationState.localOnly,
      );
    }
    return CoachRenderedReply(
      text: parsed.intent == CoachIntent.emotionalSupport
          ? '我在。先不用证明什么，你可以只说说现在最难的那一小步。'
          : '我听到了。这条只留在本机当前对话里，不会自动变成长期记忆。',
      actions: const <CoachRenderedAction>[],
      verificationState: CoachVerificationState.localOnly,
    );
  }

  List<CompanionFact> _factsForSnapshot(TrainingStateSnapshotV1 snapshot) {
    CoachSourceRef? planSource;
    for (final CoachSourceRef source in snapshot.sourceRefs) {
      if (source.sourceKind == 'scheduled_workout') {
        planSource = source;
        break;
      }
    }
    if (planSource == null || snapshot.plannedDurationMinutes == null) {
      return const <CompanionFact>[];
    }
    return <CompanionFact>[
      CompanionFact(
        label: '既有计划',
        value: '${snapshot.plannedDurationMinutes} 分钟',
        source: CompanionFactSource.trainingLog,
        deepLink: '/plans',
        sourceLocalId: planSource.sourceLocalId,
        sourceDigest: planSource.sourceDigest,
        observedAt: planSource.observedAt,
        sourceSummary: planSource.summaryKey,
      ),
    ];
  }

  CompanionContext _assembleContext({
    required DateTime now,
    required CompanionRelationship relationship,
  }) {
    final Set<String> signalDates = <String>{
      ..._petState.energyHistory.map((PetDailyEnergy item) => item.localDate),
      ..._trainingLogs
          .where((TrainingLog item) => item.completed)
          .map((TrainingLog item) => _localDate(item.date.toLocal())),
      if (_petState.todayActivitySummary != null)
        _petState.todayActivitySummary!.localDate,
    };
    final String today = _localDate(now);
    final bool hasSignalToday = signalDates.contains(today);
    final List<DateTime> orderedSignals = signalDates
        .map(DateTime.parse)
        .where((DateTime item) =>
            !item.isAfter(DateTime(now.year, now.month, now.day)))
        .toList()
      ..sort();
    final DateTime? latestSignal =
        orderedSignals.isEmpty ? null : orderedSignals.last;
    final int daysSinceLastActivity = latestSignal == null
        ? 0
        : DateTime(now.year, now.month, now.day)
            .difference(DateTime(
              latestSignal.year,
              latestSignal.month,
              latestSignal.day,
            ))
            .inDays;
    final bool wasAwayYesterday = hasSignalToday &&
        orderedSignals.any((DateTime item) =>
            item.isBefore(DateTime(now.year, now.month, now.day - 2)));
    final PainLog? latestPain = _painLogs.isEmpty ? null : _painLogs.first;
    final int relationshipDays = DateTime(now.year, now.month, now.day)
            .difference(DateTime(
              relationship.startedOn.year,
              relationship.startedOn.month,
              relationship.startedOn.day,
            ))
            .inDays +
        1;
    return CompanionContext(
      relationshipDays: relationshipDays.clamp(1, 99999),
      daysSinceLastActivity: daysSinceLastActivity.clamp(0, 99999),
      missedInLast7Days: _missedScheduledWorkouts(now),
      currentStreak: _currentStreak(signalDates, now),
      wasAwayYesterday: wasAwayYesterday,
      hasSignalToday: hasSignalToday,
      latestPainScore: latestPain?.painLevel,
      hasUnresolvedSeverePain: latestPain?.requiresMedicalAttention ?? false,
      disturbTier: relationship.disturbTier,
      consecutiveUnopened: relationship.consecutiveUnopened,
      notificationDetailEnabled: relationship.notificationDetailEnabled,
      quietHoursStartMinute: relationship.quietHoursStartMinute,
      quietHoursEndMinute: relationship.quietHoursEndMinute,
      boundaries: <CompanionBoundaryTopic>{
        ...relationship.boundaries,
        CompanionBoundaryTopic.appearance,
      },
    );
  }

  List<CompanionCandidate> _candidates({
    required DateTime now,
    required CompanionContext context,
    required RelationshipState relationshipState,
    required List<CompanionMessage> history,
  }) {
    final Map<String, String> values = <String, String>{
      'togetherDays': '${context.relationshipDays}',
      'workoutName': '今日训练',
      'durationMin': '${_todayWorkout(now)?.allocatedMinutes ?? 30}',
      if (_latestPain != null) 'bodyPart': _latestPain!.bodyPart,
      if (_latestPain != null) 'painLevel': '${_latestPain!.painLevel}',
    };
    final List<CompanionCandidate> candidates = <CompanionCandidate>[];
    if (relationshipState == RelationshipState.injured && _latestPain != null) {
      final CompanionCopyVariant injury = resolveInjuryCopyVariant(
        painScore: _latestPain!.painLevel,
        hasLastedMoreThanTwoWeeks: _latestPain!.persistsOverTwoWeeks,
        isOngoing: _latestPain!.timing == PainTiming.ongoing,
      );
      if (injury.canRender(values)) {
        final bool redLine =
            _latestPain!.painLevel >= 7 || _latestPain!.persistsOverTwoWeeks;
        candidates.add(CompanionCandidate(
          copyVariantId: injury.id,
          intent: CompanionIntent.injuryCare,
          body: injury.render(values),
          urgency: 100,
          baseValue: 100,
          defaultPrivacy: PrivacyLevel.l0,
          deliveryKind: CompanionDeliveryKind.proactive,
          preferredAt: now,
          safetyCritical: true,
          boundaryTopics: const <CompanionBoundaryTopic>{
            CompanionBoundaryTopic.pain
          },
          facts: <CompanionFact>[
            CompanionFact(
              label: '疼痛记录',
              value: '${_latestPain!.bodyPart} ${_latestPain!.painLevel}/10',
              source: CompanionFactSource.manualEntry,
              deepLink: '/rehab',
              isSensitive: true,
            ),
          ],
          actions: redLine
              ? const <CompanionAction>[
                  CompanionAction(
                    actionId: 'open-rehab',
                    label: '看看记录',
                    kind: CompanionActionKind.primary,
                    effect: CompanionActionEffect.openExistingRoute,
                    route: '/rehab',
                  ),
                ]
              : const <CompanionAction>[
                  CompanionAction(
                    actionId: 'open-adjustment',
                    label: '看看调整',
                    kind: CompanionActionKind.primary,
                    effect: CompanionActionEffect.requestExistingAdjustment,
                    route: '/daily-adjustment',
                  ),
                ],
        ));
      }
      return candidates;
    }
    if (relationshipState == RelationshipState.returning) {
      _addCopyCandidate(
        candidates: candidates,
        intent: CompanionIntent.returning,
        values: values,
        history: history,
        now: now,
        urgency: 90,
        baseValue: 90,
        privacy: PrivacyLevel.l0,
        actions: const <CompanionAction>[
          CompanionAction(
            actionId: 'open-today',
            label: '看看今天',
            kind: CompanionActionKind.primary,
            effect: CompanionActionEffect.openExistingRoute,
            route: '/dashboard',
          ),
        ],
      );
      return candidates;
    }
    if (relationshipState == RelationshipState.dormant ||
        relationshipState == RelationshipState.lapsed) {
      final int days = context.daysSinceLastActivity;
      if (relationshipState == RelationshipState.dormant &&
          days != 3 &&
          days != 6) {
        return candidates;
      }
      if (relationshipState == RelationshipState.lapsed && days % 7 != 0) {
        return candidates;
      }
      _addCopyCandidate(
        candidates: candidates,
        intent: CompanionIntent.quietDay,
        values: values,
        history: history,
        now: now,
        urgency: 20,
        baseValue: 65,
        privacy: PrivacyLevel.l0,
      );
      return candidates;
    }
    _addCopyCandidate(
      candidates: candidates,
      intent: CompanionIntent.morningBrief,
      values: values,
      history: history,
      now: now,
      urgency: 55,
      baseValue: 70,
      privacy: PrivacyLevel.l0,
      preferredAt: _morningSlot(now),
      facts: _todayFacts(),
      actions: <CompanionAction>[
        const CompanionAction(
          actionId: 'open-plan',
          label: '看看计划',
          kind: CompanionActionKind.primary,
          effect: CompanionActionEffect.openExistingRoute,
          route: '/plans',
        ),
        if (_todayWorkout(now) != null)
          const CompanionAction(
            actionId: 'dismiss-today',
            label: '今天算了',
            kind: CompanionActionKind.dismiss,
            effect: CompanionActionEffect.recordDismissal,
          ),
      ],
    );
    final ScheduledWorkout? workout = _todayWorkout(now);
    if (workout != null) {
      final DateTime reminderAt =
          _scheduledTime(workout).subtract(const Duration(minutes: 15));
      if (!reminderAt.isAfter(now) && !_isNearWorkout(now, workout)) {
        return candidates;
      }
      _addCopyCandidate(
        candidates: candidates,
        intent: CompanionIntent.preWorkout,
        values: values,
        history: history,
        now: now,
        urgency: 70,
        baseValue: 75,
        privacy: PrivacyLevel.l1,
        preferredAt: reminderAt.isAfter(now) ? reminderAt : now,
        facts: _todayFacts(),
        actions: const <CompanionAction>[
          CompanionAction(
            actionId: 'open-plan',
            label: '看看计划',
            kind: CompanionActionKind.primary,
            effect: CompanionActionEffect.openExistingRoute,
            route: '/plans',
          ),
        ],
      );
    }
    return candidates;
  }

  PainLog? get _latestPain => _painLogs.isEmpty ? null : _painLogs.first;

  void _addCopyCandidate({
    required List<CompanionCandidate> candidates,
    required CompanionIntent intent,
    required Map<String, String> values,
    required List<CompanionMessage> history,
    required DateTime now,
    required int urgency,
    required int baseValue,
    required PrivacyLevel privacy,
    DateTime? preferredAt,
    List<CompanionFact> facts = const <CompanionFact>[],
    List<CompanionAction> actions = const <CompanionAction>[],
  }) {
    final CompanionCopyVariant? copy = pickCompanionCopyVariant(
      intent: intent,
      variables: values,
      usedVariantIds: const <String>{},
      history: history
          .map((CompanionMessage item) => CompanionCopyHistory(
                variantId: item.copyVariantId,
                createdAt: item.createdAt,
              ))
          .toList(growable: false),
      now: now,
      random: Random(now.microsecondsSinceEpoch + intent.index),
    );
    if (copy == null) return;
    candidates.add(CompanionCandidate(
      copyVariantId: copy.id,
      intent: intent,
      body: copy.render(values),
      urgency: urgency,
      baseValue: baseValue,
      defaultPrivacy: privacy,
      deliveryKind: CompanionDeliveryKind.proactive,
      preferredAt: preferredAt ?? now,
      facts: facts,
      actions: actions,
    ));
  }

  List<CompanionFact> _todayFacts() {
    final List<CompanionFact> facts = <CompanionFact>[
      CompanionFact(
        label: '数据口径',
        value: _bodyDataQuality.statusLabel,
        source: CompanionFactSource.derived,
        deepLink: '/data-center',
      ),
    ];
    final int? steps = _petState.todayActivitySummary?.steps;
    if (steps != null) {
      facts.add(CompanionFact(
        label: '今日步数',
        value: '$steps 步',
        source: CompanionFactSource.healthKit,
        deepLink: '/pet/data',
      ));
    }
    final ScheduledWorkout? workout = _todayWorkout(_clock());
    if (workout != null) {
      facts.add(CompanionFact(
        label: '今日计划',
        value: '${workout.allocatedMinutes} 分钟',
        source: CompanionFactSource.derived,
        deepLink: '/plans',
      ));
    }
    if (_petState.todayEnergy != null) {
      facts.add(CompanionFact(
        label: '袋小满能量',
        value: '${_petState.todayEnergy!.awardedTotal} 点',
        source: CompanionFactSource.derived,
        deepLink: '/companion/archive',
      ));
    }
    return facts;
  }

  ScheduledWorkout? _todayWorkout(DateTime now) => _schedule.workoutFor(now);

  int _missedScheduledWorkouts(DateTime now) {
    int missed = 0;
    for (int offset = 1; offset <= 7; offset += 1) {
      final DateTime day = DateTime(now.year, now.month, now.day - offset);
      final ScheduledWorkout? scheduled = _schedule.workoutFor(day);
      if (scheduled == null) continue;
      final bool completed = _trainingLogs.any((TrainingLog log) =>
          log.completed && _sameDate(log.date.toLocal(), day));
      if (!completed) missed += 1;
    }
    return missed;
  }

  int _currentStreak(Set<String> signalDates, DateTime now) {
    int streak = 0;
    for (int offset = 0; offset < 366; offset += 1) {
      final DateTime day = DateTime(now.year, now.month, now.day - offset);
      if (!signalDates.contains(_localDate(day))) break;
      streak += 1;
    }
    return streak;
  }
}

CompanionRelationship _copyRelationship(
  CompanionRelationship source, {
  String? companionName,
  RelationshipState? lastResolvedState,
  DateTime? stateEnteredOn,
  DisturbTier? disturbTier,
  bool? notificationsEnabled,
  bool? notificationDetailEnabled,
  Set<CompanionBoundaryTopic>? boundaries,
  int? consecutiveUnopened,
}) {
  final DateTime now = DateTime.now().toUtc();
  return CompanionRelationship(
    athleteProfileId: source.athleteProfileId,
    companionName: companionName,
    startedOn: source.startedOn,
    lastResolvedState: lastResolvedState ?? source.lastResolvedState,
    stateEnteredOn: stateEnteredOn ?? source.stateEnteredOn,
    disturbTier: disturbTier ?? source.disturbTier,
    quietHoursStartMinute: source.quietHoursStartMinute,
    quietHoursEndMinute: source.quietHoursEndMinute,
    notificationsEnabled: notificationsEnabled ?? source.notificationsEnabled,
    notificationDetailEnabled:
        notificationDetailEnabled ?? source.notificationDetailEnabled,
    boundaries: boundaries ?? source.boundaries,
    consecutiveUnopened: consecutiveUnopened ?? source.consecutiveUnopened,
    createdAt: source.createdAt,
    updatedAt: now,
  );
}

bool _isNearWorkout(DateTime now, ScheduledWorkout workout) {
  final DateTime target = _scheduledTime(workout);
  return now.isAfter(target.subtract(const Duration(minutes: 20))) &&
      now.isBefore(target.add(const Duration(minutes: 10)));
}

DateTime _scheduledTime(ScheduledWorkout workout) => DateTime(
      workout.scheduledDate.year,
      workout.scheduledDate.month,
      workout.scheduledDate.day,
    ).add(Duration(minutes: workout.startMinute));

DateTime _morningSlot(DateTime now) {
  final DateTime preferred = DateTime(now.year, now.month, now.day, 8, 30);
  return preferred.isAfter(now) ? preferred : now;
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _localDate(DateTime value) {
  final String month = value.month.toString().padLeft(2, '0');
  final String day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _messageId(String scope, DateTime now) =>
    'companion-$scope-${now.toUtc().microsecondsSinceEpoch}';
