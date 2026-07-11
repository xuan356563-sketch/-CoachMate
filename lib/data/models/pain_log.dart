enum PainTiming {
  beforeTraining,
  duringTraining,
  afterTraining,
  nextDay,
  ongoing,
}

extension PainTimingJson on PainTiming {
  String get jsonValue {
    switch (this) {
      case PainTiming.beforeTraining:
        return 'before_training';
      case PainTiming.duringTraining:
        return 'during_training';
      case PainTiming.afterTraining:
        return 'after_training';
      case PainTiming.nextDay:
        return 'next_day';
      case PainTiming.ongoing:
        return 'ongoing';
    }
  }

  String get label {
    switch (this) {
      case PainTiming.beforeTraining:
        return '训练前';
      case PainTiming.duringTraining:
        return '训练中';
      case PainTiming.afterTraining:
        return '训练后';
      case PainTiming.nextDay:
        return '次日';
      case PainTiming.ongoing:
        return '持续存在';
    }
  }
}

PainTiming painTimingFromJson(String? value) {
  switch (value) {
    case 'before_training':
      return PainTiming.beforeTraining;
    case 'during_training':
      return PainTiming.duringTraining;
    case 'after_training':
      return PainTiming.afterTraining;
    case 'next_day':
      return PainTiming.nextDay;
    case 'ongoing':
      return PainTiming.ongoing;
    default:
      return PainTiming.ongoing;
  }
}

class PainLog {
  final String id;
  final String bodyPart;
  final int painLevel;
  final PainTiming timing;
  final String note;
  final DateTime date;
  final DateTime createdAt;

  const PainLog({
    required this.id,
    required this.bodyPart,
    required this.painLevel,
    required this.timing,
    required this.note,
    required this.date,
    required this.createdAt,
  });

  int get ongoingDays {
    final DateTime today = DateTime.now();
    final DateTime start = DateTime(date.year, date.month, date.day);
    final DateTime end = DateTime(today.year, today.month, today.day);
    final int days = end.difference(start).inDays;
    return days < 0 ? 0 : days;
  }

  bool get persistsOverTwoWeeks {
    return timing == PainTiming.ongoing && ongoingDays > 14;
  }

  bool get requiresMedicalAttention {
    return painLevel >= 7 || persistsOverTwoWeeks;
  }

  bool get shouldDeloadTraining {
    return painLevel >= 4 || persistsOverTwoWeeks;
  }

  String get medicalAttentionReason {
    if (painLevel >= 7) {
      return '$bodyPart疼痛已达到 $painLevel 分';
    }
    if (persistsOverTwoWeeks) {
      return '$bodyPart疼痛已持续超过 2 周';
    }
    return '$bodyPart疼痛需要进一步评估';
  }

  factory PainLog.fromJson(Map<String, dynamic> json) {
    return PainLog(
      id: json['id'] as String? ?? '',
      bodyPart: json['bodyPart'] as String? ?? '',
      painLevel: (json['painLevel'] as num?)?.toInt() ?? 0,
      timing: painTimingFromJson(json['timing'] as String?),
      note: json['note'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bodyPart': bodyPart,
      'painLevel': painLevel,
      'timing': timing.jsonValue,
      'note': note,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
