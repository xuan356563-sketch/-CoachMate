enum DailyCheckInSource {
  prefilled,
  subjectiveTired,
}

extension DailyCheckInSourceJson on DailyCheckInSource {
  String get jsonValue => switch (this) {
        DailyCheckInSource.prefilled => 'prefilled',
        DailyCheckInSource.subjectiveTired => 'subjective_tired',
      };

  String get label => switch (this) {
        DailyCheckInSource.prefilled => '预填确认',
        DailyCheckInSource.subjectiveTired => '主观偏累',
      };
}

DailyCheckInSource dailyCheckInSourceFromJson(String? value) {
  return value == 'subjective_tired'
      ? DailyCheckInSource.subjectiveTired
      : DailyCheckInSource.prefilled;
}

enum DailyContinuityKind {
  standard,
  plannedRest,
  safetyPause,
}

extension DailyContinuityKindJson on DailyContinuityKind {
  String get jsonValue => switch (this) {
        DailyContinuityKind.standard => 'standard',
        DailyContinuityKind.plannedRest => 'planned_rest',
        DailyContinuityKind.safetyPause => 'safety_pause',
      };

  String get label => switch (this) {
        DailyContinuityKind.standard => '完成今日记录',
        DailyContinuityKind.plannedRest => '按计划恢复',
        DailyContinuityKind.safetyPause => '安全暂停',
      };

  String get description => switch (this) {
        DailyContinuityKind.standard => '完成当天身体状态确认。',
        DailyContinuityKind.plannedRest => '今天主动恢复，不伪造训练完成。',
        DailyContinuityKind.safetyPause => '因疲劳或不适暂停训练，优先保护身体。',
      };
}

DailyContinuityKind dailyContinuityKindFromJson(String? value) {
  return switch (value) {
    'planned_rest' => DailyContinuityKind.plannedRest,
    'safety_pause' => DailyContinuityKind.safetyPause,
    _ => DailyContinuityKind.standard,
  };
}

class DailyCheckInRecord {
  const DailyCheckInRecord({
    required this.id,
    required this.localDate,
    required this.confirmedAt,
    required this.source,
    this.continuityKind = DailyContinuityKind.standard,
  });

  final String id;
  final DateTime localDate;
  final DateTime confirmedAt;
  final DailyCheckInSource source;
  final DailyContinuityKind continuityKind;

  factory DailyCheckInRecord.fromJson(Map<String, dynamic> json) {
    return DailyCheckInRecord(
      id: json['id'] as String? ?? '',
      localDate: _dateOnly(
        DateTime.tryParse(json['localDate'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      ),
      confirmedAt: DateTime.tryParse(json['confirmedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: dailyCheckInSourceFromJson(json['source'] as String?),
      continuityKind:
          dailyContinuityKindFromJson(json['continuityKind'] as String?),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'localDate': _dateKey(localDate),
        'confirmedAt': confirmedAt.toIso8601String(),
        'source': source.jsonValue,
        'continuityKind': continuityKind.jsonValue,
      };
}

class CheckInStreakState {
  const CheckInStreakState({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalCheckInDays,
    required this.lastCheckInDate,
  });

  const CheckInStreakState.empty()
      : currentStreak = 0,
        longestStreak = 0,
        totalCheckInDays = 0,
        lastCheckInDate = null;

  final int currentStreak;
  final int longestStreak;
  final int totalCheckInDays;
  final DateTime? lastCheckInDate;
}

class CheckInCelebrationReceipt {
  const CheckInCelebrationReceipt({
    required this.id,
    required this.title,
    required this.achievedAt,
    this.seenAt,
  });

  final String id;
  final String title;
  final DateTime achievedAt;
  final DateTime? seenAt;

  bool get isSeen => seenAt != null;

  CheckInCelebrationReceipt copyWith({DateTime? seenAt}) {
    return CheckInCelebrationReceipt(
      id: id,
      title: title,
      achievedAt: achievedAt,
      seenAt: seenAt ?? this.seenAt,
    );
  }

  factory CheckInCelebrationReceipt.fromJson(Map<String, dynamic> json) {
    return CheckInCelebrationReceipt(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      achievedAt: DateTime.tryParse(json['achievedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      seenAt: DateTime.tryParse(json['seenAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'achievedAt': achievedAt.toIso8601String(),
        if (seenAt != null) 'seenAt': seenAt!.toIso8601String(),
      };
}

class DailyCheckInSnapshot {
  const DailyCheckInSnapshot({
    required this.records,
    required this.celebrations,
    required this.streak,
  });

  final List<DailyCheckInRecord> records;
  final List<CheckInCelebrationReceipt> celebrations;
  final CheckInStreakState streak;

  List<CheckInCelebrationReceipt> get unseenCelebrations => celebrations
      .where((CheckInCelebrationReceipt item) => !item.isSeen)
      .toList(growable: false);
}

class DailyCheckInWriteResult {
  const DailyCheckInWriteResult({
    required this.created,
    required this.snapshot,
    required this.newCelebrations,
  });

  final bool created;
  final DailyCheckInSnapshot snapshot;
  final List<CheckInCelebrationReceipt> newCelebrations;
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _dateKey(DateTime value) {
  final DateTime date = _dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
