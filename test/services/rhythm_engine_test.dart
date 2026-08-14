import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_rhythm.dart';
import 'package:trainflow_ai/services/rhythm_engine.dart';

void main() {
  group('RhythmEngine', () {
    const RhythmEngine engine = RhythmEngine();

    test('四项贡献相加并限制在 0.6 到 1.4', () {
      final RhythmCalculation result = engine.calculate(
        input: RhythmInput(
          calculatedOn: DateTime(2026, 7, 27),
          birthDate: DateTime(1994, 11, 11),
          averageSleepHours: 5.5,
          sleepSampleDays: 20,
          averageDailySteps: 3000,
          activitySampleDays: 20,
          trainingDays: 0,
          strengthMinutes: 0,
          restingHeartRateSamples: <RhythmTimedValue>[
            for (int day = 0; day < 20; day++)
              RhythmTimedValue(
                dayOffset: day * 29 / 19,
                value: 60 + day * 6 / 19,
              ),
          ],
        ),
      );

      expect(result.speed, closeTo(1.24, 0.0001));
      expect(result.sufficientFactorCount, 4);
      expect(result.stateAge, isNotNull);
      expect(result.factors[RhythmFactor.sleep]!.contribution, 0.10);
      expect(result.factors[RhythmFactor.activity]!.contribution, 0.05);
      expect(result.factors[RhythmFactor.training]!.contribution, 0.04);
      expect(
        result.factors[RhythmFactor.restingHeartRate]!.contribution,
        0.05,
      );
    });

    test('不足两项充分数据时不输出状态年龄', () {
      final RhythmCalculation result = engine.calculate(
        input: RhythmInput(
          calculatedOn: DateTime(2026, 7, 27),
          birthDate: DateTime(1994, 11, 11),
          averageSleepHours: 7.8,
          sleepSampleDays: 15,
          averageDailySteps: null,
          activitySampleDays: 0,
          trainingDays: null,
          strengthMinutes: null,
          restingHeartRateSamples: const <RhythmTimedValue>[],
        ),
      );

      expect(result.sufficientFactorCount, 1);
      expect(result.stateAge, isNull);
      expect(result.factors[RhythmFactor.activity]!.statusLabel, '暂时没影响');
    });

    test('有两项充分数据但没有生日时只输出节奏速度', () {
      final RhythmCalculation result = engine.calculate(
        input: RhythmInput(
          calculatedOn: DateTime(2026, 7, 27),
          averageSleepHours: 7.5,
          sleepSampleDays: 15,
          averageDailySteps: 8500,
          activitySampleDays: 15,
          trainingDays: null,
          strengthMinutes: null,
          restingHeartRateSamples: const <RhythmTimedValue>[],
        ),
      );

      expect(result.speed, closeTo(0.91, 0.0001));
      expect(result.stateAge, isNull);
      expect(result.hasBaseline, isTrue);
    });

    test('生日按实际天数计算并输出一位小数状态年龄', () {
      final RhythmCalculation result = engine.calculate(
        input: RhythmInput(
          calculatedOn: DateTime(2026, 7, 27),
          birthDate: DateTime(1996, 7, 27),
          averageSleepHours: 7.5,
          sleepSampleDays: 15,
          averageDailySteps: 6000,
          activitySampleDays: 15,
          trainingDays: null,
          strengthMinutes: null,
          restingHeartRateSamples: const <RhythmTimedValue>[],
        ),
      );

      expect(result.actualAge, closeTo(30, 0.01));
      expect(result.stateAge, 29.4);
    });
  });

  group('ReviewEligibilityEngine', () {
    const ReviewEligibilityEngine engine = ReviewEligibilityEngine();

    test('饮食和体重同时达到边界时解锁，训练不作为硬门槛', () {
      final ReviewUnlockStatus status = engine.evaluate(
        input: ReviewEligibilityInput(
          windowEnd: DateTime(2026, 7, 27),
          mealDates: <DateTime>[
            for (int day = 21; day <= 27; day++) DateTime(2026, 7, day),
          ],
          weightDates: <DateTime>[
            DateTime(2026, 7, 18),
            DateTime(2026, 7, 20),
            DateTime(2026, 7, 23),
            DateTime(2026, 7, 25),
          ],
          trainingDates: const <DateTime>[],
        ),
      );

      expect(status.isUnlocked, isTrue);
      expect(status.dietDays, 7);
      expect(status.weightRecords, 4);
      expect(status.weightSpanDays, 7);
      expect(status.trainingDays, 0);
      expect(status.gaps, isEmpty);
    });

    test('数量足够但体重首末跨度不足时保持锁定并返回中文缺口', () {
      final ReviewUnlockStatus status = engine.evaluate(
        input: ReviewEligibilityInput(
          windowEnd: DateTime(2026, 7, 27),
          mealDates: <DateTime>[
            for (int day = 21; day <= 27; day++) DateTime(2026, 7, day),
          ],
          weightDates: <DateTime>[
            DateTime(2026, 7, 22),
            DateTime(2026, 7, 23),
            DateTime(2026, 7, 24),
            DateTime(2026, 7, 25),
          ],
          trainingDates: const <DateTime>[],
        ),
      );

      expect(status.isUnlocked, isFalse);
      expect(status.gaps, contains('体重首末记录还需间隔至少 7 天'));
    });
  });
}
