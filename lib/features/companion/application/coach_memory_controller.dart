import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/features/companion/application/companion_controller.dart';
import 'package:trainflow_ai/features/companion/application/companion_database_provider.dart';
import 'package:trainflow_ai/features/companion/data/coach_api.dart';
import 'package:trainflow_ai/features/companion/data/coach_local_repository.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';
import 'package:trainflow_ai/features/pet/application/pet_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/plugins/application/feature_access.dart';
import 'package:trainflow_ai/plugins/application/feature_controller_binding.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';

final coachMemoryControllerProvider =
    AsyncNotifierProvider<CoachMemoryController, CoachMemoryState>(
  CoachMemoryController.new,
  retry: (int _, Object __) => null,
);

class CoachMemoryState {
  const CoachMemoryState({
    required this.athleteProfileId,
    required this.memories,
    required this.statusMessage,
    required this.cloudProjectionConsented,
    this.available = true,
  });

  const CoachMemoryState.unavailable(this.statusMessage)
      : athleteProfileId = '',
        memories = const <CoachMemoryV1>[],
        cloudProjectionConsented = false,
        available = false;

  final String athleteProfileId;
  final List<CoachMemoryV1> memories;
  final String statusMessage;
  final bool cloudProjectionConsented;
  final bool available;
}

class CoachMemoryController extends AsyncNotifier<CoachMemoryState> {
  static const String _featureId = 'feature.companion';
  late CoachLocalRepository _repository;
  late CoachApi _api;
  late LocalStorageService _storage;
  late DateTime Function() _clock;
  String _athleteProfileId = '';
  bool _cloudProjectionConsented = false;
  String? _statusOverride;

  @override
  Future<CoachMemoryState> build() async {
    final database = ref.watch(coachDatabaseGatewayProvider);
    final AsyncValue<PetState> pet = ref.watch(petControllerProvider);
    if (database == null) {
      return const CoachMemoryState.unavailable('Coach 记忆库暂不可用，未修改任何数据。');
    }
    if (!pet.hasValue) {
      return const CoachMemoryState.unavailable('正在读取本机伙伴账号。');
    }
    _athleteProfileId =
        pet.requireValue.activeCompanion?.athleteProfileId ?? '';
    if (_athleteProfileId.isEmpty) {
      return const CoachMemoryState.unavailable('尚未选择可使用的袋小满。');
    }
    _clock = ref.watch(companionClockProvider);
    _api = ref.watch(coachApiProvider);
    _storage = ref.watch(localStorageServiceProvider);
    _cloudProjectionConsented =
        _storage.readJson(coachCloudConsentStorageKey)?['granted'] == true;
    _repository = CoachLocalRepository(database, clock: _clock);
    bindFeatureController(ref, _featureId, 'memory', this);
    return _load();
  }

  Future<void> confirm(String memoryId) async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    await operation.commit(() => _repository.confirmMemory(
          athleteProfileId: _athleteProfileId,
          memoryId: memoryId,
          syncAllowed: false,
        ));
    await refresh();
  }

  Future<void> setMayMention(String memoryId, bool value) async {
    final FeatureOperation? operation = value
        ? ref.read(featureAccessProvider).beginOperation(_featureId)
        : null;
    final CoachMemoryV1? memory = await _repository.loadMemory(
      athleteProfileId: _athleteProfileId,
      memoryId: memoryId,
    );
    if (memory == null || !memory.isUsable(_clock())) {
      throw StateError('只有已确认且有效的记忆可以修改提及权限');
    }
    Future<void> save() => _repository.saveMemory(memory.copyWith(
          mayMention: value,
          updatedAt: _clock().toUtc(),
        ));
    await (operation == null ? save() : operation.commit(save));
    await refresh();
  }

  Future<void> setCloudProjectionConsent(bool granted) async {
    _statusOverride = null;
    if (granted) {
      final FeatureOperation operation =
          ref.read(featureAccessProvider).beginOperation(_featureId);
      await _api.setCloudConsent(granted: true);
      operation.checkActive();
      await _saveCloudConsent(true, operation: operation);
      _statusOverride = 'Coach 云投影已授权；仅明确开启的已确认记忆可进入最小投影。';
      await refresh();
      return;
    }

    // 撤回先在本机生效，确保后续请求不会继续携带记忆；云端删除失败时明确提示重试。
    await _saveCloudConsent(false);
    final List<CoachMemoryV1> memories =
        await _repository.listMemories(_athleteProfileId);
    for (final CoachMemoryV1 memory in memories) {
      if (!memory.syncAllowed) continue;
      await _repository.saveMemory(memory.copyWith(
        syncAllowed: false,
        updatedAt: _clock().toUtc(),
      ));
    }
    try {
      await _api.setCloudConsent(granted: false);
      _statusOverride = 'Coach 云投影已撤回，云端投影已请求删除；本机记忆保持不变。';
    } catch (_) {
      _statusOverride = '本机已停止 Coach 云投影；云端删除尚未确认，请联网后再次撤回。';
    }
    await refresh();
  }

  Future<void> setSyncAllowed(String memoryId, bool value) async {
    final FeatureOperation? operation = value
        ? ref.read(featureAccessProvider).beginOperation(_featureId)
        : null;
    if (value && !_cloudProjectionConsented) {
      throw StateError('请先明确开启 Coach 云投影同意');
    }
    final CoachMemoryV1? memory = await _repository.loadMemory(
      athleteProfileId: _athleteProfileId,
      memoryId: memoryId,
    );
    if (memory == null || !memory.isUsable(_clock())) {
      throw StateError('只有已确认且有效的记忆可以修改云同步权限');
    }
    Future<void> save() => _repository.saveMemory(memory.copyWith(
          syncAllowed: value,
          updatedAt: _clock().toUtc(),
        ));
    await (operation == null ? save() : operation.commit(save));
    _statusOverride =
        value ? '这条记忆已允许进入最小云投影；不会上传原始对话或健康样本。' : '这条记忆已停止进入后续云投影。';
    await refresh();
  }

  Future<void> correct({
    required String memoryId,
    required String replacement,
  }) async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation(_featureId);
    final String text = replacement.trim();
    if (text.isEmpty || text.length > 240) {
      throw ArgumentError.value(
          replacement, 'replacement', '纠正内容需为 1 到 240 个字');
    }
    final DateTime now = _clock();
    await operation.commit(() => _repository.correctMemory(
          athleteProfileId: _athleteProfileId,
          memoryId: memoryId,
          replacementMemoryId:
              'memory-correction-${now.toUtc().microsecondsSinceEpoch}',
          value: <String, Object?>{'statement': text},
          displayText: text,
          correctionSource: CoachSourceRef(
            sourceKind: 'user_correction',
            sourceLocalId: 'correction-${now.toUtc().microsecondsSinceEpoch}',
            sourceDigest: CoachDigest.sha256(text),
            observedAt: now,
            summaryKey: '用户在记忆面板中的纠正',
          ),
        ));
    await refresh();
  }

  Future<void> forget(String memoryId) async {
    await _repository.forgetMemory(
      athleteProfileId: _athleteProfileId,
      memoryId: memoryId,
    );
    await refresh();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<CoachMemoryState>();
    state = await AsyncValue.guard(_load);
  }

  Future<CoachMemoryState> _load() async {
    final List<CoachMemoryV1> memories =
        await _repository.listMemories(_athleteProfileId);
    final String? statusOverride = _statusOverride;
    _statusOverride = null;
    return CoachMemoryState(
      athleteProfileId: _athleteProfileId,
      memories: memories,
      statusMessage: statusOverride ??
          (memories.isEmpty
              ? '还没有长期记忆。普通表达需要你确认后才会参与建议。'
              : '每条记忆都可查看来源、有效期与使用权限。'),
      cloudProjectionConsented: _cloudProjectionConsented,
    );
  }

  Future<void> _saveCloudConsent(
    bool granted, {
    FeatureOperation? operation,
  }) async {
    Future<void> save() async {
      _cloudProjectionConsented = granted;
      _storage.saveJson(coachCloudConsentStorageKey, <String, dynamic>{
        'granted': granted,
        'document_version': 'coach-cloud-projection-2026-08-12.1',
        'updated_at': _clock().toUtc().toIso8601String(),
      });
      await _storage.flush();
    }

    await (operation == null ? save() : operation.commit(save));
  }
}
