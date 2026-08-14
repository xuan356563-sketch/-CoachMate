enum OnboardingStage {
  personal,
  training,
  login,
  cloudConsent,
  membership,
  complete,
}

class StructuredInjuryProfile {
  const StructuredInjuryProfile({
    required this.bodyRegion,
    required this.state,
    required this.limitingActivity,
    required this.confirmedNote,
  });

  factory StructuredInjuryProfile.fromJson(Map<String, Object?> json) {
    return StructuredInjuryProfile(
      bodyRegion: json['body_region']! as String,
      state: json['state']! as String,
      limitingActivity: json['limiting_activity']! as String,
      confirmedNote: json['confirmed_note']! as String,
    );
  }

  final String bodyRegion;
  final String state;
  final String limitingActivity;
  final String confirmedNote;

  Map<String, Object?> toJson() => <String, Object?>{
        'body_region': bodyRegion,
        'state': state,
        'limiting_activity': limitingActivity,
        'confirmed_note': confirmedNote,
      };
}

class PersonalProfileDraft {
  const PersonalProfileDraft({
    required this.nickname,
    required this.gender,
    required this.declaredAge,
    this.heightCm,
    this.weightKg,
    required this.workerProfileType,
    required this.workScheduleType,
    required this.trainingGoal,
    required this.mainSports,
    required this.trainingExperienceLevel,
    required this.injuries,
  });

  factory PersonalProfileDraft.fromJson(Map<String, Object?> json) {
    return PersonalProfileDraft(
      nickname: json['nickname']! as String,
      gender: json['gender']! as String,
      declaredAge: json['declared_age']! as int,
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      workerProfileType: json['worker_profile_type']! as String,
      workScheduleType: json['work_schedule_type']! as String,
      trainingGoal: json['training_goal']! as String,
      mainSports: List<String>.from(json['main_sports']! as List<Object?>),
      trainingExperienceLevel: json['training_experience_level']! as String,
      injuries: (json['injuries']! as List<Object?>)
          .map(
            (Object? value) => StructuredInjuryProfile.fromJson(
              Map<String, Object?>.from(value! as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final String nickname;
  final String gender;
  final int declaredAge;
  final double? heightCm;
  final double? weightKg;
  final String workerProfileType;
  final String workScheduleType;
  final String trainingGoal;
  final List<String> mainSports;
  final String trainingExperienceLevel;
  final List<StructuredInjuryProfile> injuries;

  bool get isAdult => declaredAge >= 18;

  Map<String, Object?> toJson() => <String, Object?>{
        'nickname': nickname,
        'gender': gender,
        'declared_age': declaredAge,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'worker_profile_type': workerProfileType,
        'work_schedule_type': workScheduleType,
        'training_goal': trainingGoal,
        'main_sports': List<String>.of(mainSports),
        'training_experience_level': trainingExperienceLevel,
        'injuries': injuries
            .map((StructuredInjuryProfile value) => value.toJson())
            .toList(growable: false),
      };
}

class TrainingBaselineDraft {
  const TrainingBaselineDraft({
    required this.trainingEnvironment,
    required this.weeklyTrainingDays,
    required this.dailyAvailableMinutes,
    required this.coreSelfReport,
    required this.aerobicTalkTest,
    required this.cardioRecovery,
  });

  factory TrainingBaselineDraft.fromJson(Map<String, Object?> json) {
    return TrainingBaselineDraft(
      trainingEnvironment: json['training_environment']! as String,
      weeklyTrainingDays: json['weekly_training_days']! as int,
      dailyAvailableMinutes: json['daily_available_minutes']! as int,
      coreSelfReport: json['core_self_report']! as String,
      aerobicTalkTest: json['aerobic_talk_test']! as String,
      cardioRecovery: json['cardio_recovery']! as String,
    );
  }

  final String trainingEnvironment;
  final int weeklyTrainingDays;
  final int dailyAvailableMinutes;
  final String coreSelfReport;
  final String aerobicTalkTest;
  final String cardioRecovery;

  Map<String, Object?> toJson() => <String, Object?>{
        'training_environment': trainingEnvironment,
        'weekly_training_days': weeklyTrainingDays,
        'daily_available_minutes': dailyAvailableMinutes,
        'core_self_report': coreSelfReport,
        'aerobic_talk_test': aerobicTalkTest,
        'cardio_recovery': cardioRecovery,
      };
}

class HealthCloudConsent {
  const HealthCloudConsent({
    required this.includeHeight,
    required this.includeWeight,
    required this.includeInjuries,
    required this.documentVersion,
  });

  final bool includeHeight;
  final bool includeWeight;
  final bool includeInjuries;
  final String documentVersion;

  bool get includesHealth => includeHeight || includeWeight || includeInjuries;

  Map<String, Object?> toJson() => <String, Object?>{
        'include_height': includeHeight,
        'include_weight': includeWeight,
        'include_injuries': includeInjuries,
        'document_version': documentVersion,
      };

  factory HealthCloudConsent.fromJson(Map<String, Object?> json) {
    return HealthCloudConsent(
      includeHeight: json['include_height']! as bool,
      includeWeight: json['include_weight']! as bool,
      includeInjuries: json['include_injuries']! as bool,
      documentVersion: json['document_version']! as String,
    );
  }
}

enum MembershipEntitlementStatus {
  none,
  trial,
  active,
  gracePeriod,
  billingRetry,
  expired,
  revoked,
}

class MembershipEntitlement {
  const MembershipEntitlement({
    required this.status,
    required this.canGeneratePlan,
    this.productId,
    this.expiresAt,
  });

  final MembershipEntitlementStatus status;
  final bool canGeneratePlan;
  final String? productId;
  final DateTime? expiresAt;
}

class FirstRunDraft {
  const FirstRunDraft({
    required this.stage,
    required this.createdAt,
    required this.updatedAt,
    this.personal,
    this.training,
    this.healthConsent,
    this.boundUserId,
  });

  factory FirstRunDraft.initial(DateTime now) => FirstRunDraft(
        stage: OnboardingStage.personal,
        createdAt: now,
        updatedAt: now,
      );

  factory FirstRunDraft.fromJson(Map<String, Object?> json) {
    return FirstRunDraft(
      stage: OnboardingStage.values.byName(json['stage']! as String),
      createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at']! as String).toUtc(),
      personal: json['personal'] == null
          ? null
          : PersonalProfileDraft.fromJson(
              Map<String, Object?>.from(json['personal']! as Map),
            ),
      training: json['training'] == null
          ? null
          : TrainingBaselineDraft.fromJson(
              Map<String, Object?>.from(json['training']! as Map),
            ),
      healthConsent: json['health_consent'] == null
          ? null
          : HealthCloudConsent.fromJson(
              Map<String, Object?>.from(json['health_consent']! as Map),
            ),
      boundUserId: json['bound_user_id'] as String?,
    );
  }

  final OnboardingStage stage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PersonalProfileDraft? personal;
  final TrainingBaselineDraft? training;
  final HealthCloudConsent? healthConsent;
  final String? boundUserId;

  bool isExpiredAt(DateTime now) =>
      stage != OnboardingStage.complete &&
      now.toUtc().difference(updatedAt.toUtc()) > const Duration(days: 7);

  FirstRunDraft copyWith({
    OnboardingStage? stage,
    DateTime? updatedAt,
    PersonalProfileDraft? personal,
    TrainingBaselineDraft? training,
    HealthCloudConsent? healthConsent,
    String? boundUserId,
  }) {
    return FirstRunDraft(
      stage: stage ?? this.stage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      personal: personal ?? this.personal,
      training: training ?? this.training,
      healthConsent: healthConsent ?? this.healthConsent,
      boundUserId: boundUserId ?? this.boundUserId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'stage': stage.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'personal': personal?.toJson(),
        'training': training?.toJson(),
        'health_consent': healthConsent?.toJson(),
        'bound_user_id': boundUserId,
      };
}
