import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/data/models/motion_check.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/data/models/daily_adjustment.dart';
import 'package:trainflow_ai/data/seed/seed_motion_checks.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';
import 'package:trainflow_ai/services/motion_analysis_service.dart';
import 'package:trainflow_ai/services/daily_adjustment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('云端缺失动作项不再填入 Mock 错误，计划保持不变', () {
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider
          .overrideWithValue(InMemoryLocalStorageService()),
    ]);
    addTearDown(container.dispose);
    final before = container.read(trainingMvpProvider);
    container.read(trainingMvpProvider.notifier).applyAiMotionArtifact(
          ruleId: seedMotionChecks.first.id,
          artifact: AiArtifact(
              id: 'confirmed-test',
              capability: AiCapability.motion,
              artifactType: 'motion_score_v1',
              schemaVersion: 1,
              decision: AiArtifactDecision.accepted,
              contextDigest: 'test-only',
              payload: const {
                'score': 80,
                'risk_level': 'medium',
                'confidence': 0.8
              },
              warnings: const [],
              provider: 'test',
              model: 'test',
              generatedAt: DateTime(2026, 9, 12)),
        );
    final after = container.read(trainingMvpProvider);
    expect(after.latestMotionAnalysisResult!.detectedErrors, isEmpty);
    expect(after.latestMotionAnalysisResult!.replacementActions, isEmpty);
    expect(after.latestMotionAnalysisResult!.usableForDecision, isFalse);
    expect(after.dailyAdjustmentDecision.reason,
        before.dailyAdjustmentDecision.reason);
    expect(after.plans, before.plans);
  });
  final sample = MotionAnalysisService().buildMockResult(
      rule: seedMotionChecks.first, capturedAt: DateTime(2026, 9, 12));
  DailyAdjustmentDecision decide(MotionAnalysisResult? result) =>
      DailyAdjustmentService().buildDecision(
          baseWorkout: seedTrainingPlans.first.workoutDays.first,
          availableMinutes: 60,
          workStress: WorkStressLevel.normal,
          environment: TrainingEnvironment.gym,
          weather: WeatherCondition.good,
          latestBodyMetric: null,
          latestPainLog: null,
          latestMotionAnalysisResult: result,
          readinessScore: 80);
  test('演示和未知旧记录不能改变训练建议，历史仍可读取', () {
    final legacy = sample.toJson()..remove('evidenceKind');
    final restored = MotionAnalysisResult.fromJson(legacy);
    expect(restored.score, sample.score);
    expect(restored.evidenceKind, MotionEvidenceKind.unknown);
    for (final item in [sample, restored]) {
      expect(item.usableForDecision, isFalse);
      expect(decide(item).decisionType, decide(null).decisionType);
      expect(decide(item).reason, decide(null).reason);
    }
  });
  test('完整确认结果可参与建议，空纠正与非有限置信度不能参与', () {
    final data = {
      ...sample.toJson(),
      'evidenceKind': 'confirmedCloud',
      'analysisConfidence': 0.8,
      'angleMetrics': ['用户确认的纠正说明'],
      'detectedErrors': ['观测问题'],
      'replacementActions': ['已提供的替代'],
      'suggestedImpact': 'technique'
    };
    final result = MotionAnalysisResult.fromJson(data);
    expect(result.usableForDecision, isTrue);
    expect(decide(result).decisionType, TrainingDecisionType.technique);
    for (final change in [
      {'angleMetrics': <String>[]},
      {'detectedErrors': <String>[]},
      {'analysisConfidence': double.nan},
      {'evidenceKind': 'other'}
    ]) {
      expect(
          MotionAnalysisResult.fromJson({...data, ...change}).usableForDecision,
          isFalse);
    }
  });
}
