import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

class CoachMemoryDraft {
  const CoachMemoryDraft({
    required this.category,
    required this.displayText,
    required this.isExplicitCommand,
  });

  final CoachMemoryCategory category;
  final String displayText;
  final bool isExplicitCommand;
}

class CoachParsedTurn {
  const CoachParsedTurn({
    required this.intent,
    required this.emotion,
    this.memoryDraft,
  });

  final CoachIntent intent;
  final CoachEmotion emotion;
  final CoachMemoryDraft? memoryDraft;
}

/// 本地确定性解析器只输出枚举码，不生成训练事实、训练数值或医疗判断。
class CoachTurnParser {
  const CoachTurnParser();

  CoachParsedTurn parse(String input) {
    final String text = input.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(input, 'input', '伙伴消息不能为空');
    }
    final CoachIntent intent = _intent(text);
    return CoachParsedTurn(
      intent: intent,
      emotion: _emotion(text),
      memoryDraft: _memoryDraft(text),
    );
  }
}

CoachIntent _intent(String text) {
  if (_containsAny(text, const <String>['记住', '忘记', '你记得', '记忆'])) {
    return CoachIntent.manageMemory;
  }
  if (_containsAny(text, const <String>['为什么', '解释', '原因'])) {
    return CoachIntent.explainPlan;
  }
  if (_containsAny(text, const <String>['恢复', '休息', '疲劳', '累'])) {
    return CoachIntent.recovery;
  }
  if (_containsAny(text, const <String>['训练', '练什么', '今天练', '开始'])) {
    return CoachIntent.todayTraining;
  }
  if (_containsAny(text, const <String>['难受', '焦虑', '沮丧', '不开心', '陪我'])) {
    return CoachIntent.emotionalSupport;
  }
  return CoachIntent.checkIn;
}

CoachEmotion _emotion(String text) {
  if (_containsAny(text, const <String>['焦虑', '担心', '害怕'])) {
    return CoachEmotion.anxious;
  }
  if (_containsAny(text, const <String>['烦', '生气', '沮丧'])) {
    return CoachEmotion.frustrated;
  }
  if (_containsAny(text, const <String>['难受', '低落', '不开心', '没精神'])) {
    return CoachEmotion.low;
  }
  if (_containsAny(text, const <String>['开心', '不错', '完成了', '有精神'])) {
    return CoachEmotion.positive;
  }
  return CoachEmotion.neutral;
}

CoachMemoryDraft? _memoryDraft(String text) {
  if (_containsAny(text, _forbiddenMemoryTerms)) return null;
  final bool explicit = text.startsWith('记住') || text.startsWith('请记住');
  final CoachMemoryCategory? category = switch (text) {
    String value when _containsAny(value, const <String>['不想提', '别提', '不要提']) =>
      CoachMemoryCategory.boundary,
    String value
        when _containsAny(value, const <String>['对我有效', '这样有用', '管用']) =>
      CoachMemoryCategory.effectiveStrategy,
    String value when _containsAny(value, const <String>['习惯', '仪式']) =>
      CoachMemoryCategory.ritual,
    String value
        when _containsAny(value, const <String>['总是被', '很难坚持', '障碍']) =>
      CoachMemoryCategory.obstacle,
    String value when _containsAny(value, const <String>['里程碑', '第一次', '达成']) =>
      CoachMemoryCategory.milestone,
    String value
        when explicit || _containsAny(value, const <String>['喜欢', '偏好']) =>
      CoachMemoryCategory.preference,
    _ => null,
  };
  if (category == null) return null;
  final String normalized =
      text.replaceFirst(RegExp(r'^请?记住[：,:，]?\s*'), '').trim();
  if (normalized.isEmpty || normalized.length > 240) return null;
  return CoachMemoryDraft(
    category: category,
    displayText: normalized,
    isExplicitCommand: explicit,
  );
}

const List<String> _forbiddenMemoryTerms = <String>[
  '疼痛',
  '伤病',
  '诊断',
  '心率',
  'HRV',
  'hrv',
  '体重',
  '体脂',
  '睡眠',
  '恢复',
  '负荷',
  '训练目标',
  '训练计划',
];

bool _containsAny(String text, List<String> terms) =>
    terms.any((String term) => text.contains(term));
