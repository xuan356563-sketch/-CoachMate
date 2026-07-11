import 'evidence_source.dart';
import 'motion_pose.dart';

enum MotionCheckType {
  squat,
  lunge,
  hipHinge,
  pushUp,
  plank,
  calfRaise,
  highKnee,
  sideRun,
}

extension MotionCheckTypeJson on MotionCheckType {
  String get jsonValue {
    switch (this) {
      case MotionCheckType.squat:
        return 'squat';
      case MotionCheckType.lunge:
        return 'lunge';
      case MotionCheckType.hipHinge:
        return 'hip_hinge';
      case MotionCheckType.pushUp:
        return 'push_up';
      case MotionCheckType.plank:
        return 'plank';
      case MotionCheckType.calfRaise:
        return 'calf_raise';
      case MotionCheckType.highKnee:
        return 'high_knee';
      case MotionCheckType.sideRun:
        return 'side_run';
    }
  }

  String get label {
    switch (this) {
      case MotionCheckType.squat:
        return '深蹲';
      case MotionCheckType.lunge:
        return '弓步蹲';
      case MotionCheckType.hipHinge:
        return '髋铰链';
      case MotionCheckType.pushUp:
        return '俯卧撑';
      case MotionCheckType.plank:
        return '平板支撑';
      case MotionCheckType.calfRaise:
        return '提踵';
      case MotionCheckType.highKnee:
        return '高抬腿';
      case MotionCheckType.sideRun:
        return '跑步侧面姿态';
    }
  }
}

MotionCheckType motionCheckTypeFromJson(String? value) {
  switch (value) {
    case 'squat':
      return MotionCheckType.squat;
    case 'lunge':
      return MotionCheckType.lunge;
    case 'hip_hinge':
      return MotionCheckType.hipHinge;
    case 'push_up':
      return MotionCheckType.pushUp;
    case 'plank':
      return MotionCheckType.plank;
    case 'calf_raise':
      return MotionCheckType.calfRaise;
    case 'high_knee':
      return MotionCheckType.highKnee;
    case 'side_run':
      return MotionCheckType.sideRun;
    default:
      return MotionCheckType.squat;
  }
}

enum MotionRiskLevel {
  low,
  medium,
  high,
}

extension MotionRiskLevelJson on MotionRiskLevel {
  String get jsonValue {
    switch (this) {
      case MotionRiskLevel.low:
        return 'low';
      case MotionRiskLevel.medium:
        return 'medium';
      case MotionRiskLevel.high:
        return 'high';
    }
  }

  String get label {
    switch (this) {
      case MotionRiskLevel.low:
        return '低风险';
      case MotionRiskLevel.medium:
        return '中风险';
      case MotionRiskLevel.high:
        return '高风险';
    }
  }
}

MotionRiskLevel motionRiskLevelFromJson(String? value) {
  switch (value) {
    case 'low':
      return MotionRiskLevel.low;
    case 'medium':
      return MotionRiskLevel.medium;
    case 'high':
      return MotionRiskLevel.high;
    default:
      return MotionRiskLevel.medium;
  }
}

class MotionCheckRule {
  final String id;
  final String? exerciseId;
  final MotionCheckType type;
  final String title;
  final String description;
  final int score;
  final MotionRiskLevel riskLevel;
  final List<String> targetAngles;
  final List<String> commonIssues;
  final List<String> correctionCues;
  final List<String> regressions;
  final List<String> nextCaptureTips;
  final List<EvidenceSource> evidenceSources;

  const MotionCheckRule({
    required this.id,
    this.exerciseId,
    required this.type,
    required this.title,
    required this.description,
    required this.score,
    required this.riskLevel,
    required this.targetAngles,
    required this.commonIssues,
    required this.correctionCues,
    required this.regressions,
    required this.nextCaptureTips,
    required this.evidenceSources,
  });

  factory MotionCheckRule.fromJson(Map<String, dynamic> json) {
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    return MotionCheckRule(
      id: json['id'] as String? ?? '',
      exerciseId: json['exerciseId'] as String?,
      type: motionCheckTypeFromJson(json['type'] as String?),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      riskLevel: motionRiskLevelFromJson(json['riskLevel'] as String?),
      targetAngles:
          List<String>.from(json['targetAngles'] as List<dynamic>? ?? []),
      commonIssues:
          List<String>.from(json['commonIssues'] as List<dynamic>? ?? []),
      correctionCues:
          List<String>.from(json['correctionCues'] as List<dynamic>? ?? []),
      regressions:
          List<String>.from(json['regressions'] as List<dynamic>? ?? []),
      nextCaptureTips:
          List<String>.from(json['nextCaptureTips'] as List<dynamic>? ?? []),
      evidenceSources: evidenceJson
          .map(
            (dynamic value) =>
                EvidenceSource.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'exerciseId': exerciseId,
      'type': type.jsonValue,
      'title': title,
      'description': description,
      'score': score,
      'riskLevel': riskLevel.jsonValue,
      'targetAngles': targetAngles,
      'commonIssues': commonIssues,
      'correctionCues': correctionCues,
      'regressions': regressions,
      'nextCaptureTips': nextCaptureTips,
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
    };
  }
}

class MotionAnalysisResult {
  final String id;
  final String sourceRuleId;
  final MotionCheckType type;
  final String title;
  final int score;
  final MotionRiskLevel riskLevel;
  final DateTime capturedAt;
  final List<String> detectedErrors;
  final List<String> involvedAreas;
  final String bodyEngineSummary;
  final String decisionImpact;
  final TrainingDecisionImpact suggestedImpact;
  final List<String> replacementActions;
  final List<EvidenceSource> evidenceSources;
  final String analysisSource;
  final double analysisConfidence;
  final List<String> angleMetrics;
  final MotionPoseFrame? poseFrame;

  const MotionAnalysisResult({
    required this.id,
    required this.sourceRuleId,
    required this.type,
    required this.title,
    required this.score,
    required this.riskLevel,
    required this.capturedAt,
    required this.detectedErrors,
    required this.involvedAreas,
    required this.bodyEngineSummary,
    required this.decisionImpact,
    required this.suggestedImpact,
    required this.replacementActions,
    required this.evidenceSources,
    this.analysisSource = '本地规则 Mock',
    this.analysisConfidence = 0,
    this.angleMetrics = const [],
    this.poseFrame,
  });

  String get capturedDateLabel {
    return '${capturedAt.year}-${capturedAt.month.toString().padLeft(2, '0')}-${capturedAt.day.toString().padLeft(2, '0')}';
  }

  factory MotionAnalysisResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    final dynamic poseFrameJson = json['poseFrame'];
    return MotionAnalysisResult(
      id: json['id'] as String? ?? '',
      sourceRuleId: json['sourceRuleId'] as String? ?? '',
      type: motionCheckTypeFromJson(json['type'] as String?),
      title: json['title'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      riskLevel: motionRiskLevelFromJson(json['riskLevel'] as String?),
      capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      detectedErrors:
          List<String>.from(json['detectedErrors'] as List<dynamic>? ?? []),
      involvedAreas:
          List<String>.from(json['involvedAreas'] as List<dynamic>? ?? []),
      bodyEngineSummary: json['bodyEngineSummary'] as String? ?? '',
      decisionImpact: json['decisionImpact'] as String? ?? '',
      suggestedImpact:
          trainingDecisionImpactFromJson(json['suggestedImpact'] as String?),
      replacementActions:
          List<String>.from(json['replacementActions'] as List<dynamic>? ?? []),
      evidenceSources: evidenceJson
          .map(
            (dynamic value) =>
                EvidenceSource.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
      analysisSource: json['analysisSource'] as String? ?? '本地规则 Mock',
      analysisConfidence: (json['analysisConfidence'] as num?)?.toDouble() ?? 0,
      angleMetrics:
          List<String>.from(json['angleMetrics'] as List<dynamic>? ?? []),
      poseFrame: poseFrameJson is Map<String, dynamic>
          ? MotionPoseFrame.fromJson(poseFrameJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceRuleId': sourceRuleId,
      'type': type.jsonValue,
      'title': title,
      'score': score,
      'riskLevel': riskLevel.jsonValue,
      'capturedAt': capturedAt.toIso8601String(),
      'detectedErrors': detectedErrors,
      'involvedAreas': involvedAreas,
      'bodyEngineSummary': bodyEngineSummary,
      'decisionImpact': decisionImpact,
      'suggestedImpact': suggestedImpact.jsonValue,
      'replacementActions': replacementActions,
      'analysisSource': analysisSource,
      'analysisConfidence': analysisConfidence,
      'angleMetrics': angleMetrics,
      'poseFrame': poseFrame?.toJson(),
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
    };
  }
}

enum TrainingDecisionImpact {
  keep,
  deload,
  technique,
}

extension TrainingDecisionImpactLabel on TrainingDecisionImpact {
  String get jsonValue {
    switch (this) {
      case TrainingDecisionImpact.keep:
        return 'keep';
      case TrainingDecisionImpact.deload:
        return 'deload';
      case TrainingDecisionImpact.technique:
        return 'technique';
    }
  }

  String get label {
    switch (this) {
      case TrainingDecisionImpact.keep:
        return '保持计划';
      case TrainingDecisionImpact.deload:
        return '建议降级';
      case TrainingDecisionImpact.technique:
        return '转技术日';
    }
  }
}

TrainingDecisionImpact trainingDecisionImpactFromJson(String? value) {
  switch (value) {
    case 'keep':
      return TrainingDecisionImpact.keep;
    case 'technique':
      return TrainingDecisionImpact.technique;
    case 'deload':
    default:
      return TrainingDecisionImpact.deload;
  }
}
