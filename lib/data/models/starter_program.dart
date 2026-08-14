import 'evidence_source.dart';

enum StarterProgramGoal {
  habit,
  fatLoss,
  runningIntro,
}

extension StarterProgramGoalJson on StarterProgramGoal {
  String get jsonValue {
    switch (this) {
      case StarterProgramGoal.habit:
        return 'habit';
      case StarterProgramGoal.fatLoss:
        return 'fat_loss';
      case StarterProgramGoal.runningIntro:
        return 'running_intro';
    }
  }

  String get label {
    switch (this) {
      case StarterProgramGoal.habit:
        return '习惯建立';
      case StarterProgramGoal.fatLoss:
        return '减脂入门';
      case StarterProgramGoal.runningIntro:
        return '跑步入门';
    }
  }
}

StarterProgramGoal starterProgramGoalFromJson(String? value) {
  switch (value) {
    case 'habit':
      return StarterProgramGoal.habit;
    case 'fat_loss':
      return StarterProgramGoal.fatLoss;
    case 'running_intro':
      return StarterProgramGoal.runningIntro;
    default:
      return StarterProgramGoal.habit;
  }
}

enum StarterProgramFeedback {
  tooTired,
  justRight,
  tooEasy,
}

extension StarterProgramFeedbackLabel on StarterProgramFeedback {
  String get label {
    switch (this) {
      case StarterProgramFeedback.tooTired:
        return '太累了';
      case StarterProgramFeedback.justRight:
        return '刚好';
      case StarterProgramFeedback.tooEasy:
        return '太轻松';
    }
  }
}

class StarterProgramProgress {
  final StarterProgramGoal goal;
  final int dayIndex;
  final int streak;
  final bool rescueMode;
  final String statusMessage;

  const StarterProgramProgress({
    required this.goal,
    required this.dayIndex,
    required this.streak,
    required this.rescueMode,
    required this.statusMessage,
  });

  factory StarterProgramProgress.fromJson(Map<String, dynamic> json) {
    final int rawDayIndex = (json['dayIndex'] as num?)?.toInt() ?? 1;
    final int rawStreak = (json['streak'] as num?)?.toInt() ?? 0;
    final String rawStatusMessage =
        json['statusMessage'] as String? ?? '第 1 天目标：低到不可能失败。';
    return StarterProgramProgress(
      goal: starterProgramGoalFromJson(json['goal'] as String?),
      dayIndex: rawDayIndex.clamp(1, 30).toInt(),
      streak: rawStreak.clamp(0, 30).toInt(),
      rescueMode: json['rescueMode'] == true,
      statusMessage: _normalizeStarterProgramStatusMessage(rawStatusMessage),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'goal': goal.jsonValue,
      'dayIndex': dayIndex,
      'streak': streak,
      'rescueMode': rescueMode,
      'statusMessage': statusMessage,
    };
  }
}

String _normalizeStarterProgramStatusMessage(String message) {
  return switch (message) {
    '已记录“太累了”：明天不加量，优先保住连续性。' => '已记录“太累了”：明天不加量，恢复优先。',
    '计划已顺延：漏练不惩罚，今天仍保留当前任务。' => '计划已顺延：今天仍保留当前任务，完成后计入累计成长日。',
    '已切换 5 分钟补救版，完成后仍可保住连击。' => '已切换 5 分钟补救版，完成后计入累计成长日。',
    _ => message,
  };
}

class StarterProgramDay {
  final String id;
  final StarterProgramGoal goal;
  final int dayIndex;
  final String weekTheme;
  final String title;
  final int durationMinutes;
  final List<String> trainingSteps;
  final String mealInstruction;
  final String rescueVersion;
  final String adjustmentRule;
  final bool isGraduationTest;
  final List<EvidenceSource> evidenceSources;

  const StarterProgramDay({
    required this.id,
    required this.goal,
    required this.dayIndex,
    required this.weekTheme,
    required this.title,
    required this.durationMinutes,
    required this.trainingSteps,
    required this.mealInstruction,
    required this.rescueVersion,
    required this.adjustmentRule,
    required this.isGraduationTest,
    required this.evidenceSources,
  });

  String get dayLabel {
    return '第 $dayIndex/30 天';
  }

  factory StarterProgramDay.fromJson(Map<String, dynamic> json) {
    final List<dynamic> evidenceJson =
        json['evidenceSources'] as List<dynamic>? ?? [];
    return StarterProgramDay(
      id: json['id'] as String? ?? '',
      goal: starterProgramGoalFromJson(json['goal'] as String?),
      dayIndex: json['dayIndex'] as int? ?? 1,
      weekTheme: json['weekTheme'] as String? ?? '',
      title: json['title'] as String? ?? '',
      durationMinutes: json['durationMinutes'] as int? ?? 0,
      trainingSteps:
          List<String>.from(json['trainingSteps'] as List<dynamic>? ?? []),
      mealInstruction: json['mealInstruction'] as String? ?? '',
      rescueVersion: json['rescueVersion'] as String? ?? '',
      adjustmentRule: json['adjustmentRule'] as String? ?? '',
      isGraduationTest: json['isGraduationTest'] as bool? ?? false,
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
      'goal': goal.jsonValue,
      'dayIndex': dayIndex,
      'weekTheme': weekTheme,
      'title': title,
      'durationMinutes': durationMinutes,
      'trainingSteps': trainingSteps,
      'mealInstruction': mealInstruction,
      'rescueVersion': rescueVersion,
      'adjustmentRule': adjustmentRule,
      'isGraduationTest': isGraduationTest,
      'evidenceSources': evidenceSources
          .map((EvidenceSource source) => source.toJson())
          .toList(),
    };
  }
}
