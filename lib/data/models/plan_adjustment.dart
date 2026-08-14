enum PlanAdjustmentKind {
  adjusted,
  restored,
}

extension PlanAdjustmentKindLabel on PlanAdjustmentKind {
  String get label {
    switch (this) {
      case PlanAdjustmentKind.adjusted:
        return '手动调整';
      case PlanAdjustmentKind.restored:
        return '恢复原计划';
    }
  }

  String get jsonValue {
    switch (this) {
      case PlanAdjustmentKind.adjusted:
        return 'adjusted';
      case PlanAdjustmentKind.restored:
        return 'restored';
    }
  }
}

PlanAdjustmentKind planAdjustmentKindFromJson(String? value) {
  switch (value) {
    case 'restored':
      return PlanAdjustmentKind.restored;
    case 'adjusted':
    default:
      return PlanAdjustmentKind.adjusted;
  }
}

class PlanAdjustment {
  final String id;
  final String planId;
  final String workoutDayId;
  final String workoutTitle;
  final int originalEstimatedMinutes;
  final int adjustedEstimatedMinutes;
  final String originalIntensity;
  final String adjustedIntensity;
  final String reason;
  final PlanAdjustmentKind kind;
  final DateTime adjustedAt;

  /// 由待确认调整建议产生时记录来源；手动调整保持为空。
  final String? sourceProposalId;

  const PlanAdjustment({
    required this.id,
    required this.planId,
    required this.workoutDayId,
    required this.workoutTitle,
    required this.originalEstimatedMinutes,
    required this.adjustedEstimatedMinutes,
    required this.originalIntensity,
    required this.adjustedIntensity,
    required this.reason,
    required this.kind,
    required this.adjustedAt,
    this.sourceProposalId,
  });

  factory PlanAdjustment.fromJson(Map<String, dynamic> json) {
    return PlanAdjustment(
      id: json['id'] as String? ?? '',
      planId: json['planId'] as String? ?? '',
      workoutDayId: json['workoutDayId'] as String? ?? '',
      workoutTitle: json['workoutTitle'] as String? ?? '',
      originalEstimatedMinutes:
          (json['originalEstimatedMinutes'] as num?)?.toInt() ?? 0,
      adjustedEstimatedMinutes:
          (json['adjustedEstimatedMinutes'] as num?)?.toInt() ?? 0,
      originalIntensity: json['originalIntensity'] as String? ?? '',
      adjustedIntensity: json['adjustedIntensity'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      kind: planAdjustmentKindFromJson(json['kind'] as String?),
      adjustedAt: DateTime.tryParse(json['adjustedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceProposalId: json['sourceProposalId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'planId': planId,
      'workoutDayId': workoutDayId,
      'workoutTitle': workoutTitle,
      'originalEstimatedMinutes': originalEstimatedMinutes,
      'adjustedEstimatedMinutes': adjustedEstimatedMinutes,
      'originalIntensity': originalIntensity,
      'adjustedIntensity': adjustedIntensity,
      'reason': reason,
      'kind': kind.jsonValue,
      'adjustedAt': adjustedAt.toIso8601String(),
      if (sourceProposalId != null) 'sourceProposalId': sourceProposalId,
    };
  }

  bool get isActive => kind == PlanAdjustmentKind.adjusted;

  String get adjustedAtLabel {
    final String month = adjustedAt.month.toString().padLeft(2, '0');
    final String day = adjustedAt.day.toString().padLeft(2, '0');
    final String hour = adjustedAt.hour.toString().padLeft(2, '0');
    final String minute = adjustedAt.minute.toString().padLeft(2, '0');
    return '${adjustedAt.year}-$month-$day $hour:$minute';
  }
}
