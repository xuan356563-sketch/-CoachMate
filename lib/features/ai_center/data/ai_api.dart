import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ai_artifact.dart';
import '../../../data/models/ai_chat.dart';
import '../../../data/models/profile_proposal.dart';
import '../../../data/models/plan_revision_proposal.dart';
import '../../auth/data/authenticated_api_client.dart';
import 'training_prescription_api_models.dart';
import 'plan_revision_api_models.dart';

final aiApiProvider = Provider<AiApi>(
  (Ref ref) => AiApi(ref.watch(authenticatedApiClientProvider)),
);

class AiApi {
  final AuthenticatedApiClient _client;

  const AiApi(this._client);

  Future<AiChatResponse> chat({
    required String requestId,
    required AiChatCloudIntent intent,
    required AiChatContext context,
  }) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v2/ai/chat',
      <String, dynamic>{
        'contract_version': 2,
        'request_id': requestId,
        'intent': intent.jsonValue,
        'context': context.toJson(),
      },
      authenticated: true,
    );
    final AiChatResponse result = AiChatResponse.fromJson(response);
    if (result.reply.isEmpty) {
      throw const ApiException(
        code: 'ai_chat_invalid',
        message: 'AI 回复格式无效，请稍后重试。',
      );
    }
    return result;
  }

  Future<List<AiArtifact>> listArtifacts() async {
    final Map<String, dynamic> response =
        await _client.getJson('/v1/ai/artifacts', authenticated: true);
    final Object? rawArtifacts = response['artifacts'];
    if (rawArtifacts is! List) return const <AiArtifact>[];
    return rawArtifacts
        .whereType<Map>()
        .map(
          (Map<dynamic, dynamic> item) =>
              AiArtifact.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<ProfileProposal> proposeProfile(
    ProfileProposalRequest request,
  ) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v1/ai/profile-proposals',
      request.toJson(),
      authenticated: true,
    );
    try {
      return ProfileProposal.fromArtifact(AiArtifact.fromJson(response));
    } on Object {
      throw const ApiException(
        code: 'profile_proposal_invalid',
        message: '服务返回的画像提议格式无效，请继续使用本地表单。',
      );
    }
  }

  Future<TrainingPrescriptionCapabilities>
      trainingPrescriptionCapabilities() async {
    final Map<String, dynamic> response = await _client.getJson(
      '/v1/ai/training-prescriptions/capabilities',
      authenticated: true,
    );
    late final TrainingPrescriptionCapabilities capabilities;
    try {
      capabilities = TrainingPrescriptionCapabilities.fromJson(response);
    } on Object {
      throw const ApiException(
        code: 'training_plan_skill_unavailable',
        message: 'Skill 能力信息无效，现有计划不会改变。',
      );
    }
    final bool hasInvalidSkill = capabilities.skills.any(
      (TrainingPrescriptionSkillCapability skill) =>
          skill.id.isEmpty ||
          !_isSemanticVersion(skill.version) ||
          skill.displayName.isEmpty ||
          skill.sports.isEmpty ||
          !_isSha256(skill.sourceSha256) ||
          !_isSha256(skill.runtimeSha256),
    );
    if (capabilities.contractVersion != 1 ||
        (capabilities.enabled && capabilities.skills.isEmpty) ||
        hasInvalidSkill) {
      throw const ApiException(
        code: 'training_plan_skill_unavailable',
        message: 'Skill 能力信息无效，现有计划不会改变。',
      );
    }
    return capabilities;
  }

  Future<KnowledgeCatalogSummary> knowledgeCatalog() async {
    final Map<String, dynamic> response = await _client.getJson(
      '/v1/knowledge/catalog',
      authenticated: true,
    );
    try {
      return KnowledgeCatalogSummary.fromJson(response);
    } on Object {
      throw const ApiException(
        code: 'knowledge_catalog_invalid',
        message: '训练知识目录格式无效，请使用本地规则计划。',
      );
    }
  }

  Future<AiArtifact> generateTrainingPrescription(
    TrainingPrescriptionRequest request,
  ) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v1/ai/training-prescriptions',
      request.toJson(),
      authenticated: true,
    );
    try {
      final AiArtifact artifact = AiArtifact.fromJson(response);
      final prescription = artifact.trainingPrescription;
      if (artifact.artifactType != 'training_prescription_v1' ||
          artifact.capability != AiCapability.trainer ||
          artifact.schemaVersion != 1 ||
          !_isSha256(artifact.contextDigest) ||
          prescription == null ||
          prescription.generationMeta.contractVersion != '1' ||
          !_isSha256(
            prescription.generationMeta.clientContextDigest,
          ) ||
          prescription.generationMeta.model.isEmpty ||
          prescription.skill.id.isEmpty ||
          !_isSemanticVersion(prescription.skill.version) ||
          prescription.skill.displayName.isEmpty ||
          !_isSha256(prescription.skill.sourceSha256) ||
          !_isSha256(prescription.skill.runtimeSha256) ||
          (prescription.skill.fragmentSha256 != null &&
              !_isSha256(prescription.skill.fragmentSha256!)) ||
          prescription.skill.selectionReason.isEmpty ||
          prescription.selectionReasonCode.isEmpty) {
        throw const FormatException('训练处方契约校验失败');
      }
      return artifact;
    } on Object {
      throw const ApiException(
        code: 'training_prescription_invalid',
        message: '服务返回的训练处方格式无效，现有计划不会改变。',
      );
    }
  }

  Future<AiArtifact> generateTrainingPrescriptionV2(
    TrainingPrescriptionV2Request request,
  ) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v2/ai/training-prescriptions',
      request.toJson(),
      authenticated: true,
    );
    try {
      final AiArtifact artifact = AiArtifact.fromJson(response);
      final prescription = artifact.trainingPrescription;
      final Object? rawCitations = artifact.payload['knowledge_citations'];
      if (artifact.artifactType != 'training_prescription_v2' ||
          artifact.capability != AiCapability.trainer ||
          artifact.schemaVersion != 2 ||
          !_isSha256(artifact.contextDigest) ||
          artifact.payload['population_template_id'] !=
              request.populationTemplateId ||
          rawCitations is! List ||
          rawCitations.isEmpty ||
          rawCitations.any(
            (Object? item) =>
                item is! Map ||
                item['id'] is! String ||
                (item['id'] as String).isEmpty ||
                !const <String>{'principle', 'training_template'}
                    .contains(item['type']),
          ) ||
          prescription == null ||
          prescription.generationMeta.contractVersion != '2' ||
          prescription.generationMeta.clientContextDigest !=
              request.clientContextDigest ||
          prescription.generationMeta.knowledgeSnapshotVersion !=
              request.knowledgeSnapshotVersion ||
          prescription.skill.id.isEmpty ||
          !_isSemanticVersion(prescription.skill.version) ||
          !_isSha256(prescription.skill.sourceSha256) ||
          !_isSha256(prescription.skill.runtimeSha256)) {
        throw const FormatException('V2 训练处方契约校验失败');
      }
      return artifact;
    } on Object {
      throw const ApiException(
        code: 'training_prescription_invalid',
        message: '服务返回的 V2 训练处方格式无效，现有计划不会改变。',
      );
    }
  }

  Future<PlanRevisionProposal> generatePlanRevision(
    PlanRevisionRequest request,
  ) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v1/ai/plan-revisions',
      request.toJson(),
      authenticated: true,
    );
    try {
      final AiArtifact artifact = AiArtifact.fromJson(response);
      return PlanRevisionProposal.fromArtifact(
        artifact: artifact,
        currentPrescription: request.currentPrescription,
        expectedClientContextDigest: request.clientContextDigest,
      );
    } on Object {
      throw const ApiException(
        code: 'plan_revision_invalid',
        message: '服务返回的周期重排格式无效，当前计划不会改变。',
      );
    }
  }

  Future<AiArtifact> generateText({
    required AiCapability capability,
    required String prompt,
    required AiGenerationContext context,
    bool force = false,
  }) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v1/ai/generations',
      <String, dynamic>{
        'capability': capability.jsonValue,
        'prompt': prompt,
        'context': context.toJson(),
        'force': force,
      },
      authenticated: true,
    );
    return AiArtifact.fromJson(response);
  }

  Future<AiArtifact> analyzeMotion({
    required Uint8List imageBytes,
    required String filename,
    required String ruleId,
    required String localPoseSummary,
  }) async {
    final Map<String, dynamic> response = await _client.postMultipartImage(
      '/v1/ai/motion-analysis',
      bytes: imageBytes,
      filename: filename,
      fields: <String, String>{
        'rule_id': ruleId,
        'local_pose_summary': localPoseSummary,
      },
    );
    return AiArtifact.fromJson(response);
  }

  Future<AiArtifact> decide({
    required String artifactId,
    required AiArtifactDecision decision,
  }) async {
    final Map<String, dynamic> response = await _client.postJson(
      '/v1/ai/artifacts/$artifactId/decision',
      <String, dynamic>{'decision': decision.jsonValue},
      authenticated: true,
    );
    final AiArtifact artifact = AiArtifact.fromJson(response);
    if (artifact.id != artifactId || artifact.decision != decision) {
      throw const ApiException(
        code: 'ai_artifact_decision_invalid',
        message: '服务返回的确认结果不一致，本地内容不会改变。',
      );
    }
    return artifact;
  }

  Future<void> delete(String artifactId) async {
    await _client.deleteJson('/v1/ai/artifacts/$artifactId');
  }
}

bool _isSha256(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

bool _isSemanticVersion(String value) => RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
      r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    ).hasMatch(value);
