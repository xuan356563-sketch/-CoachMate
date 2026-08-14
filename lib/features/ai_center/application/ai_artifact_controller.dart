import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ai_artifact.dart';
import '../../../data/models/plan_revision_proposal.dart';
import '../../../data/repositories/ai_artifact_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../auth/data/authenticated_api_client.dart';
import '../data/ai_api.dart';
import '../data/plan_revision_api_models.dart';
import '../data/training_prescription_api_models.dart';

final aiArtifactRepositoryProvider = Provider<AiArtifactRepository>(
  (Ref ref) => PersistedAiArtifactRepository(
    ref.watch(localStorageServiceProvider),
  ),
);

final aiArtifactControllerProvider =
    NotifierProvider<AiArtifactController, AiArtifactState>(
  AiArtifactController.new,
);

class AiArtifactState {
  final List<AiArtifact> artifacts;
  final bool isSyncing;
  final bool isGenerating;
  final AiCapability? activeCapability;
  final bool healthDataProcessingConsented;
  final String statusMessage;

  const AiArtifactState({
    required this.artifacts,
    required this.isSyncing,
    required this.isGenerating,
    required this.activeCapability,
    required this.healthDataProcessingConsented,
    required this.statusMessage,
  });

  bool get isBusy => isSyncing || isGenerating;

  AiArtifact? latestFor(AiCapability capability) {
    for (final AiArtifact artifact in artifacts) {
      if (artifact.capability == capability) return artifact;
    }
    return null;
  }

  AiArtifact? latestForArtifactType(
    AiCapability capability,
    String artifactType,
  ) {
    for (final AiArtifact artifact in artifacts) {
      if (artifact.capability == capability &&
          artifact.artifactType == artifactType) {
        return artifact;
      }
    }
    return null;
  }

  AiArtifactState copyWith({
    List<AiArtifact>? artifacts,
    bool? isSyncing,
    bool? isGenerating,
    AiCapability? activeCapability,
    bool clearActiveCapability = false,
    bool? healthDataProcessingConsented,
    String? statusMessage,
  }) =>
      AiArtifactState(
        artifacts: artifacts ?? this.artifacts,
        isSyncing: isSyncing ?? this.isSyncing,
        isGenerating: isGenerating ?? this.isGenerating,
        activeCapability: clearActiveCapability
            ? null
            : activeCapability ?? this.activeCapability,
        healthDataProcessingConsented:
            healthDataProcessingConsented ?? this.healthDataProcessingConsented,
        statusMessage: statusMessage ?? this.statusMessage,
      );
}

/// 管理跨设备 AI 卡片缓存，不保存原始图片、音频或用户提示词。
class AiArtifactController extends Notifier<AiArtifactState> {
  late final AiArtifactRepository _repository;

  @override
  AiArtifactState build() {
    _repository = ref.watch(aiArtifactRepositoryProvider);
    // 旧版本允许保存“发送健康摘要”同意；v1 成长系统改为健康数据仅本地，
    // 启动控制器时强制撤销旧开关，避免未来界面误用陈旧状态。
    _repository.setHealthDataProcessingConsent(false);
    return AiArtifactState(
      artifacts: _repository.listArtifacts(),
      isSyncing: false,
      isGenerating: false,
      activeCapability: null,
      healthDataProcessingConsented: false,
      statusMessage: 'AI 结果会先生成卡片，确认后才影响本地训练。',
    );
  }

  Future<void> sync() async {
    if (state.isBusy) return;
    state = state.copyWith(
      isSyncing: true,
      statusMessage: '正在同步已生成的 AI 卡片…',
    );
    try {
      final List<AiArtifact> remote =
          await ref.read(aiApiProvider).listArtifacts();
      final List<AiArtifact> merged = _mergeArtifacts(state.artifacts, remote);
      _repository.replaceArtifacts(merged);
      state = state.copyWith(
        artifacts: merged,
        isSyncing: false,
        statusMessage:
            remote.isEmpty ? '云端暂无 AI 卡片。' : '已同步 ${remote.length} 张 AI 卡片。',
      );
    } on ApiException catch (error) {
      state = state.copyWith(
        isSyncing: false,
        statusMessage: '暂时无法同步，已保留本机 AI 卡片：${error.message}',
      );
    }
  }

  void setHealthDataProcessingConsent(bool value) {
    _repository.setHealthDataProcessingConsent(false);
    state = state.copyWith(
      healthDataProcessingConsented: false,
      statusMessage: '健康与成长数据仅在本机处理，不会发送给云端 AI。',
    );
  }

  Future<AiArtifact?> generateText({
    required AiCapability capability,
    required String prompt,
    required AiGenerationContext context,
    bool force = false,
  }) async {
    if (capability != AiCapability.trainer &&
        capability != AiCapability.recovery) {
      state = state.copyWith(statusMessage: '该 AI 能力正在准备中。');
      return null;
    }
    if (state.isBusy) return null;
    state = state.copyWith(
      isGenerating: true,
      activeCapability: capability,
      statusMessage: '正在生成${capability.label}卡片…',
    );
    try {
      final AiArtifact artifact = await ref.read(aiApiProvider).generateText(
            capability: capability,
            prompt: prompt.trim(),
            context: context,
            force: force,
          );
      _repository.upsert(artifact);
      state = state.copyWith(
        artifacts: _repository.listArtifacts(),
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: artifact.warnings.isEmpty
            ? '${capability.label}卡片已生成，请先确认再采用。'
            : '${capability.label}卡片已生成，请先核对提示。',
      );
      return artifact;
    } on ApiException catch (error) {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: '${capability.label}暂时不可用：${error.message}',
      );
      return null;
    }
  }

  Future<AiArtifact?> generateTrainingPrescription(
    TrainingPrescriptionRequest request,
  ) async {
    if (state.isBusy) return null;
    state = state.copyWith(
      isGenerating: true,
      activeCapability: AiCapability.trainer,
      statusMessage: '正在使用已审核 Skill 生成四周训练处方…',
    );
    try {
      final AiArtifact artifact =
          await ref.read(aiApiProvider).generateTrainingPrescription(request);
      _repository.upsert(artifact);
      state = state.copyWith(
        artifacts: _repository.listArtifacts(),
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: '训练处方已生成，正在进行本地编译和安全审计。',
      );
      return artifact;
    } on ApiException catch (error) {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: '训练处方暂时不可用：${error.message}',
      );
      return null;
    } on FormatException {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: '训练处方格式无效，现有计划不会改变。',
      );
      return null;
    }
  }

  Future<AiArtifact?> generateTrainingPrescriptionV2(
    TrainingPrescriptionV2Request request,
  ) async {
    if (state.isBusy) return null;
    state = state.copyWith(
      isGenerating: true,
      activeCapability: AiCapability.trainer,
      statusMessage: '正在使用已审核知识与模板生成四周训练处方…',
    );
    try {
      final AiArtifact artifact =
          await ref.read(aiApiProvider).generateTrainingPrescriptionV2(request);
      _repository.upsert(artifact);
      state = state.copyWith(
        artifacts: _repository.listArtifacts(),
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: 'V2 训练处方已生成，正在进行本地编译和安全审计。',
      );
      return artifact;
    } on ApiException catch (error) {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: 'V2 训练处方暂时不可用：${error.message}',
      );
      return null;
    } on FormatException {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: 'V2 训练处方格式无效，现有计划不会改变。',
      );
      return null;
    }
  }

  Future<PlanRevisionProposal?> generatePlanRevision(
    PlanRevisionRequest request,
  ) async {
    if (state.isBusy) return null;
    state = state.copyWith(
      isGenerating: true,
      activeCapability: AiCapability.trainer,
      statusMessage: '正在生成剩余周期差异…',
    );
    try {
      final PlanRevisionProposal proposal =
          await ref.read(aiApiProvider).generatePlanRevision(request);
      _repository.upsert(proposal.artifact);
      state = state.copyWith(
        artifacts: _repository.listArtifacts(),
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: '周期重排提议已生成，确认前当前计划不会改变。',
      );
      return proposal;
    } on ApiException catch (error) {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: '周期重排暂时不可用：${error.message}',
      );
      return null;
    }
  }

  Future<AiArtifact?> generateMotion({
    required List<int> imageBytes,
    required String filename,
    required String ruleId,
    required String localPoseSummary,
  }) async {
    if (state.isBusy) return null;
    state = state.copyWith(
      isGenerating: true,
      activeCapability: AiCapability.motion,
      statusMessage: '正在进行 AI Motion 图片复核…',
    );
    try {
      final AiArtifact artifact = await ref.read(aiApiProvider).analyzeMotion(
            imageBytes: Uint8List.fromList(imageBytes),
            filename: filename,
            ruleId: ruleId,
            localPoseSummary: localPoseSummary,
          );
      _repository.upsert(artifact);
      state = state.copyWith(
        artifacts: _repository.listArtifacts(),
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: 'AI Motion 已生成评分卡，请确认后再应用到今日训练。',
      );
      return artifact;
    } on ApiException catch (error) {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: 'AI Motion 暂时不可用：${error.message}',
      );
      return null;
    }
  }

  Future<AiArtifact?> decide({
    required AiArtifact artifact,
    required AiArtifactDecision decision,
  }) async {
    final bool isAcceptedPrescriptionRevalidation =
        (artifact.artifactType == 'training_prescription_v1' ||
                artifact.artifactType == 'training_prescription_v2') &&
            artifact.decision == AiArtifactDecision.accepted &&
            decision == AiArtifactDecision.accepted;
    if (state.isBusy ||
        (!artifact.isPending && !isAcceptedPrescriptionRevalidation)) {
      return null;
    }
    state = state.copyWith(
      isGenerating: true,
      activeCapability: artifact.capability,
      statusMessage: '正在保存你的确认结果…',
    );
    try {
      final AiArtifact saved = await ref.read(aiApiProvider).decide(
            artifactId: artifact.id,
            decision: decision,
          );
      _repository.upsert(saved);
      state = state.copyWith(
        artifacts: _repository.listArtifacts(),
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: decision == AiArtifactDecision.accepted
            ? '已确认 AI 卡片，本地安全规则仍优先。'
            : '已拒绝该 AI 卡片，不会影响现有训练。',
      );
      return saved;
    } on ApiException catch (error) {
      state = state.copyWith(
        isGenerating: false,
        clearActiveCapability: true,
        statusMessage: '无法保存确认结果：${error.message}',
      );
      return null;
    }
  }

  Future<bool> delete(AiArtifact artifact) async {
    if (state.isBusy) return false;
    state = state.copyWith(isGenerating: true, statusMessage: '正在删除 AI 卡片…');
    try {
      await ref.read(aiApiProvider).delete(artifact.id);
      _repository.remove(artifact.id);
      state = state.copyWith(
        artifacts: _repository.listArtifacts(),
        isGenerating: false,
        statusMessage: 'AI 卡片已删除。',
      );
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(
        isGenerating: false,
        statusMessage: '无法删除 AI 卡片：${error.message}',
      );
      return false;
    }
  }

  List<AiArtifact> _mergeArtifacts(
    List<AiArtifact> local,
    List<AiArtifact> remote,
  ) {
    final Map<String, AiArtifact> items = <String, AiArtifact>{
      for (final AiArtifact item in local) item.id: item,
      for (final AiArtifact item in remote) item.id: item,
    };
    final List<AiArtifact> merged = items.values.toList();
    merged.sort(
        (AiArtifact a, AiArtifact b) => b.generatedAt.compareTo(a.generatedAt));
    return merged;
  }
}
