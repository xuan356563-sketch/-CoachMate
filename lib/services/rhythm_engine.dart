import 'dart:math' as math;

import '../data/models/body_rhythm.dart';

class RhythmConfig {
  const RhythmConfig({
    this.version = 'rhythm-v1.0.0',
    this.windowDays = 30,
    this.minimumSufficientFactors = 2,
  });

  final String version;
  final int windowDays;
  final int minimumSufficientFactors;
}

class RhythmEngine {
  const RhythmEngine({
    this.config = const RhythmConfig(),
  });

  final RhythmConfig config;

  RhythmCalculation calculate({required RhythmInput input}) {
    final Map<RhythmFactor, RhythmFactorResult> factors =
        <RhythmFactor, RhythmFactorResult>{
      RhythmFactor.sleep: _sleep(input),
      RhythmFactor.activity: _activity(input),
      RhythmFactor.training: _training(input),
      RhythmFactor.restingHeartRate: _restingHeartRate(input),
    };
    final double speed = _clamp(
      1 +
          factors.values.fold<double>(
            0,
            (double sum, RhythmFactorResult item) => sum + item.contribution,
          ),
      0.6,
      1.4,
    );
    final double? actualAge = input.birthDate == null
        ? null
        : _actualAge(input.birthDate!, input.calculatedOn);
    final int sufficientCount = factors.values
        .where((RhythmFactorResult item) => item.isSufficient)
        .length;
    final double? stateAge =
        actualAge == null || sufficientCount < config.minimumSufficientFactors
            ? null
            : _roundOne(actualAge + (speed - 1) * 20);
    return RhythmCalculation(
      speed: speed,
      actualAge: actualAge,
      stateAge: stateAge,
      factors: Map<RhythmFactor, RhythmFactorResult>.unmodifiable(factors),
      minimumSufficientFactors: config.minimumSufficientFactors,
    );
  }

  RhythmFactorResult _sleep(RhythmInput input) {
    final double? hours = input.averageSleepHours;
    final bool sufficient = hours != null && input.sleepSampleDays >= 15;
    if (!sufficient) {
      return const RhythmFactorResult(
        factor: RhythmFactor.sleep,
        contribution: 0,
        isSufficient: false,
        summary: '近 30 天有效睡眠不足 15 晚',
      );
    }
    final double contribution;
    if (hours >= 7.5) {
      contribution = -0.05;
    } else if (hours >= 7) {
      contribution = 0;
    } else if (hours >= 6.5) {
      contribution = 0.03;
    } else if (hours >= 5.5) {
      contribution = 0.05 + (6.5 - hours) * 0.05;
    } else {
      contribution = 0.10;
    }
    return RhythmFactorResult(
      factor: RhythmFactor.sleep,
      contribution: _factorClamp(contribution),
      isSufficient: true,
      summary: '近 30 天平均 ${hours.toStringAsFixed(1)} 小时'
          ' · ${input.sleepSampleDays} 晚',
    );
  }

  RhythmFactorResult _activity(RhythmInput input) {
    final double? steps = input.averageDailySteps;
    final bool sufficient = steps != null && input.activitySampleDays >= 15;
    if (!sufficient) {
      return const RhythmFactorResult(
        factor: RhythmFactor.activity,
        contribution: 0,
        isSufficient: false,
        summary: '近 30 天有效步数不足 15 天',
      );
    }
    final double contribution;
    if (steps >= 8000) {
      contribution = -0.04;
    } else if (steps >= 6000) {
      contribution = 0.02 - (steps - 6000) / 2000 * 0.04;
    } else if (steps >= 4000) {
      contribution = 0.05 - (steps - 4000) / 2000 * 0.03;
    } else {
      contribution = 0.05;
    }
    return RhythmFactorResult(
      factor: RhythmFactor.activity,
      contribution: _factorClamp(contribution),
      isSufficient: true,
      summary: '近 30 天平均 ${steps.round()} 步/天'
          ' · ${input.activitySampleDays} 天',
    );
  }

  RhythmFactorResult _training(RhythmInput input) {
    final int? days = input.trainingDays;
    final int? strengthMinutes = input.strengthMinutes;
    if (days == null || strengthMinutes == null) {
      return const RhythmFactorResult(
        factor: RhythmFactor.training,
        contribution: 0,
        isSufficient: false,
        summary: '暂时没有可用训练记录',
      );
    }
    final double weeklyDays = days / config.windowDays * 7;
    final double weeklyStrength =
        strengthMinutes / config.windowDays * 7;
    final double contribution;
    if (weeklyDays >= 3 && weeklyStrength >= 150) {
      contribution = -0.05;
    } else if (input.noTrainingDays >= 14 || days == 0) {
      contribution = 0.04;
    } else {
      contribution = 0;
    }
    return RhythmFactorResult(
      factor: RhythmFactor.training,
      contribution: contribution,
      isSufficient: true,
      summary: '近 30 天 $days 天 · $strengthMinutes 分钟力量',
    );
  }

  RhythmFactorResult _restingHeartRate(RhythmInput input) {
    final List<RhythmTimedValue> samples = input.restingHeartRateSamples;
    if (samples.length < 20) {
      return const RhythmFactorResult(
        factor: RhythmFactor.restingHeartRate,
        contribution: 0,
        isSufficient: false,
        summary: '近 30 天静息心率不足 20 天',
      );
    }
    final double meanX = samples.fold<double>(
          0,
          (double sum, RhythmTimedValue item) => sum + item.dayOffset,
        ) /
        samples.length;
    final double meanY = samples.fold<double>(
          0,
          (double sum, RhythmTimedValue item) => sum + item.value,
        ) /
        samples.length;
    double numerator = 0;
    double denominator = 0;
    for (final RhythmTimedValue sample in samples) {
      numerator += (sample.dayOffset - meanX) * (sample.value - meanY);
      denominator += math.pow(sample.dayOffset - meanX, 2).toDouble();
    }
    final double projectedChange =
        denominator == 0 ? 0 : numerator / denominator * 30;
    final double contribution = projectedChange <= -3
        ? -0.03
        : projectedChange > 3
            ? 0.05
            : 0;
    return RhythmFactorResult(
      factor: RhythmFactor.restingHeartRate,
      contribution: contribution,
      isSufficient: true,
      summary: '近 30 天趋势 '
          '${projectedChange >= 0 ? '+' : ''}${projectedChange.toStringAsFixed(1)} BPM',
    );
  }

  double _actualAge(DateTime birthDate, DateTime calculatedOn) {
    final DateTime birth =
        DateTime(birthDate.year, birthDate.month, birthDate.day);
    final DateTime target =
        DateTime(calculatedOn.year, calculatedOn.month, calculatedOn.day);
    if (birth.isAfter(target)) {
      throw const FormatException('生日不能晚于计算日期。');
    }
    return target.difference(birth).inDays / 365.2425;
  }

  double _factorClamp(double value) => _clamp(value, -0.15, 0.15);

  double _clamp(double value, double minimum, double maximum) =>
      math.max(minimum, math.min(maximum, value));

  double _roundOne(double value) => (value * 10).round() / 10;
}

class ReviewEligibilityEngine {
  const ReviewEligibilityEngine();

  ReviewUnlockStatus evaluate({required ReviewEligibilityInput input}) {
    final DateTime end = _dateOnly(input.windowEnd);
    final DateTime start = end.subtract(const Duration(days: 14));
    final List<DateTime> mealDates = _inWindow(input.mealDates, start, end);
    final List<DateTime> weightDates = _inWindow(
      input.weightDates,
      start,
      end,
      deduplicate: false,
    )..sort();
    final List<DateTime> trainingDates =
        _inWindow(input.trainingDates, start, end);
    final int span = weightDates.length < 2
        ? 0
        : weightDates.last.difference(weightDates.first).inDays;
    final List<String> gaps = <String>[];
    if (mealDates.length < 7) {
      gaps.add('还需记录 ${7 - mealDates.length} 个饮食日');
    }
    if (weightDates.length < 4) {
      gaps.add('还需记录 ${4 - weightDates.length} 次体重');
    }
    if (weightDates.length >= 2 && span < 7) {
      gaps.add('体重首末记录还需间隔至少 7 天');
    }
    if (weightDates.length < 2) {
      gaps.add('体重首末记录还需形成时间跨度');
    }
    return ReviewUnlockStatus(
      isUnlocked: gaps.isEmpty,
      dietDays: mealDates.length,
      weightRecords: weightDates.length,
      weightSpanDays: span,
      trainingDays: trainingDates.length,
      gaps: List<String>.unmodifiable(gaps),
    );
  }

  List<DateTime> _inWindow(
    List<DateTime> values,
    DateTime start,
    DateTime end, {
    bool deduplicate = true,
  }) {
    final List<DateTime> filtered = values
        .map(_dateOnly)
        .where(
          (DateTime value) => !value.isBefore(start) && !value.isAfter(end),
        )
        .toList();
    if (!deduplicate) return filtered;
    final Map<String, DateTime> unique = <String, DateTime>{
      for (final DateTime value in filtered)
        '${value.year}-${value.month}-${value.day}': value,
    };
    return unique.values.toList(growable: false);
  }

  DateTime _dateOnly(DateTime value) {
    final DateTime local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
