import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/meal_guide.dart';
import 'package:trainflow_ai/data/models/motion_check.dart';
import 'package:trainflow_ai/data/models/user_insight.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/meal_guide/application/meal_preference_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('照吃偏好控制器同步照吃卡和建议并保留跟练会话、知识和画像', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController training =
        container.read(trainingMvpProvider.notifier);
    training.startWorkoutPlayer(workoutDayId: 'workout-week1-day2');
    await training.completeWorkoutPlayerStep();
    training.setKnowledgeSearchQuery('跑步');
    training.analyzeMotionCheck(
      container.read(trainingMvpProvider).motionChecks.first.id,
    );
    training.generateWeeklyUserInsightTask();
    final TrainingMvpState before = container.read(trainingMvpProvider);
    final List<String> beforeMotionAnalysisIds = before.motionAnalysisResults
        .map((MotionAnalysisResult result) => result.id)
        .toList();
    final UserInsightTableState beforeUserInsightTableState =
        before.userInsightTableState;

    await container
        .read(mealPreferenceControllerProvider.notifier)
        .saveScenario(MealScenario.homeCooking);
    await Future<void>.delayed(Duration.zero);

    final TrainingMvpState after = container.read(trainingMvpProvider);
    expect(after.mealScenario, MealScenario.homeCooking);
    expect(after.activeMealGuide.scenario, MealScenario.homeCooking);
    expect(after.coachAdvices, contains(contains('按自炊场景执行')));
    expect(after.activeWorkoutPlayerDayId, before.activeWorkoutPlayerDayId);
    expect(after.workoutPlayerStepIndex, before.workoutPlayerStepIndex);
    expect(after.logs, before.logs);
    expect(after.knowledgeSearchQuery, before.knowledgeSearchQuery);
    expect(after.filteredKnowledgeBooks.length,
        before.filteredKnowledgeBooks.length);
    expect(
      after.motionAnalysisResults
          .map((MotionAnalysisResult result) => result.id)
          .toList(),
      beforeMotionAnalysisIds,
    );
    _expectSameMotionAnalysis(
      after.latestMotionAnalysisResult,
      before.latestMotionAnalysisResult,
    );
    _expectSameUserInsightTableState(
      after.userInsightTableState,
      beforeUserInsightTableState,
    );
  });
}

void _expectSameMotionAnalysis(
  MotionAnalysisResult? actual,
  MotionAnalysisResult? expected,
) {
  expect(actual, isNotNull);
  expect(expected, isNotNull);
  expect(actual!.id, expected!.id);
  expect(actual.sourceRuleId, expected.sourceRuleId);
  expect(actual.type, expected.type);
  expect(actual.title, expected.title);
  expect(actual.score, expected.score);
  expect(actual.riskLevel, expected.riskLevel);
  expect(actual.detectedErrors, expected.detectedErrors);
  expect(actual.involvedAreas, expected.involvedAreas);
  expect(actual.suggestedImpact, expected.suggestedImpact);
  expect(actual.replacementActions, expected.replacementActions);
  expect(actual.evidenceSources.map((source) => source.id).toList(),
      expected.evidenceSources.map((source) => source.id).toList());
}

void _expectSameUserInsightTableState(
  UserInsightTableState actual,
  UserInsightTableState expected,
) {
  expect(actual.profileSnapshot?.id, expected.profileSnapshot?.id);
  expect(actual.profileEvents.map((event) => event.id).toList(),
      expected.profileEvents.map((event) => event.id).toList());
  expect(actual.userProfiles.map((profile) => profile.id).toList(),
      expected.userProfiles.map((profile) => profile.id).toList());
  expect(actual.predictionLogs.map((log) => log.id).toList(),
      expected.predictionLogs.map((log) => log.id).toList());
  expect(actual.weeklyTasks.map((task) => task.id).toList(),
      expected.weeklyTasks.map((task) => task.id).toList());
  expect(
      actual.latestWeeklyTask?.weekLabel, expected.latestWeeklyTask?.weekLabel);
  expect(
    actual.latestWeeklyTask?.profileEventCount,
    expected.latestWeeklyTask?.profileEventCount,
  );
  expect(
    actual.latestWeeklyTask?.userProfileCount,
    expected.latestWeeklyTask?.userProfileCount,
  );
  expect(
    actual.latestWeeklyTask?.predictionLogCount,
    expected.latestWeeklyTask?.predictionLogCount,
  );
  expect(
    actual.latestWeeklyTask?.statusLabel,
    expected.latestWeeklyTask?.statusLabel,
  );
  expect(actual.totalTableRows, expected.totalTableRows);
}
