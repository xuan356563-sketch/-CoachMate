import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/core/widgets/flow_mascot.dart';
import 'package:trainflow_ai/core/widgets/trainmate_action_character.dart';
import 'package:trainflow_ai/core/widgets/trainflow_widgets.dart';
import 'package:trainflow_ai/data/models/motion_check.dart';
import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/exercise_library/exercise_list_page.dart';
import 'package:trainflow_ai/features/profile/profile_page.dart';
import 'package:trainflow_ai/features/race_prep/race_prep_page.dart';
import 'package:trainflow_ai/features/training_plan/plan_list_page.dart';

void main() {
  test('五个导航默认状态映射到固定业务动作', () {
    final List<FlowMascotSpec> specs = <FlowMascotSpec>[
      selectTodayMascotSpec(
        profileCompleted: true,
        decisionType: TrainingDecisionType.normal,
        shouldDeloadTraining: false,
        isSynchronizing: false,
        completedTaskCount: 0,
        totalTaskCount: 3,
      ),
      selectPlanMascotSpec(
        hasPlans: true,
        hasAvailability: false,
        hasScheduledWorkouts: false,
        hasProposedAdjustment: false,
        hasConfirmedAdjustment: false,
      ),
      selectExerciseMascotSpec(
        hasExercises: true,
        riskLevel: null,
      ),
      selectRaceMascotSpec(
        isRecognizing: false,
        hasRaces: false,
        hasActiveOfficialResult: false,
        phase: null,
        needsRecovery: false,
      ),
      selectProfileMascotSpec(
        profileCompleted: true,
        isHealthSyncing: false,
        requiresMedicalAttention: false,
        readinessScore: 80,
      ),
    ];

    expect(
      specs
          .map((FlowMascotSpec spec) =>
              trainMateActionForFlowMascot(spec.action))
          .toList(),
      <TrainMateAction>[
        TrainMateAction.running,
        TrainMateAction.seatedMeditation,
        TrainMateAction.sideLungeStretch,
        TrainMateAction.sprint,
        TrainMateAction.seatedMeditation,
      ],
    );
  });

  test('今日状态在引导、恢复、同步和完成之间切换角色', () {
    FlowMascotSpec build({
      bool profileCompleted = true,
      TrainingDecisionType decisionType = TrainingDecisionType.normal,
      bool shouldDeloadTraining = false,
      bool isSynchronizing = false,
      int completedTaskCount = 0,
      int totalTaskCount = 3,
    }) =>
        selectTodayMascotSpec(
          profileCompleted: profileCompleted,
          decisionType: decisionType,
          shouldDeloadTraining: shouldDeloadTraining,
          isSynchronizing: isSynchronizing,
          completedTaskCount: completedTaskCount,
          totalTaskCount: totalTaskCount,
        );

    expect(build(profileCompleted: false).action, FlowMascotAction.beckon);
    expect(
      build(decisionType: TrainingDecisionType.recovery).action,
      FlowMascotAction.meditate,
    );
    expect(build(isSynchronizing: true).action, FlowMascotAction.scan);
    expect(
      build(completedTaskCount: 3).action,
      FlowMascotAction.celebrate,
    );
    expect(build().expression, FlowMascotExpression.wink);
  });

  test('训练计划能区分思考日历、指向建议和点头确认', () {
    FlowMascotSpec build({
      bool hasPlans = true,
      bool hasAvailability = false,
      bool hasScheduledWorkouts = false,
      bool hasProposedAdjustment = false,
      bool hasConfirmedAdjustment = false,
    }) =>
        selectPlanMascotSpec(
          hasPlans: hasPlans,
          hasAvailability: hasAvailability,
          hasScheduledWorkouts: hasScheduledWorkouts,
          hasProposedAdjustment: hasProposedAdjustment,
          hasConfirmedAdjustment: hasConfirmedAdjustment,
        );

    expect(build().action, FlowMascotAction.thinkCalendar);
    expect(
      build(hasProposedAdjustment: true).action,
      FlowMascotAction.pointSuggestion,
    );
    expect(
      build(hasConfirmedAdjustment: true).action,
      FlowMascotAction.nodCheck,
    );
    expect(
      build(hasAvailability: true, hasScheduledWorkouts: true).action,
      FlowMascotAction.nodCheck,
    );
  });

  test('动作库按空态和风险等级切换搜索、拉伸、点赞与纠错', () {
    expect(
      selectExerciseMascotSpec(hasExercises: false, riskLevel: null).action,
      FlowMascotAction.search,
    );
    expect(
      selectExerciseMascotSpec(hasExercises: true, riskLevel: null).action,
      FlowMascotAction.stretch,
    );
    expect(
      selectExerciseMascotSpec(hasExercises: true, riskLevel: null).expression,
      FlowMascotExpression.smile,
    );
    expect(
      selectExerciseMascotSpec(
        hasExercises: true,
        riskLevel: MotionRiskLevel.low,
      ).action,
      FlowMascotAction.thumbsUp,
    );
    expect(
      selectExerciseMascotSpec(
        hasExercises: true,
        riskLevel: MotionRiskLevel.high,
      ).expression,
      FlowMascotExpression.concerned,
    );
  });

  test('比赛备战按识别、成绩、减量和比赛周切换动作', () {
    expect(
      selectRaceMascotSpec(
        isRecognizing: true,
        hasRaces: true,
        hasActiveOfficialResult: false,
        phase: RacePhaseType.build,
        needsRecovery: false,
      ).action,
      FlowMascotAction.scan,
    );
    expect(
      selectRaceMascotSpec(
        isRecognizing: false,
        hasRaces: true,
        hasActiveOfficialResult: true,
        phase: RacePhaseType.raceWeek,
        needsRecovery: false,
      ).action,
      FlowMascotAction.celebrate,
    );
    expect(
      selectRaceMascotSpec(
        isRecognizing: false,
        hasRaces: true,
        hasActiveOfficialResult: false,
        phase: RacePhaseType.taper,
        needsRecovery: false,
      ).action,
      FlowMascotAction.meditate,
    );
    final FlowMascotSpec raceWeek = selectRaceMascotSpec(
      isRecognizing: false,
      hasRaces: true,
      hasActiveOfficialResult: false,
      phase: RacePhaseType.raceWeek,
      needsRecovery: false,
    );
    final FlowMascotSpec buildWeek = selectRaceMascotSpec(
      isRecognizing: false,
      hasRaces: true,
      hasActiveOfficialResult: false,
      phase: RacePhaseType.build,
      needsRecovery: false,
    );
    expect(raceWeek.action, FlowMascotAction.sprint);
    expect(raceWeek.durationMilliseconds, 300);
    expect(raceWeek.motionCycles, 2);
    expect(buildWeek.durationMilliseconds, greaterThan(300));
    expect(
      selectRaceMascotSpec(
        isRecognizing: false,
        hasRaces: true,
        hasActiveOfficialResult: false,
        phase: RacePhaseType.raceWeek,
        needsRecovery: false,
      ).action,
      FlowMascotAction.sprint,
    );
  });

  test('我的页面按档案、健康同步和恢复状态切换动作', () {
    expect(
      selectProfileMascotSpec(
        profileCompleted: false,
        isHealthSyncing: false,
        requiresMedicalAttention: false,
        readinessScore: 80,
      ).action,
      FlowMascotAction.beckon,
    );
    expect(
      selectProfileMascotSpec(
        profileCompleted: true,
        isHealthSyncing: true,
        requiresMedicalAttention: false,
        readinessScore: 80,
      ).action,
      FlowMascotAction.listen,
    );
    expect(
      selectProfileMascotSpec(
        profileCompleted: true,
        isHealthSyncing: false,
        requiresMedicalAttention: true,
        readinessScore: 80,
      ).action,
      FlowMascotAction.recover,
    );
  });

  testWidgets('五个页面状态变化会更新可识别的角色动作键', (tester) async {
    final List<FlowMascotSpec> initial = <FlowMascotSpec>[
      selectTodayMascotSpec(
        profileCompleted: true,
        decisionType: TrainingDecisionType.normal,
        shouldDeloadTraining: false,
        isSynchronizing: false,
        completedTaskCount: 0,
        totalTaskCount: 3,
      ),
      selectPlanMascotSpec(
        hasPlans: true,
        hasAvailability: false,
        hasScheduledWorkouts: false,
        hasProposedAdjustment: false,
        hasConfirmedAdjustment: false,
      ),
      selectExerciseMascotSpec(hasExercises: true, riskLevel: null),
      selectRaceMascotSpec(
        isRecognizing: false,
        hasRaces: false,
        hasActiveOfficialResult: false,
        phase: null,
        needsRecovery: false,
      ),
      selectProfileMascotSpec(
        profileCompleted: true,
        isHealthSyncing: false,
        requiresMedicalAttention: false,
        readinessScore: 80,
      ),
    ];
    final List<FlowMascotSpec> updated = <FlowMascotSpec>[
      selectTodayMascotSpec(
        profileCompleted: true,
        decisionType: TrainingDecisionType.normal,
        shouldDeloadTraining: false,
        isSynchronizing: false,
        completedTaskCount: 3,
        totalTaskCount: 3,
      ),
      selectPlanMascotSpec(
        hasPlans: true,
        hasAvailability: true,
        hasScheduledWorkouts: true,
        hasProposedAdjustment: false,
        hasConfirmedAdjustment: false,
      ),
      selectExerciseMascotSpec(
        hasExercises: true,
        riskLevel: MotionRiskLevel.high,
      ),
      selectRaceMascotSpec(
        isRecognizing: false,
        hasRaces: true,
        hasActiveOfficialResult: false,
        phase: RacePhaseType.raceWeek,
        needsRecovery: false,
      ),
      selectProfileMascotSpec(
        profileCompleted: true,
        isHealthSyncing: true,
        requiresMedicalAttention: false,
        readinessScore: 80,
      ),
    ];

    await tester.pumpWidget(_MascotGallery(specs: initial));
    for (final FlowMascotSpec spec in initial) {
      expect(_findMascotKey(spec), findsWidgets);
    }

    await tester.pumpWidget(_MascotGallery(specs: updated));
    for (final FlowMascotSpec spec in updated) {
      expect(_findMascotKey(spec), findsWidgets);
    }
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('393×852 五个页头逐页显示对应角色且有限动画不溢出', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<({String title, FlowMascotSpec spec})> pages =
        <({String title, FlowMascotSpec spec})>[
      (
        title: '今日成长',
        spec: selectTodayMascotSpec(
          profileCompleted: true,
          decisionType: TrainingDecisionType.normal,
          shouldDeloadTraining: false,
          isSynchronizing: false,
          completedTaskCount: 0,
          totalTaskCount: 3,
        ),
      ),
      (
        title: '训练计划',
        spec: selectPlanMascotSpec(
          hasPlans: true,
          hasAvailability: false,
          hasScheduledWorkouts: false,
          hasProposedAdjustment: false,
          hasConfirmedAdjustment: false,
        ),
      ),
      (
        title: '动作库',
        spec: selectExerciseMascotSpec(hasExercises: true, riskLevel: null),
      ),
      (
        title: '比赛备战',
        spec: selectRaceMascotSpec(
          isRecognizing: false,
          hasRaces: false,
          hasActiveOfficialResult: false,
          phase: null,
          needsRecovery: false,
        ),
      ),
      (
        title: '我的',
        spec: selectProfileMascotSpec(
          profileCompleted: true,
          isHealthSyncing: false,
          requiresMedicalAttention: false,
          readinessScore: 80,
        ),
      ),
    ];

    for (final ({String title, FlowMascotSpec spec}) page in pages) {
      await tester.pumpWidget(
        MaterialApp(
          theme: TDesignTheme.lightTheme,
          home: Scaffold(
            body: TrainFlowPage(
              title: page.title,
              subtitle: '角色页头验收',
              artwork: FloatingFlowMascot(size: 96, spec: page.spec),
              children: const <Widget>[
                TrainFlowCard(child: Text('页面内容')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      expect(find.text(page.title), findsOneWidget);
      expect(_findMascotKey(page.spec), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FlowMascot),
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Semantics &&
                widget.properties.label == page.spec.semanticLabel &&
                widget.properties.image == true,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

Finder _findMascotKey(FlowMascotSpec spec) => find.byKey(
      ValueKey<String>(
        'trainmate-action-'
        '${trainMateActionForFlowMascot(spec.action).name}-peachLight',
      ),
    );

class _MascotGallery extends StatelessWidget {
  const _MascotGallery({required this.specs});

  final List<FlowMascotSpec> specs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Wrap(
          children: <Widget>[
            for (final FlowMascotSpec spec in specs)
              FloatingFlowMascot(size: 56, spec: spec),
          ],
        ),
      ),
    );
  }
}
