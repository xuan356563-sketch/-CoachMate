class SelfUseAcceptanceDay {
  final int dayNumber;
  final DateTime date;
  final bool bodyDataLogged;
  final bool planReviewed;
  final bool workoutExecuted;
  final bool feedbackLogged;
  final bool starterProgramChecked;
  final bool blockingIssue;
  final String notes;

  const SelfUseAcceptanceDay({
    required this.dayNumber,
    required this.date,
    this.bodyDataLogged = false,
    this.planReviewed = false,
    this.workoutExecuted = false,
    this.feedbackLogged = false,
    this.starterProgramChecked = false,
    this.blockingIssue = false,
    this.notes = '',
  });

  bool get checklistComplete =>
      bodyDataLogged &&
      planReviewed &&
      workoutExecuted &&
      feedbackLogged &&
      starterProgramChecked;

  SelfUseAcceptanceDay copyWith({
    bool? bodyDataLogged,
    bool? planReviewed,
    bool? workoutExecuted,
    bool? feedbackLogged,
    bool? starterProgramChecked,
    bool? blockingIssue,
    String? notes,
  }) {
    return SelfUseAcceptanceDay(
      dayNumber: dayNumber,
      date: date,
      bodyDataLogged: bodyDataLogged ?? this.bodyDataLogged,
      planReviewed: planReviewed ?? this.planReviewed,
      workoutExecuted: workoutExecuted ?? this.workoutExecuted,
      feedbackLogged: feedbackLogged ?? this.feedbackLogged,
      starterProgramChecked:
          starterProgramChecked ?? this.starterProgramChecked,
      blockingIssue: blockingIssue ?? this.blockingIssue,
      notes: notes ?? this.notes,
    );
  }

  factory SelfUseAcceptanceDay.fromJson(Map<String, dynamic> json) {
    return SelfUseAcceptanceDay(
      dayNumber: (json['dayNumber'] as num?)?.toInt() ?? 1,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      bodyDataLogged: json['bodyDataLogged'] as bool? ?? false,
      planReviewed: json['planReviewed'] as bool? ?? false,
      workoutExecuted: json['workoutExecuted'] as bool? ?? false,
      feedbackLogged: json['feedbackLogged'] as bool? ?? false,
      starterProgramChecked: json['starterProgramChecked'] as bool? ?? false,
      blockingIssue: json['blockingIssue'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dayNumber': dayNumber,
      'date': date.toIso8601String(),
      'bodyDataLogged': bodyDataLogged,
      'planReviewed': planReviewed,
      'workoutExecuted': workoutExecuted,
      'feedbackLogged': feedbackLogged,
      'starterProgramChecked': starterProgramChecked,
      'blockingIssue': blockingIssue,
      'notes': notes,
    };
  }
}

class SelfUseAcceptanceRecord {
  final DateTime? startedAt;
  final List<SelfUseAcceptanceDay> days;

  const SelfUseAcceptanceRecord({
    required this.startedAt,
    required this.days,
  });

  const SelfUseAcceptanceRecord.empty()
      : startedAt = null,
        days = const [];

  bool get isStarted => startedAt != null && days.isNotEmpty;

  int get completedDayCount =>
      days.where((SelfUseAcceptanceDay day) => day.checklistComplete).length;

  int get blockingDayCount =>
      days.where((SelfUseAcceptanceDay day) => day.blockingIssue).length;

  bool get checklistReady =>
      days.length == 14 && completedDayCount == 14 && blockingDayCount == 0;

  SelfUseAcceptanceDay? findDay(int dayNumber) {
    for (final SelfUseAcceptanceDay day in days) {
      if (day.dayNumber == dayNumber) {
        return day;
      }
    }
    return null;
  }

  SelfUseAcceptanceRecord copyWith({
    DateTime? startedAt,
    List<SelfUseAcceptanceDay>? days,
  }) {
    return SelfUseAcceptanceRecord(
      startedAt: startedAt ?? this.startedAt,
      days: days ?? this.days,
    );
  }

  factory SelfUseAcceptanceRecord.fromJson(Map<String, dynamic> json) {
    final List<dynamic> daysJson = json['days'] as List<dynamic>? ?? [];
    return SelfUseAcceptanceRecord(
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      days: daysJson
          .whereType<Map<String, dynamic>>()
          .map(SelfUseAcceptanceDay.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 1,
      'startedAt': startedAt?.toIso8601String(),
      'days': days.map((SelfUseAcceptanceDay day) => day.toJson()).toList(),
    };
  }
}
