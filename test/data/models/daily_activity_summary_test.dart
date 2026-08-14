import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_activity_summary.dart';

void main() {
  group('DailyActivitySummary', () {
    test('缺失健康字段保持为空，负数规范为零且逐字段来源独立', () {
      final DailyActivitySummary summary = DailyActivitySummary(
        athleteProfileId: 'athlete-1',
        localDate: '2026-08-01',
        timeZoneName: 'America/Los_Angeles',
        timeZoneOffsetMinutes: -420,
        steps: null,
        stepGoal: -6000,
        activeEnergyKcal: -12.5,
        activeEnergyGoalKcal: 300,
        exerciseMinutes: 18,
        exerciseGoalMinutes: null,
        standHours: 7,
        standGoalHours: 10,
        fieldSources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.healthKit,
          DailyActivityField.stepGoal: ActivityFieldSource.manualOverride,
        },
        syncedAt: DateTime.parse('2026-08-01T09:30:00-07:00'),
      );

      expect(summary.steps, isNull);
      expect(summary.stepGoal, 0);
      expect(summary.activeEnergyKcal, 0);
      expect(summary.exerciseGoalMinutes, isNull);
      expect(summary.timeZoneOffsetMinutes, -420);
      expect(
        summary.sourceFor(DailyActivityField.steps),
        ActivityFieldSource.healthKit,
      );
      expect(
        summary.sourceFor(DailyActivityField.activeEnergyKcal),
        ActivityFieldSource.unavailable,
      );
      expect(summary.syncedAt.isUtc, isTrue);
      expect(summary.syncedAt.toIso8601String(), '2026-08-01T16:30:00.000Z');
    });

    test('JSON 往返保留本地日期、时区和逐字段来源', () {
      final DailyActivitySummary original = DailyActivitySummary(
        athleteProfileId: 'athlete-2',
        localDate: '2026-08-02',
        timeZoneName: 'Asia/Shanghai',
        timeZoneOffsetMinutes: 480,
        steps: 7200,
        stepGoal: 6000,
        activeEnergyKcal: 245.5,
        activeEnergyGoalKcal: 300,
        exerciseMinutes: 32,
        exerciseGoalMinutes: 30,
        standHours: 11,
        standGoalHours: 10,
        fieldSources: const <DailyActivityField, ActivityFieldSource>{
          DailyActivityField.steps: ActivityFieldSource.healthKit,
          DailyActivityField.stepGoal: ActivityFieldSource.derivedGoal,
          DailyActivityField.activeEnergyKcal: ActivityFieldSource.healthKit,
          DailyActivityField.activeEnergyGoalKcal:
              ActivityFieldSource.manualOverride,
        },
        syncedAt: DateTime.utc(2026, 8, 2, 12, 15),
      );

      final DailyActivitySummary restored =
          DailyActivitySummary.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.localDate, '2026-08-02');
      expect(restored.timeZoneName, 'Asia/Shanghai');
      expect(restored.timeZoneOffsetMinutes, 480);
    });

    test('未知旧来源值保守降级为不可用且未知字段被忽略', () {
      final DailyActivitySummary summary = DailyActivitySummary.fromJson(
        <String, Object?>{
          'athleteProfileId': 'athlete-3',
          'localDate': '2026-08-03',
          'timeZoneName': 'UTC',
          'timeZoneOffsetMinutes': 0,
          'steps': 1200,
          'fieldSources': <String, Object?>{
            'steps': 'legacy_phone',
            'step_goal': 'derived_goal',
            'legacy_metric': 'health_kit',
          },
          'syncedAt': '2026-08-03T10:00:00.000Z',
        },
      );

      expect(
        summary.sourceFor(DailyActivityField.steps),
        ActivityFieldSource.unavailable,
      );
      expect(
        summary.sourceFor(DailyActivityField.stepGoal),
        ActivityFieldSource.derivedGoal,
      );
      expect(summary.fieldSources.length, 2);
    });
  });
}
