import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/onboarding/application/profile_privacy_parser.dart';

void main() {
  const ProfilePrivacyParser parser = ProfilePrivacyParser();

  test('敏感原文只在本机识别且不会进入画像请求', () {
    final ProfileLocalExtraction extraction = parser.parse(
      '我32岁，体重80kg，膝盖疼，手机号13800138000。'
      '想减脂，每周3次，每次45分钟，家里有哑铃。',
    );
    final String encoded = jsonEncode(
      extraction.toRequestJson(requestId: 'profile-local-1'),
    );

    expect(
      extraction.sensitiveFieldCodes,
      containsAll(<String>['age', 'body_metrics', 'pain_or_injury', 'contact']),
    );
    expect(extraction.knownFields['goal'], 'fat_loss');
    expect(extraction.knownFields['weekly_training_days'], 3);
    expect(extraction.knownFields['available_minutes'], 45);
    expect(extraction.knownFields['equipment_access'], <String>['dumbbell']);
    expect(encoded, isNot(contains('32岁')));
    expect(encoded, isNot(contains('80kg')));
    expect(encoded, isNot(contains('膝盖')));
    expect(encoded, isNot(contains('13800138000')));
  });

  test('明确年龄和带单位身体指标只进入本地敏感草稿', () {
    final ProfileLocalExtraction extraction = parser.parse(
      '我32岁，身高175cm，体重70.5kg，最近膝盖疼。想跑步。',
    );
    final ProfileSensitiveDraft sensitive = extraction.localSensitiveDraft;
    final String encoded = jsonEncode(
      extraction.toRequestJson(requestId: 'profile-local-sensitive'),
    );

    expect(sensitive.declaredAge, 32);
    expect(sensitive.heightCm, 175);
    expect(sensitive.weightKg, 70.5);
    expect(sensitive.painOrInjuryNote, contains('膝盖疼'));
    expect(encoded, isNot(contains('32')));
    expect(encoded, isNot(contains('175')));
    expect(encoded, isNot(contains('70.5')));
    expect(encoded, isNot(contains('膝盖疼')));
  });

  test('模糊年龄不推导生日或年龄值', () {
    final ProfileLocalExtraction extraction = parser.parse(
      '我三十多岁，想保持健康。',
    );

    expect(extraction.sensitiveFieldCodes, contains('age'));
    expect(extraction.localSensitiveDraft.declaredAge, isNull);
  });

  test('缺失训练字段生成最多五个确定性追问', () {
    final ProfileLocalExtraction extraction = parser.parse('想开始运动。');

    expect(extraction.followUpQuestions, hasLength(5));
    expect(
      extraction.followUpQuestions
          .map((ProfileFollowUpQuestion item) => item.fieldCode),
      <String>[
        'goal',
        'primary_sport',
        'experience_level',
        'weekly_training_days',
        'available_minutes',
      ],
    );
    expect(
      extraction.followUpQuestions.every(
        (ProfileFollowUpQuestion item) => item.options.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('六个必填训练字段均在本地提取时不需要云端调用', () {
    final ProfileLocalExtraction extraction = parser.parse(
      '我是跑步初学者，目标减脂，每周3天，每次45分钟，使用哑铃。',
    );

    expect(extraction.unresolvedFieldCodes, isEmpty);
    expect(extraction.requiresCloudProposal, isFalse);
  });

  test('只有脱敏后仍有歧义的短句才进入云端候选片段', () {
    final ProfileLocalExtraction extraction = parser.parse(
      '更喜欢有节奏、能长期坚持的项目。',
    );

    expect(extraction.requiresCloudProposal, isTrue);
    expect(extraction.ambiguityFragments, <String>['更喜欢有节奏、能长期坚持的项目']);
    expect(extraction.ambiguityFragments.single.length, lessThanOrEqualTo(240));
  });
}
