import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/first_run_onboarding/domain/first_run_models.dart';

void main() {
  test('确认后的草稿可序列化且不包含原始输入', () {
    final FirstRunDraft draft = FirstRunDraft(
      stage: OnboardingStage.training,
      createdAt: DateTime.utc(2026, 7, 31),
      updatedAt: DateTime.utc(2026, 7, 31, 1),
      personal: const PersonalProfileDraft(
        nickname: '小智',
        gender: 'male',
        declaredAge: 32,
        heightCm: 175,
        weightKg: 72,
        workerProfileType: 'sedentary_office',
        workScheduleType: 'regular_office',
        trainingGoal: 'fat_loss',
        mainSports: <String>['running'],
        trainingExperienceLevel: 'beginner',
        injuries: <StructuredInjuryProfile>[],
      ),
    );

    final Map<String, Object?> json = draft.toJson();

    expect(json.toString(), isNot(contains('raw')));
    expect(FirstRunDraft.fromJson(json).personal?.nickname, '小智');
  });

  test('七天未完成的登录前草稿判定为过期', () {
    final FirstRunDraft draft = FirstRunDraft.initial(
      DateTime.utc(2026, 7, 1),
    );

    expect(
      draft.isExpiredAt(DateTime.utc(2026, 7, 8, 0, 0, 1)),
      isTrue,
    );
    expect(draft.isExpiredAt(DateTime.utc(2026, 7, 7)), isFalse);
  });

  test('未满18岁不能进入训练建档阶段', () {
    const PersonalProfileDraft profile = PersonalProfileDraft(
      nickname: '测试用户',
      gender: 'unknown',
      declaredAge: 17,
      workerProfileType: 'student',
      workScheduleType: 'regular',
      trainingGoal: 'general_fitness',
      mainSports: <String>[],
      trainingExperienceLevel: 'beginner',
      injuries: <StructuredInjuryProfile>[],
    );

    expect(profile.isAdult, isFalse);
  });
}
