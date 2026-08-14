import 'ai_training_prescription.dart';

enum AiCapability {
  trainer,
  motion,
  recovery,
  nutrition,
  gear,
  race,
  coach,
}

extension AiCapabilityLabel on AiCapability {
  String get jsonValue => switch (this) {
        AiCapability.trainer => 'trainer',
        AiCapability.motion => 'motion',
        AiCapability.recovery => 'recovery',
        AiCapability.nutrition => 'nutrition',
        AiCapability.gear => 'gear',
        AiCapability.race => 'race',
        AiCapability.coach => 'coach',
      };

  String get label => switch (this) {
        AiCapability.trainer => 'AI Trainer',
        AiCapability.motion => 'AI Motion',
        AiCapability.recovery => 'AI Recovery',
        AiCapability.nutrition => 'AI Nutrition',
        AiCapability.gear => 'AI Gear',
        AiCapability.race => 'AI Race',
        AiCapability.coach => 'AI Coach',
      };
}

AiCapability aiCapabilityFromJson(String? value) {
  return switch (value) {
    'motion' => AiCapability.motion,
    'recovery' => AiCapability.recovery,
    'nutrition' => AiCapability.nutrition,
    'gear' => AiCapability.gear,
    'race' => AiCapability.race,
    'coach' => AiCapability.coach,
    _ => AiCapability.trainer,
  };
}

enum AiArtifactDecision { pending, accepted, rejected }

extension AiArtifactDecisionJson on AiArtifactDecision {
  String get jsonValue => switch (this) {
        AiArtifactDecision.pending => 'pending',
        AiArtifactDecision.accepted => 'accepted',
        AiArtifactDecision.rejected => 'rejected',
      };
}

AiArtifactDecision aiArtifactDecisionFromJson(String? value) {
  return switch (value) {
    'accepted' => AiArtifactDecision.accepted,
    'rejected' => AiArtifactDecision.rejected,
    _ => AiArtifactDecision.pending,
  };
}

/// 仅保存服务端 Schema 校验后的 UI 产物，不保存原始提示词、照片或音频。
class AiArtifact {
  final String id;
  final AiCapability capability;
  final String artifactType;
  final int schemaVersion;
  final AiArtifactDecision decision;
  final String contextDigest;
  final Map<String, dynamic> payload;
  final List<String> warnings;
  final String provider;
  final String model;
  final DateTime generatedAt;
  final DateTime? decidedAt;

  const AiArtifact({
    required this.id,
    required this.capability,
    required this.artifactType,
    required this.schemaVersion,
    required this.decision,
    required this.contextDigest,
    required this.payload,
    required this.warnings,
    required this.provider,
    required this.model,
    required this.generatedAt,
    this.decidedAt,
  });

  bool get isPending => decision == AiArtifactDecision.pending;

  AiTrainerPlan? get trainerPlan => artifactType == 'trainer_plan_v1'
      ? AiTrainerPlan.fromJson(payload)
      : null;

  AiTrainingPrescription? get trainingPrescription =>
      artifactType == 'training_prescription_v1' ||
              artifactType == 'training_prescription_v2'
          ? AiTrainingPrescription.fromJson(payload)
          : null;

  AiRecoveryDashboard? get recoveryDashboard =>
      artifactType == 'recovery_dashboard_v1'
          ? AiRecoveryDashboard.fromJson(payload)
          : null;

  AiMotionScore? get motionScore => artifactType == 'motion_score_v1'
      ? AiMotionScore.fromJson(payload)
      : null;

  factory AiArtifact.fromJson(Map<String, dynamic> json) {
    final Object? rawPayload = json['payload'];
    return AiArtifact(
      id: json['id'] as String? ?? '',
      capability: aiCapabilityFromJson(json['capability'] as String?),
      artifactType: json['artifact_type'] as String? ??
          json['artifactType'] as String? ??
          '',
      schemaVersion: (json['schema_version'] as num?)?.toInt() ??
          (json['schemaVersion'] as num?)?.toInt() ??
          1,
      decision: aiArtifactDecisionFromJson(
        json['decision_status'] as String? ?? json['decision'] as String?,
      ),
      contextDigest: json['context_digest'] as String? ??
          json['contextDigest'] as String? ??
          '',
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
      warnings: _strings(json['warnings']),
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      generatedAt: DateTime.tryParse(
            json['generated_at'] as String? ??
                json['generatedAt'] as String? ??
                '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      decidedAt: DateTime.tryParse(
        json['decided_at'] as String? ?? json['decidedAt'] as String? ?? '',
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'capability': capability.jsonValue,
        'artifact_type': artifactType,
        'schema_version': schemaVersion,
        'decision_status': decision.jsonValue,
        'context_digest': contextDigest,
        'payload': payload,
        'warnings': warnings,
        'provider': provider,
        'model': model,
        'generated_at': generatedAt.toIso8601String(),
        'decided_at': decidedAt?.toIso8601String(),
      };

  AiArtifact copyWith({
    AiArtifactDecision? decision,
    DateTime? decidedAt,
  }) =>
      AiArtifact(
        id: id,
        capability: capability,
        artifactType: artifactType,
        schemaVersion: schemaVersion,
        decision: decision ?? this.decision,
        contextDigest: contextDigest,
        payload: payload,
        warnings: warnings,
        provider: provider,
        model: model,
        generatedAt: generatedAt,
        decidedAt: decidedAt ?? this.decidedAt,
      );
}

class AiHealthSummary {
  final double? sleepHours;
  final int? restingHeartRate;
  final int? hrvMs;
  final int? fatigueLevel;

  const AiHealthSummary({
    this.sleepHours,
    this.restingHeartRate,
    this.hrvMs,
    this.fatigueLevel,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sleep_hours': sleepHours,
        'resting_heart_rate': restingHeartRate,
        'hrv_ms': hrvMs,
        'fatigue_level': fatigueLevel,
      };
}

class AiGenerationContext {
  final String goal;
  final List<String> sports;
  final int availableMinutes;
  final int? scheduledMinutes;
  final String? scheduledPeriod;
  final int readinessScore;
  final String dailyDecision;
  final int painLevel;
  final AiHealthSummary? healthSummary;

  const AiGenerationContext({
    required this.goal,
    required this.sports,
    required this.availableMinutes,
    this.scheduledMinutes,
    this.scheduledPeriod,
    required this.readinessScore,
    required this.dailyDecision,
    required this.painLevel,
    this.healthSummary,
  });

  /// 云端 AI 只接收训练目标和时间约束。
  ///
  /// readiness、疼痛、日决策与 HealthKit 摘要均属于健康或健康派生数据，
  /// 即使用户曾在旧版本同意，也不得进入网络 DTO。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'goal': goal,
        'sports': sports,
        'available_minutes': availableMinutes,
        'scheduled_minutes': scheduledMinutes,
        'scheduled_period': scheduledPeriod,
      };
}

class AiTrainerPlan {
  final String cycleLabel;
  final String weeklyStructure;
  final List<AiTrainerWorkoutCard> workoutCards;
  final List<String> safetyNotes;

  const AiTrainerPlan({
    required this.cycleLabel,
    required this.weeklyStructure,
    required this.workoutCards,
    required this.safetyNotes,
  });

  factory AiTrainerPlan.fromJson(Map<String, dynamic> json) => AiTrainerPlan(
        cycleLabel: json['cycle_label'] as String? ?? '',
        weeklyStructure: json['weekly_structure'] as String? ?? '',
        workoutCards: _maps(json['workout_cards'])
            .map(AiTrainerWorkoutCard.fromJson)
            .toList(),
        safetyNotes: _strings(json['safety_notes']),
      );
}

class AiTrainerWorkoutCard {
  final String title;
  final int durationMinutes;
  final String intensity;
  final List<String> focus;
  final String safetyNote;

  const AiTrainerWorkoutCard({
    required this.title,
    required this.durationMinutes,
    required this.intensity,
    required this.focus,
    required this.safetyNote,
  });

  factory AiTrainerWorkoutCard.fromJson(Map<String, dynamic> json) =>
      AiTrainerWorkoutCard(
        title: json['title'] as String? ?? '',
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
        intensity: json['intensity'] as String? ?? '',
        focus: _strings(json['focus']),
        safetyNote: json['safety_note'] as String? ?? '',
      );
}

class AiRecoveryDashboard {
  final int readinessScore;
  final String recommendedAction;
  final List<String> factors;
  final List<String> todayTasks;
  final List<String> redFlags;
  final String safetyNote;

  const AiRecoveryDashboard({
    required this.readinessScore,
    required this.recommendedAction,
    required this.factors,
    required this.todayTasks,
    required this.redFlags,
    required this.safetyNote,
  });

  factory AiRecoveryDashboard.fromJson(Map<String, dynamic> json) =>
      AiRecoveryDashboard(
        readinessScore: (json['readiness_score'] as num?)?.toInt() ?? 0,
        recommendedAction: json['recommended_action'] as String? ?? '',
        factors: _strings(json['factors']),
        todayTasks: _strings(json['today_tasks']),
        redFlags: _strings(json['red_flags']),
        safetyNote: json['safety_note'] as String? ?? '',
      );
}

class AiMotionScore {
  final int score;
  final String riskLevel;
  final double confidence;
  final List<String> detectedErrors;
  final List<String> corrections;
  final List<String> replacements;
  final String safetyNote;

  const AiMotionScore({
    required this.score,
    required this.riskLevel,
    required this.confidence,
    required this.detectedErrors,
    required this.corrections,
    required this.replacements,
    required this.safetyNote,
  });

  factory AiMotionScore.fromJson(Map<String, dynamic> json) => AiMotionScore(
        score: (json['score'] as num?)?.toInt() ?? 0,
        riskLevel: json['risk_level'] as String? ?? 'medium',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        detectedErrors: _strings(json['detected_errors']),
        corrections: _strings(json['corrections']),
        replacements: _strings(json['replacements']),
        safetyNote: json['safety_note'] as String? ?? '',
      );
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((String item) => item.isNotEmpty).toList()
    : const <String>[];

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .toList()
    : const <Map<String, dynamic>>[];
