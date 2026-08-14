import 'ai_knowledge_citation.dart';
import 'ai_training_prescription.dart';
import 'workout_day.dart';

enum PlanIntensityBand { recovery, easy, moderate, challenging }

enum PlanProgressionMode { conservative, balanced }

enum PlanGenerationMethod { standard, abcStrengthCycle }

class PlanSessionPreference {
  final TrainingType trainingType;
  final int durationMinutes;
  final PlanIntensityBand intensityBand;
  final List<String> focusCodes;

  const PlanSessionPreference({
    required this.trainingType,
    required this.durationMinutes,
    required this.intensityBand,
    required this.focusCodes,
  });
}

/// 本地编译器使用的中立偏好，不依赖网络 DTO 字段。
class PlanGenerationPreferences {
  final String generationId;
  final String cycleFocus;
  final PlanProgressionMode progressionMode;
  final PlanGenerationMethod generationMethod;
  final List<PlanSessionPreference> weeklySessions;
  final List<AiKnowledgeCitation> knowledgeCitations;

  const PlanGenerationPreferences({
    required this.generationId,
    required this.cycleFocus,
    required this.progressionMode,
    this.generationMethod = PlanGenerationMethod.standard,
    required this.weeklySessions,
    this.knowledgeCitations = const <AiKnowledgeCitation>[],
  });

  bool get usesAbcStrengthCycle =>
      generationMethod == PlanGenerationMethod.abcStrengthCycle;

  factory PlanGenerationPreferences.fromPrescription({
    required AiTrainingPrescription prescription,
    required String generationId,
  }) {
    return PlanGenerationPreferences(
      generationId: generationId,
      cycleFocus: prescription.cycleFocus,
      progressionMode:
          prescription.progressionMode == AiProgressionMode.balanced
              ? PlanProgressionMode.balanced
              : PlanProgressionMode.conservative,
      generationMethod: prescription.skill.id == 'training-plan-builder' &&
              prescription.skill.coverage == 'strength' &&
              prescription.skill.fragmentSha256 != null
          ? PlanGenerationMethod.abcStrengthCycle
          : PlanGenerationMethod.standard,
      weeklySessions: prescription.weeklySessions
          .map(
            (AiSessionBlueprint item) => PlanSessionPreference(
              trainingType: item.trainingType,
              durationMinutes: item.durationMinutes,
              intensityBand: switch (item.intensityBand) {
                AiIntensityBand.recovery => PlanIntensityBand.recovery,
                AiIntensityBand.easy => PlanIntensityBand.easy,
                AiIntensityBand.moderate => PlanIntensityBand.moderate,
                AiIntensityBand.challenging => PlanIntensityBand.challenging,
              },
              focusCodes: List<String>.unmodifiable(item.focusCodes),
            ),
          )
          .toList(growable: false),
      knowledgeCitations: List<AiKnowledgeCitation>.unmodifiable(
        prescription.knowledgeCitations,
      ),
    );
  }
}
