import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';

void main() {
  test('训练结构画像支持五维与腿部四要素往返序列化', () {
    const ExerciseTrainingProfile profile = ExerciseTrainingProfile(
      dimensions: <TrainingDimension>[
        TrainingDimension.neural,
        TrainingDimension.eccentric,
      ],
      legElements: <LegTrainingElement>[
        LegTrainingElement.eccentricLanding,
        LegTrainingElement.power,
      ],
      airborne: true,
      defaultIntent: ExecutionIntent.explosive,
    );

    final ExerciseTrainingProfile restored =
        ExerciseTrainingProfile.fromJson(profile.toJson());

    expect(restored.dimensions, profile.dimensions);
    expect(restored.legElements, profile.legElements);
    expect(restored.airborne, isTrue);
    expect(restored.defaultIntent, ExecutionIntent.explosive);
  });

  test('未知动作返回空画像而不是猜测训练属性', () {
    final ExerciseTrainingProfile profile =
        trainingProfileForExercise('exercise-unknown');

    expect(profile.dimensions, isEmpty);
    expect(profile.legElements, isEmpty);
    expect(profile.airborne, isFalse);
  });
}
