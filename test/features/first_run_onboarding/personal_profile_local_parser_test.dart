import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/first_run_onboarding/application/personal_profile_local_parser.dart';

void main() {
  test('示例口述在本机提取成待确认字段', () {
    const PersonalProfileLocalParser parser = PersonalProfileLocalParser();

    final PersonalProfileParseResult result = parser.parse(
      '我叫小智，男，32岁，175厘米，72公斤，办公室久坐，右膝以前受过伤，想减脂并提高体能。',
    );

    expect(result.profile.nickname, '小智');
    expect(result.profile.gender, 'male');
    expect(result.profile.declaredAge, 32);
    expect(result.profile.heightCm, 175);
    expect(result.profile.weightKg, 72);
    expect(result.profile.workerProfileType, 'sedentary_office');
    expect(result.profile.trainingGoal, 'fat_loss');
    expect(result.profile.injuries.single.bodyRegion, 'right_knee');
    expect(result.rawTextRetained, isFalse);
  });

  test('解析器不推断疾病名称', () {
    const PersonalProfileLocalParser parser = PersonalProfileLocalParser();

    final PersonalProfileParseResult result = parser.parse('我30岁，膝盖不舒服');

    expect(result.profile.injuries.single.toJson().keys,
        isNot(contains('diagnosis')));
  });
}
