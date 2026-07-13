import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/widgets/exercise_media.dart';
import 'package:trainflow_ai/data/models/exercise.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';

void main() {
  Exercise createExercise({required String mediaPath}) {
    return Exercise(
      id: 'exercise-media-test',
      name: '动作媒体测试',
      category: ExerciseCategory.runningDrill,
      targetMuscles: const ['核心'],
      sportTags: const [MainSport.generalFitness],
      description: '用于验证动作媒体格式。',
      steps: const ['保持稳定'],
      commonMistakes: const ['动作过快'],
      setsAndReps: '1 组',
      equipment: const ['空地'],
      mediaUrl: mediaPath,
      mediaUrls: [mediaPath],
      mediaStatus: ExerciseMediaStatus.precise,
      evidenceSources: const [],
    );
  }

  testWidgets('GIF 动作资源显示动图标识', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExerciseMedia(
            exercise: createExercise(
              mediaPath: 'assets/images/exercises/high_knees.gif',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('精确示范 · GIF 动图'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('视频路径被拒绝并显示格式提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExerciseMedia(
            exercise: createExercise(
              mediaPath: 'assets/videos/exercise-demo.mp4',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('仅支持图片或 GIF 动图'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
