import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/constants/app_colors.dart';
import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/core/widgets/trainmate_action_character.dart';
import 'package:trainflow_ai/core/widgets/trainmate_action_mappings.dart';
import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';
import 'package:trainflow_ai/data/models/exercise.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/workout_player_step.dart';

void main() {
  test('训练类型按固定规则映射动作', () {
    expect(
      trainMateActionForTrainingType(TrainingType.easyRun),
      TrainMateAction.running,
    );
    expect(
      trainMateActionForTrainingType(TrainingType.intervalRun),
      TrainMateAction.sprint,
    );
    expect(
      trainMateActionForTrainingType(TrainingType.strength),
      TrainMateAction.dumbbellOverheadPress,
    );
    expect(
      trainMateActionForTrainingType(TrainingType.hyrox),
      TrainMateAction.mountainClimber,
    );
    expect(
      trainMateActionForTrainingType(TrainingType.mobility),
      TrainMateAction.sideLungeStretch,
    );
    expect(
      trainMateActionForTrainingType(TrainingType.rehab),
      TrainMateAction.seatedMeditation,
    );
    expect(
      trainMateActionForTrainingType(TrainingType.crossTraining),
      TrainMateAction.jumpRope,
    );
  });

  test('MATE C-08 覆盖全部动作并保留 Flow 两级回退', () {
    final Set<String> navyPaths = <String>{
      for (final TrainMateAction action in TrainMateAction.values)
        TrainMateActionAssets.path(action, TrainMateCharacterVariant.navy),
    };
    final Set<String> darkPaths = <String>{
      for (final TrainMateAction action in TrainMateAction.values)
        TrainMateActionAssets.path(
          action,
          TrainMateCharacterVariant.peachLight,
        ),
    };

    expect(navyPaths, hasLength(TrainMateAction.values.length));
    expect(darkPaths, hasLength(TrainMateAction.values.length));
    expect(
      navyPaths.every(
        (String path) => path.contains('mate-feast-bag-v2'),
      ),
      isTrue,
    );
    expect(
      darkPaths.every(
        (String path) => path.contains('mate-feast-bag-v2'),
      ),
      isTrue,
    );
    final Set<String> flowV2Paths = <String>{
      for (final TrainMateAction action in TrainMateAction.values)
        for (final TrainMateCharacterVariant variant
            in TrainMateCharacterVariant.values)
          TrainMateActionAssets.flowV2Path(action, variant),
    };
    expect(
      flowV2Paths.every(
        (String path) => path.startsWith(
          'assets/branding/flow-v2-color-detail/action-characters/',
        ),
      ),
      isTrue,
    );
    final Set<String> legacyPaths = <String>{
      for (final TrainMateAction action in TrainMateAction.values)
        for (final TrainMateCharacterVariant variant
            in TrainMateCharacterVariant.values)
          TrainMateActionAssets.legacyPath(action, variant),
    };
    expect(
      <String>{
        ...navyPaths,
        ...darkPaths,
        ...flowV2Paths,
        ...legacyPaths,
      }.every(
        (String path) => !path.contains('flow-dog-v1'),
      ),
      isTrue,
    );
    expect(
      legacyPaths.every(
        (String path) => path.startsWith('assets/branding/action-characters/'),
      ),
      isTrue,
    );
    expect(
      TrainMateActionAssets.legacyPath(
        TrainMateAction.running,
        TrainMateCharacterVariant.navy,
      ),
      'assets/branding/action-characters/navy/02-running.png',
    );
  });

  test('动作分类和器械状态按固定规则映射动作', () {
    expect(
      trainMateActionForExercise(
        _exercise(ExerciseCategory.strength, equipment: const []),
      ),
      TrainMateAction.pushUp,
    );
    expect(
      trainMateActionForExercise(
        _exercise(ExerciseCategory.strength, equipment: const ['哑铃']),
      ),
      TrainMateAction.dumbbellCurl,
    );
    expect(
      trainMateActionForExercise(_exercise(ExerciseCategory.core)),
      TrainMateAction.sitUpCrunch,
    );
    expect(
      trainMateActionForExercise(_exercise(ExerciseCategory.hyrox)),
      TrainMateAction.burpee,
    );
    expect(
      trainMateActionForExercise(_exercise(ExerciseCategory.cooldown)),
      TrainMateAction.seatedForwardFold,
    );
  });

  test('跟练阶段优先于主训练类型选择动作', () {
    expect(
      trainMateActionForWorkoutPhase(
        WorkoutPlayerPhase.dynamicStretch,
        TrainingType.strength,
      ),
      TrainMateAction.standingSideStretch,
    );
    expect(
      trainMateActionForWorkoutPhase(
        WorkoutPlayerPhase.activation,
        TrainingType.strength,
      ),
      TrainMateAction.highKnees,
    );
    expect(
      trainMateActionForWorkoutPhase(
        WorkoutPlayerPhase.main,
        TrainingType.strength,
      ),
      TrainMateAction.dumbbellOverheadPress,
    );
    expect(
      trainMateActionForWorkoutPhase(
        WorkoutPlayerPhase.cooldown,
        TrainingType.strength,
      ),
      TrainMateAction.seatedForwardFold,
    );
  });

  testWidgets('深紫页头加载浅色人物，浅色卡片加载墨兰人物', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const Scaffold(
          body: TrainFlowPage(
            title: '配色验证',
            artwork: TrainMateActionCharacter(
              action: TrainMateAction.running,
              backgroundColor: AppColors.primary,
            ),
            children: [
              TrainFlowCard(
                cornerCharacterAction: TrainMateAction.running,
                child: Text('浅色卡片'),
              ),
            ],
          ),
        ),
      ),
    );

    // 页头（深紫底）加载浅色（peachLight）；卡片（白底）加载墨兰（navy）。
    expect(
      find.byKey(const ValueKey<String>('trainmate-action-running-peachLight')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('trainmate-action-running-navy')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('trainflow-card-corner-character'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('trainflow-card-corner-character'),
        ),
        matching: find.byKey(
          const ValueKey<String>('trainmate-action-running-navy'),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('393 和 430 像素宽度下页头与角落人物不溢出', (tester) async {
    for (final double width in <double>[393, 430]) {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: const Scaffold(
            body: TrainFlowPage(
              title: '响应式人物页头',
              subtitle: '窄屏文字与人物保留安全间距',
              artwork: TrainMateActionCharacter(
                action: TrainMateAction.treePoseBalance,
                backgroundColor: AppColors.primary,
              ),
              children: [
                TrainFlowCard(
                  cornerCharacterAction: TrainMateAction.treePoseBalance,
                  child: Text('重点状态卡片不会被人物遮挡'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: '宽度 $width 不应出现溢出');
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('trainflow-mobile-canvas')),
            )
            .width,
        lessThanOrEqualTo(TrainFlowTokens.pageMaxWidth),
      );
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('波浪页头人物遵循 8pt 网格定位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TDesignTheme.lightTheme,
        home: const Scaffold(
          body: OrganicPageHeader(
            title: '网格定位验证',
            artwork: TrainMateActionCharacter(
              action: TrainMateAction.running,
              backgroundColor: AppColors.primary,
            ),
          ),
        ),
      ),
    );

    final Finder artwork = find.byKey(
      const ValueKey<String>('trainmate-action-running-peachLight'),
    );
    final Positioned positioned = tester
        .widgetList<Positioned>(
          find.ancestor(of: artwork, matching: find.byType(Positioned)),
        )
        .firstWhere((widget) => widget.right != null && widget.bottom != null);
    expect(positioned.right, 16);
    expect(positioned.bottom, 24);
  });
}

Exercise _exercise(
  ExerciseCategory category, {
  List<String> equipment = const [],
}) {
  return Exercise(
    id: category.name,
    name: category.label,
    category: category,
    targetMuscles: const [],
    sportTags: const [],
    description: '',
    steps: const [],
    commonMistakes: const [],
    setsAndReps: '',
    equipment: equipment,
    mediaUrl: null,
    evidenceSources: const [],
  );
}
