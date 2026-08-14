import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/application/coach_turn_parser.dart';
import 'package:trainflow_ai/features/companion/domain/coach_contracts.dart';

void main() {
  const CoachTurnParser parser = CoachTurnParser();

  test('训练意图和情绪只解析为稳定枚举码', () {
    final CoachParsedTurn value = parser.parse('我有点焦虑，今天练什么？');

    expect(value.intent, CoachIntent.todayTraining);
    expect(value.emotion, CoachEmotion.anxious);
    expect(value.memoryDraft, isNull);
  });

  test('明确记住指令生成已确认候选类别但不写训练事实', () {
    final CoachMemoryDraft? draft = parser.parse('记住：我喜欢先热身').memoryDraft;

    expect(draft, isNotNull);
    expect(draft!.category, CoachMemoryCategory.preference);
    expect(draft.displayText, '我喜欢先热身');
    expect(draft.isExplicitCommand, isTrue);
  });

  test('普通偏好表达只生成待确认草稿', () {
    final CoachMemoryDraft? draft = parser.parse('我喜欢晚上训练').memoryDraft;

    expect(draft, isNotNull);
    expect(draft!.isExplicitCommand, isFalse);
  });

  for (final String sensitive in <String>[
    '记住我的膝盖疼痛七分',
    '记住我的体重是八十公斤',
    '我喜欢根据 HRV 调整训练',
    '记住我的训练目标',
  ]) {
    test('健康或训练事实不进入关系记忆：$sensitive', () {
      expect(parser.parse(sensitive).memoryDraft, isNull);
    });
  }
}
