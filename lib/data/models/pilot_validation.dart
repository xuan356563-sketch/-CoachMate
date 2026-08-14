enum PilotScenario { raceRunning, fatLoss, sedentaryRecovery }

extension PilotScenarioLabel on PilotScenario {
  String get label => switch (this) {
        PilotScenario.raceRunning => '跑步/备赛',
        PilotScenario.fatLoss => '减脂',
        PilotScenario.sedentaryRecovery => '久坐恢复',
      };

  String get jsonValue => switch (this) {
        PilotScenario.raceRunning => 'race_running',
        PilotScenario.fatLoss => 'fat_loss',
        PilotScenario.sedentaryRecovery => 'sedentary_recovery',
      };
}

PilotScenario pilotScenarioFromJson(String? value) => switch (value) {
      'fat_loss' => PilotScenario.fatLoss,
      'sedentary_recovery' => PilotScenario.sedentaryRecovery,
      _ => PilotScenario.raceRunning,
    };

enum PilotDepositStatus {
  notApplicable,
  pendingOffline,
  receivedOffline,
  refundDue,
  refundedOffline,
}

extension PilotDepositStatusLabel on PilotDepositStatus {
  String get label => switch (this) {
        PilotDepositStatus.notApplicable => '不适用',
        PilotDepositStatus.pendingOffline => '线下待确认',
        PilotDepositStatus.receivedOffline => '线下已收 19.9 元',
        PilotDepositStatus.refundDue => '线下待退',
        PilotDepositStatus.refundedOffline => '线下已退',
      };
}

enum PilotContinuationDecision { pending, acceptedEarlyBird, declined }

extension PilotContinuationDecisionLabel on PilotContinuationDecision {
  String get label => switch (this) {
        PilotContinuationDecision.pending => '第 14 天待决定',
        PilotContinuationDecision.acceptedEarlyBird => '接受 9.9 元/月早鸟价',
        PilotContinuationDecision.declined => '暂不继续',
      };
}

class PilotParticipantRecord {
  const PilotParticipantRecord({
    required this.id,
    required this.alias,
    required this.scenario,
    required this.startedOn,
    required this.commitmentAcceptedAt,
    required this.checkInDates,
    required this.feedbackDates,
    required this.depositStatus,
    required this.continuationDecision,
  });

  final String id;
  final String alias;
  final PilotScenario scenario;
  final DateTime startedOn;
  final DateTime? commitmentAcceptedAt;
  final List<DateTime> checkInDates;
  final List<DateTime> feedbackDates;
  final PilotDepositStatus depositStatus;
  final PilotContinuationDecision continuationDecision;

  int get checkInCount => checkInDates.length;
  int get feedbackCount => feedbackDates.length;
  bool get commitmentAccepted => commitmentAcceptedAt != null;

  PilotParticipantRecord copyWith({
    DateTime? commitmentAcceptedAt,
    List<DateTime>? checkInDates,
    List<DateTime>? feedbackDates,
    PilotDepositStatus? depositStatus,
    PilotContinuationDecision? continuationDecision,
  }) {
    return PilotParticipantRecord(
      id: id,
      alias: alias,
      scenario: scenario,
      startedOn: startedOn,
      commitmentAcceptedAt: commitmentAcceptedAt ?? this.commitmentAcceptedAt,
      checkInDates: checkInDates ?? this.checkInDates,
      feedbackDates: feedbackDates ?? this.feedbackDates,
      depositStatus: depositStatus ?? this.depositStatus,
      continuationDecision: continuationDecision ?? this.continuationDecision,
    );
  }

  factory PilotParticipantRecord.fromJson(Map<String, dynamic> json) {
    return PilotParticipantRecord(
      id: json['id'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      scenario: pilotScenarioFromJson(json['scenario'] as String?),
      startedOn: _parseDate(json['startedOn']) ?? DateTime(1970),
      commitmentAcceptedAt:
          DateTime.tryParse(json['commitmentAcceptedAt'] as String? ?? ''),
      checkInDates: _parseDateList(json['checkInDates']),
      feedbackDates: _parseDateList(json['feedbackDates']),
      depositStatus:
          _pilotDepositStatusFromJson(json['depositStatus'] as String?),
      continuationDecision: _pilotContinuationDecisionFromJson(
        json['continuationDecision'] as String?,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'alias': alias,
        'scenario': scenario.jsonValue,
        'startedOn': _dateKey(startedOn),
        if (commitmentAcceptedAt != null)
          'commitmentAcceptedAt': commitmentAcceptedAt!.toIso8601String(),
        'checkInDates': checkInDates.map(_dateKey).toList(growable: false),
        'feedbackDates': feedbackDates.map(_dateKey).toList(growable: false),
        'depositStatus': depositStatus.name,
        'continuationDecision': continuationDecision.name,
      };
}

DateTime? _parseDate(Object? value) {
  final DateTime? parsed = DateTime.tryParse(value as String? ?? '');
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

List<DateTime> _parseDateList(Object? value) {
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map(_parseDate)
      .whereType<DateTime>()
      .toList(growable: false);
}

PilotDepositStatus _pilotDepositStatusFromJson(String? value) {
  return PilotDepositStatus.values
          .where((PilotDepositStatus status) => status.name == value)
          .firstOrNull ??
      PilotDepositStatus.notApplicable;
}

PilotContinuationDecision _pilotContinuationDecisionFromJson(String? value) {
  return PilotContinuationDecision.values
          .where((PilotContinuationDecision decision) => decision.name == value)
          .firstOrNull ??
      PilotContinuationDecision.pending;
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
