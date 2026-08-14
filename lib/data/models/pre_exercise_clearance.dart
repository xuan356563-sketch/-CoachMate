enum PreExerciseClearanceStatus {
  notCompleted,
  selfCleared,
  followUpRequired,
  restrictedOrSupervised,
  physicianUnrestricted,
}

extension PreExerciseClearanceStatusJson on PreExerciseClearanceStatus {
  String get jsonValue => switch (this) {
        PreExerciseClearanceStatus.notCompleted => 'not_completed',
        PreExerciseClearanceStatus.selfCleared => 'self_cleared',
        PreExerciseClearanceStatus.followUpRequired => 'follow_up_required',
        PreExerciseClearanceStatus.restrictedOrSupervised =>
          'restricted_or_supervised',
        PreExerciseClearanceStatus.physicianUnrestricted =>
          'physician_unrestricted',
      };

  String get label => switch (this) {
        PreExerciseClearanceStatus.notCompleted => '尚未完成官方筛查',
        PreExerciseClearanceStatus.selfCleared => '官方流程提示可独立参加运动',
        PreExerciseClearanceStatus.followUpRequired => '官方流程提示需要进一步跟进',
        PreExerciseClearanceStatus.restrictedOrSupervised => '仅适合受限或监督训练',
        PreExerciseClearanceStatus.physicianUnrestricted => '已取得医生无条件许可',
      };
}

PreExerciseClearanceStatus preExerciseClearanceStatusFromJson(String? value) {
  return switch (value) {
    'self_cleared' => PreExerciseClearanceStatus.selfCleared,
    'follow_up_required' => PreExerciseClearanceStatus.followUpRequired,
    'restricted_or_supervised' =>
      PreExerciseClearanceStatus.restrictedOrSupervised,
    'physician_unrestricted' =>
      PreExerciseClearanceStatus.physicianUnrestricted,
    _ => PreExerciseClearanceStatus.notCompleted,
  };
}

class PreExerciseClearance {
  static const String officialSourceUrl = 'https://eparmedx.com/';
  static const String officialSourceLabel = 'PAR-Q+ / ePARmed-X+ 官方流程';
  static const String currentPolicyVersion =
      'eparmedx-current-reviewed-2026-07-17';

  final PreExerciseClearanceStatus status;
  final DateTime? completedAt;
  final DateTime? validUntil;
  final String sourceUrl;
  final String sourceLabel;
  final String policyVersion;
  final bool currentInjuryOrRestriction;
  final DateTime? invalidatedAt;
  final DateTime? conditionChangedAt;

  const PreExerciseClearance({
    required this.status,
    required this.completedAt,
    required this.validUntil,
    required this.sourceUrl,
    required this.sourceLabel,
    required this.policyVersion,
    required this.currentInjuryOrRestriction,
    required this.invalidatedAt,
    required this.conditionChangedAt,
  });

  const PreExerciseClearance.notCompleted()
      : this(
          status: PreExerciseClearanceStatus.notCompleted,
          completedAt: null,
          validUntil: null,
          sourceUrl: officialSourceUrl,
          sourceLabel: officialSourceLabel,
          policyVersion: currentPolicyVersion,
          currentInjuryOrRestriction: false,
          invalidatedAt: null,
          conditionChangedAt: null,
        );

  factory PreExerciseClearance.recorded({
    required PreExerciseClearanceStatus status,
    required bool currentInjuryOrRestriction,
    required DateTime completedAt,
  }) {
    final DateTime? validUntil = switch (status) {
      PreExerciseClearanceStatus.selfCleared =>
        _addCalendarMonths(completedAt, 12),
      PreExerciseClearanceStatus.physicianUnrestricted =>
        _addCalendarMonths(completedAt, 6),
      _ => null,
    };
    return PreExerciseClearance(
      status: status,
      completedAt: completedAt,
      validUntil: validUntil,
      sourceUrl: officialSourceUrl,
      sourceLabel: officialSourceLabel,
      policyVersion: currentPolicyVersion,
      currentInjuryOrRestriction: currentInjuryOrRestriction,
      invalidatedAt: null,
      conditionChangedAt: null,
    );
  }

  bool isValidAt(DateTime now) {
    final bool statusAllowsIndependentExercise =
        status == PreExerciseClearanceStatus.selfCleared ||
            status == PreExerciseClearanceStatus.physicianUnrestricted;
    final DateTime? expiry = validUntil;
    return statusAllowsIndependentExercise &&
        policyVersion == currentPolicyVersion &&
        !currentInjuryOrRestriction &&
        invalidatedAt == null &&
        conditionChangedAt == null &&
        expiry != null &&
        !now.isAfter(expiry);
  }

  String blockingReasonAt(DateTime now) {
    if (currentInjuryOrRestriction) {
      return '当前存在伤病或专业人员限制，AI 计划暂不可激活。';
    }
    if (conditionChangedAt != null) {
      return '身体状况已变化，请重新完成官方筛查。';
    }
    if (policyVersion != currentPolicyVersion) {
      return '官方筛查策略版本已更新，请重新完成官方流程。';
    }
    if (status == PreExerciseClearanceStatus.notCompleted) {
      return '请先在官方页面完成 PAR-Q+ / ePARmed-X+ 流程。';
    }
    if (status == PreExerciseClearanceStatus.followUpRequired) {
      return '官方流程提示需要进一步跟进，暂不可激活 AI 计划。';
    }
    if (status == PreExerciseClearanceStatus.restrictedOrSupervised) {
      return '当前许可包含限制或监督要求，V1 暂不支持激活。';
    }
    final DateTime? expiry = validUntil;
    if (expiry == null || now.isAfter(expiry)) {
      return '筛查记录已过有效期，请重新完成官方流程。';
    }
    if (invalidatedAt != null) {
      return '筛查记录已失效，请重新完成官方流程。';
    }
    return '';
  }

  PreExerciseClearance invalidateForConditionChange(DateTime changedAt) {
    return PreExerciseClearance(
      status: status,
      completedAt: completedAt,
      validUntil: validUntil,
      sourceUrl: sourceUrl,
      sourceLabel: sourceLabel,
      policyVersion: policyVersion,
      currentInjuryOrRestriction: true,
      invalidatedAt: changedAt,
      conditionChangedAt: changedAt,
    );
  }

  PreExerciseClearance invalidateForExpiry(DateTime expiredAt) {
    return PreExerciseClearance(
      status: status,
      completedAt: completedAt,
      validUntil: validUntil,
      sourceUrl: sourceUrl,
      sourceLabel: sourceLabel,
      policyVersion: policyVersion,
      currentInjuryOrRestriction: currentInjuryOrRestriction,
      invalidatedAt: expiredAt,
      conditionChangedAt: conditionChangedAt,
    );
  }

  factory PreExerciseClearance.fromJson(Map<String, dynamic> json) {
    return PreExerciseClearance(
      status: preExerciseClearanceStatusFromJson(json['status'] as String?),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      validUntil: DateTime.tryParse(json['validUntil'] as String? ?? ''),
      sourceUrl: json['sourceUrl'] as String? ?? officialSourceUrl,
      sourceLabel: json['sourceLabel'] as String? ?? officialSourceLabel,
      policyVersion: json['policyVersion'] as String? ?? '',
      currentInjuryOrRestriction:
          json['currentInjuryOrRestriction'] as bool? ?? false,
      invalidatedAt: DateTime.tryParse(json['invalidatedAt'] as String? ?? ''),
      conditionChangedAt:
          DateTime.tryParse(json['conditionChangedAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status.jsonValue,
        'completedAt': completedAt?.toIso8601String(),
        'validUntil': validUntil?.toIso8601String(),
        'sourceUrl': sourceUrl,
        'sourceLabel': sourceLabel,
        'policyVersion': policyVersion,
        'currentInjuryOrRestriction': currentInjuryOrRestriction,
        'invalidatedAt': invalidatedAt?.toIso8601String(),
        'conditionChangedAt': conditionChangedAt?.toIso8601String(),
      };
}

DateTime _addCalendarMonths(DateTime value, int months) {
  final int monthIndex = value.month - 1 + months;
  final int year = value.year + monthIndex ~/ 12;
  final int month = monthIndex % 12 + 1;
  final int lastDay = DateTime(year, month + 1, 0).day;
  final int day = value.day > lastDay ? lastDay : value.day;
  return DateTime(
    year,
    month,
    day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}
