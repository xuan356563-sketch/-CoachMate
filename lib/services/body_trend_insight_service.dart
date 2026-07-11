import '../data/models/body_metric.dart';
import '../data/models/body_trend_insight.dart';
import '../data/models/user_profile.dart';

class BodyTrendInsightService {
  BodyTrendInsightReport buildReport({
    required List<BodyMetric> bodyMetrics,
    required UserProfile profile,
    required double acuteLoadScore,
    int windowDays = 7,
  }) {
    if (bodyMetrics.isEmpty) {
      return const BodyTrendInsightReport(
        windowLabel: '暂无趋势窗口',
        weightTrendLabel: '等待记录',
        weightTrendDetail: '完成 3 次以上身体数据记录后，再展示趋势，不放大单日波动。',
        overlays: [
          BodyTrendOverlay(
            title: '叠加视图等待数据',
            description: '体重、静息心率、HRV、睡眠和疲劳还不足以做对照。',
          ),
        ],
        milestoneLabel: '暂无里程碑',
        milestoneDetail: '先累计稳定记录，再识别有意义变化。',
        fatLossProtectionLabel: '保守模式',
        fatLossProtectionDetail: '数据不足时不判断减脂速度，避免误导。',
      );
    }

    final List<BodyMetric> allMetrics = [...bodyMetrics]..sort(
        (BodyMetric a, BodyMetric b) => a.measuredAt.compareTo(b.measuredAt),
      );
    final DateTime latestDate = _dateOnly(allMetrics.last.measuredAt);
    final DateTime earliestAllowedDate =
        latestDate.subtract(Duration(days: windowDays - 1));
    final List<BodyMetric> sortedMetrics =
        allMetrics.where((BodyMetric metric) {
      final DateTime measuredDate = _dateOnly(metric.measuredAt);
      return !measuredDate.isBefore(earliestAllowedDate) &&
          !measuredDate.isAfter(latestDate);
    }).toList();
    if (sortedMetrics.isEmpty) {
      return BodyTrendInsightReport(
        windowLabel: '$windowDays 日窗口暂无数据',
        weightTrendLabel: '等待记录',
        weightTrendDetail: '这个趋势窗口内还没有身体数据。',
        overlays: const [
          BodyTrendOverlay(
            title: '叠加视图等待数据',
            description: '切回 7 日窗口或继续记录后再看趋势。',
          ),
        ],
        milestoneLabel: '暂无里程碑',
        milestoneDetail: '先累计稳定记录，再识别有意义变化。',
        fatLossProtectionLabel: '保守模式',
        fatLossProtectionDetail: '数据不足时不判断减脂速度，避免误导。',
      );
    }
    final BodyMetric earliest = sortedMetrics.first;
    final BodyMetric latest = sortedMetrics.last;
    final int spanDays = latest.measuredAt
        .difference(earliest.measuredAt)
        .inDays
        .clamp(1, windowDays)
        .toInt();
    final double weightChange = latest.weightKg - earliest.weightKg;
    final int restingHrChange =
        latest.restingHeartRate - earliest.restingHeartRate;
    final double averageSleep = _average(
      sortedMetrics.map((BodyMetric metric) => metric.sleepHours),
    );
    final double averageHrv = _average(
      sortedMetrics.map((BodyMetric metric) => metric.hrvMs.toDouble()),
    );
    final double averageFatigue = _average(
      sortedMetrics.map((BodyMetric metric) => metric.fatigueLevel.toDouble()),
    );
    final double averageRestingHr = _average(
      sortedMetrics
          .map((BodyMetric metric) => metric.restingHeartRate.toDouble()),
    );
    final bool fatLossGoal = profile.mainSports.contains(MainSport.fatLoss) ||
        profile.trainingGoal.contains('减脂') ||
        profile.trainingGoal.contains('减重');

    return BodyTrendInsightReport(
      windowLabel: _windowLabel(windowDays, sortedMetrics.length, spanDays),
      weightTrendLabel: _weightTrendLabel(weightChange),
      weightTrendDetail:
          '$windowDays 日窗口：从 ${earliest.measuredDateLabel} 到 ${latest.measuredDateLabel}，体重变化 ${weightChange.toStringAsFixed(1)} kg；默认看趋势，不放大单日波动。',
      overlays: [
        BodyTrendOverlay(
          title: '体重 × 训练负荷',
          description:
              '当前急性负荷 ${acuteLoadScore.round()}，体重趋势为 ${_weightTrendLabel(weightChange)}；负荷上升时不要用单日体重决定饮食。',
        ),
        BodyTrendOverlay(
          title: '静息心率 × 疲劳',
          description:
              '静息心率均值 ${averageRestingHr.round()} bpm，疲劳均值 ${averageFatigue.toStringAsFixed(1)}/10；${_restingHrFatigueAdvice(averageRestingHr, averageFatigue)}',
        ),
        BodyTrendOverlay(
          title: 'HRV × 睡眠',
          description:
              'HRV 均值 ${averageHrv.round()} ms，睡眠均值 ${averageSleep.toStringAsFixed(1)} h；${_hrvSleepAdvice(averageHrv, averageSleep)}',
        ),
      ],
      milestoneLabel: _milestoneLabel(weightChange, restingHrChange),
      milestoneDetail: _milestoneDetail(weightChange, restingHrChange),
      fatLossProtectionLabel: _fatLossProtectionLabel(
          fatLossGoal, earliest.weightKg, weightChange, spanDays),
      fatLossProtectionDetail: _fatLossProtectionDetail(
          fatLossGoal, earliest.weightKg, weightChange, spanDays),
    );
  }

  double _average(Iterable<double> values) {
    final List<double> items = values.toList();
    if (items.isEmpty) {
      return 0;
    }
    return items.reduce((double a, double b) => a + b) / items.length;
  }

  String _windowLabel(int windowDays, int recordCount, int spanDays) {
    final String prefix = '$windowDays 日窗口';
    if (recordCount >= 7 || spanDays >= windowDays - 1) {
      return '$prefix · 样本可用';
    }
    if (recordCount >= 3) {
      return '$prefix · 短期方向';
    }
    return '$prefix · 样本偏少';
  }

  String _weightTrendLabel(double weightChange) {
    if (weightChange <= -0.5) {
      return '缓慢下降';
    }
    if (weightChange >= 0.5) {
      return '缓慢上升';
    }
    return '基本稳定';
  }

  String _restingHrFatigueAdvice(double restingHr, double fatigue) {
    if (restingHr >= 64 || fatigue >= 6) {
      return '恢复压力偏高，下一课先降强度。';
    }
    return '当前压力可控，可以维持小坡度训练。';
  }

  String _hrvSleepAdvice(double hrv, double sleep) {
    if (sleep < 6.5 || hrv < 45) {
      return '恢复信号偏弱，优先补睡眠。';
    }
    return '恢复基础稳定，适合保持节奏。';
  }

  String _milestoneLabel(double weightChange, int restingHrChange) {
    if (weightChange <= -3.5 || restingHrChange <= -5) {
      return '出现积极变化';
    }
    return '继续累计里程碑';
  }

  String _milestoneDetail(double weightChange, int restingHrChange) {
    if (weightChange <= -3.5) {
      return '体重较最早记录下降 ${weightChange.abs().toStringAsFixed(1)} kg，后续可作为兑现回顾素材。';
    }
    if (restingHrChange <= -5) {
      return '静息心率较最早记录下降 ${restingHrChange.abs()} bpm，说明恢复或有氧基础可能改善。';
    }
    return '当前变化还没达到体重下降 5% 或静息心率下降 5 bpm 的里程碑，先稳定记录。';
  }

  String _fatLossProtectionLabel(
    bool fatLossGoal,
    double startWeight,
    double weightChange,
    int spanDays,
  ) {
    final double weeklyDropRate =
        _weeklyDropRate(startWeight, weightChange, spanDays);
    if (weeklyDropRate > 1.5) {
      return '减重过快';
    }
    if (fatLossGoal) {
      return '减脂速度可控';
    }
    return '健康保护开启';
  }

  String _fatLossProtectionDetail(
    bool fatLossGoal,
    double startWeight,
    double weightChange,
    int spanDays,
  ) {
    final double weeklyDropRate =
        _weeklyDropRate(startWeight, weightChange, spanDays);
    if (weeklyDropRate > 1.5) {
      return '估算每周下降 ${weeklyDropRate.toStringAsFixed(1)}%，超过 1.5% 时应放缓热量缺口并优先恢复。';
    }
    if (fatLossGoal) {
      return '当前每周下降约 ${weeklyDropRate.toStringAsFixed(1)}%，未触发过快减重保护。';
    }
    return '即使不是减脂目标，系统仍会监控每周下降比例，避免过快减重。';
  }

  double _weeklyDropRate(
      double startWeight, double weightChange, int spanDays) {
    if (startWeight <= 0 || weightChange >= 0) {
      return 0;
    }
    return (weightChange.abs() / startWeight) * 100 * 7 / spanDays;
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
