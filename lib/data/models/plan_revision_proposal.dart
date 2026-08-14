import 'ai_artifact.dart';
import 'ai_training_prescription.dart';
import 'workout_day.dart';

class PlanRevisionDifference {
  final int sessionIndex;
  final String beforeTrainingType;
  final String afterTrainingType;
  final int beforeDurationMinutes;
  final int afterDurationMinutes;
  final String reasonCode;

  const PlanRevisionDifference({
    required this.sessionIndex,
    required this.beforeTrainingType,
    required this.afterTrainingType,
    required this.beforeDurationMinutes,
    required this.afterDurationMinutes,
    required this.reasonCode,
  });

  factory PlanRevisionDifference.fromJson(Map<String, dynamic> json) {
    final int sessionIndex = (json['session_index'] as num?)?.toInt() ?? -1;
    final String beforeTrainingType =
        json['before_training_type'] as String? ?? '';
    final String afterTrainingType =
        json['after_training_type'] as String? ?? '';
    final int beforeDurationMinutes =
        (json['before_duration_minutes'] as num?)?.toInt() ?? 0;
    final int afterDurationMinutes =
        (json['after_duration_minutes'] as num?)?.toInt() ?? 0;
    final String reasonCode = json['reason_code'] as String? ?? '';
    if (sessionIndex < 0 ||
        sessionIndex > 5 ||
        beforeTrainingType.isEmpty ||
        afterTrainingType.isEmpty ||
        beforeDurationMinutes < 20 ||
        afterDurationMinutes < 20 ||
        !_reasonCodes.contains(reasonCode)) {
      throw const FormatException('周期重排差异格式无效');
    }
    return PlanRevisionDifference(
      sessionIndex: sessionIndex,
      beforeTrainingType: beforeTrainingType,
      afterTrainingType: afterTrainingType,
      beforeDurationMinutes: beforeDurationMinutes,
      afterDurationMinutes: afterDurationMinutes,
      reasonCode: reasonCode,
    );
  }
}

class PlanRevisionProposal {
  final AiArtifact artifact;
  final AiTrainingPrescription revisedPrescription;
  final List<PlanRevisionDifference> differences;
  final String generationMode;

  const PlanRevisionProposal({
    required this.artifact,
    required this.revisedPrescription,
    required this.differences,
    required this.generationMode,
  });

  factory PlanRevisionProposal.fromArtifact({
    required AiArtifact artifact,
    required AiTrainingPrescription currentPrescription,
    required String expectedClientContextDigest,
  }) {
    final Map<String, dynamic> payload = artifact.payload;
    final Object? rawRevised = payload['revised_prescription'];
    final Object? rawDifferences = payload['differences'];
    final Object? rawGenerationMeta = payload['generation_meta'];
    if (artifact.artifactType != 'plan_revision_v1' ||
        artifact.schemaVersion != 1 ||
        artifact.capability != AiCapability.trainer ||
        !artifact.isPending ||
        payload['proposal_status'] != 'pending' ||
        payload['client_context_digest'] != expectedClientContextDigest ||
        rawRevised is! Map ||
        rawDifferences is! List ||
        rawDifferences.isEmpty ||
        rawDifferences.length > 6 ||
        rawGenerationMeta is! Map) {
      throw const FormatException('周期重排产物格式无效');
    }
    final Map<String, dynamic> generationMeta =
        Map<String, dynamic>.from(rawGenerationMeta);
    final String generationMode =
        generationMeta['generation_mode'] as String? ?? '';
    if (!_generationModes.contains(generationMode)) {
      throw const FormatException('周期重排生成模式无效');
    }
    final Map<String, dynamic> revised = Map<String, dynamic>.from(rawRevised);
    revised.addAll(<String, dynamic>{
      'applied_skill': currentPrescription.skill.toJson(),
      'selection_reason': currentPrescription.skill.selectionReason,
      'selection_reason_code': currentPrescription.selectionReasonCode,
      'knowledge_citations': currentPrescription.knowledgeCitations
          .map((item) => item.toJson())
          .toList(growable: false),
      'generation_meta': <String, dynamic>{
        ...currentPrescription.generationMeta.toJson(),
        'client_context_digest': expectedClientContextDigest,
        'generation_mode': generationMode,
        'cache_hit': generationMeta['app_cache_hit'] == true,
        'app_cache_hit': generationMeta['app_cache_hit'] == true,
        'model': generationMeta['model'] as String? ??
            currentPrescription.generationMeta.model,
        'input_tokens': (generationMeta['input_tokens'] as num?)?.toInt() ?? 0,
        'output_tokens':
            (generationMeta['output_tokens'] as num?)?.toInt() ?? 0,
        'prompt_cache_hit_tokens':
            (generationMeta['prompt_cache_hit_tokens'] as num?)?.toInt() ?? 0,
        'prompt_cache_miss_tokens':
            (generationMeta['prompt_cache_miss_tokens'] as num?)?.toInt() ?? 0,
      },
    });
    final AiTrainingPrescription prescription =
        AiTrainingPrescription.fromJson(revised);
    final List<PlanRevisionDifference> differences = rawDifferences
        .map(
          (Object? item) => PlanRevisionDifference.fromJson(
            Map<String, dynamic>.from(item! as Map),
          ),
        )
        .toList(growable: false);
    for (final PlanRevisionDifference difference in differences) {
      if (difference.sessionIndex >=
          currentPrescription.weeklySessions.length) {
        throw const FormatException('周期重排差异索引超出原计划');
      }
      final AiSessionBlueprint before =
          currentPrescription.weeklySessions[difference.sessionIndex];
      final AiSessionBlueprint after =
          prescription.weeklySessions[difference.sessionIndex];
      if (before.trainingType.jsonValue != difference.beforeTrainingType ||
          before.durationMinutes != difference.beforeDurationMinutes ||
          after.trainingType.jsonValue != difference.afterTrainingType ||
          after.durationMinutes != difference.afterDurationMinutes) {
        throw const FormatException('周期重排差异与处方正文不一致');
      }
    }
    return PlanRevisionProposal(
      artifact: artifact,
      revisedPrescription: prescription,
      differences: List<PlanRevisionDifference>.unmodifiable(differences),
      generationMode: generationMode,
    );
  }
}

const Set<String> _reasonCodes = <String>{
  'consecutive_missed',
  'schedule_changed',
  'equipment_changed',
  'remaining_cycle_conflict',
  'local_safe_fallback',
};

const Set<String> _generationModes = <String>{
  'cloud_adaptation',
  'local_safe_fallback',
};
