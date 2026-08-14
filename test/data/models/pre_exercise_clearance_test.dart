import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';

void main() {
  test('自主筛查记录最多有效 12 个月，且不保存问卷或答案', () {
    final PreExerciseClearance clearance = PreExerciseClearance.recorded(
      status: PreExerciseClearanceStatus.selfCleared,
      currentInjuryOrRestriction: false,
      completedAt: DateTime(2026, 7, 17, 9),
    );

    expect(clearance.validUntil, DateTime(2027, 7, 17, 9));
    expect(clearance.isValidAt(DateTime(2027, 7, 17, 9)), isTrue);
    expect(clearance.isValidAt(DateTime(2027, 7, 17, 9, 0, 1)), isFalse);
    expect(clearance.policyVersion, isNotEmpty);
    expect(clearance.toJson(), isNot(contains('questions')));
    expect(clearance.toJson(), isNot(contains('answers')));
  });

  test('医生无条件许可最多有效 6 个月，当前伤病会阻断', () {
    final PreExerciseClearance clearance = PreExerciseClearance.recorded(
      status: PreExerciseClearanceStatus.physicianUnrestricted,
      currentInjuryOrRestriction: true,
      completedAt: DateTime(2026, 7, 17),
    );

    expect(clearance.validUntil, DateTime(2027, 1, 17));
    expect(clearance.isValidAt(DateTime(2026, 7, 18)), isFalse);
    expect(
      clearance.blockingReasonAt(DateTime(2026, 7, 18)),
      contains('当前存在伤病'),
    );
  });

  test('旧策略版本和身体状况变化都会要求重新筛查', () {
    final PreExerciseClearance legacy = PreExerciseClearance.fromJson(
      <String, dynamic>{
        ...PreExerciseClearance.recorded(
          status: PreExerciseClearanceStatus.selfCleared,
          currentInjuryOrRestriction: false,
          completedAt: DateTime(2026, 7, 17),
        ).toJson(),
        'policyVersion': 'old-policy',
      },
    );
    expect(legacy.isValidAt(DateTime(2026, 7, 18)), isFalse);
    expect(legacy.blockingReasonAt(DateTime(2026, 7, 18)), contains('版本已更新'));

    final PreExerciseClearance changed = legacy.invalidateForConditionChange(
      DateTime(2026, 7, 18),
    );
    expect(changed.conditionChangedAt, isNotNull);
    expect(changed.currentInjuryOrRestriction, isTrue);
  });
}
