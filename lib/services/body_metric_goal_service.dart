import '../data/models/body_metric.dart';
import '../data/models/body_metric_goal.dart';
import '../data/models/user_profile.dart';

class BodyMetricGoalService {
  BodyMetricGoalReport buildReport({
    required List<BodyMetric> bodyMetrics,
    required UserProfile profile,
  }) {
    if (bodyMetrics.isEmpty) {
      return const BodyMetricGoalReport(
        goals: [],
        summary: '还没有可用身体数据，先完成一次 10 秒快录。',
        protectionMessage: '没有数据时不做趋势判断，也不催促补录。',
      );
    }

    final List<BodyMetric> recent = bodyMetrics.take(7).toList();
    final BodyMetric latest = bodyMetrics.first;
    final BodyMetric earliest = bodyMetrics.last;
    final double averageWeight = _average(
      recent.map((BodyMetric metric) => metric.weightKg),
    );
    final double averageRestingHr = _average(
      recent.map((BodyMetric metric) => metric.restingHeartRate.toDouble()),
    );
    final double averageHrv = _average(
      recent.map((BodyMetric metric) => metric.hrvMs.toDouble()),
    );
    final double weightDropPercent = earliest.weightKg == 0
        ? 0
        : (earliest.weightKg - latest.weightKg) / earliest.weightKg;
    final bool fastWeightLoss =
        weightDropPercent > 0.015 && bodyMetrics.length >= 2;

    final List<BodyMetricGoal> goals = [
      _weightGoal(
        profile: profile,
        averageWeight: averageWeight,
        earliestWeight: earliest.weightKg,
        latestWeight: latest.weightKg,
        fastWeightLoss: fastWeightLoss,
      ),
      _restingHrGoal(averageRestingHr),
      _hrvGoal(averageHrv),
      _consistencyGoal(bodyMetrics.length),
    ];

    return BodyMetricGoalReport(
      goals: goals,
      summary:
          '已追踪 ${goals.length} 个指标目标，${goals.where((BodyMetricGoal goal) => goal.achieved).length} 个达到当前里程碑。',
      protectionMessage: fastWeightLoss
          ? '检测到体重下降速度偏快，建议放缓热量缺口，优先保住睡眠、力量和训练质量。'
          : '当前没有触发过快减重保护，继续看 7 日趋势而不是单日波动。',
    );
  }

  BodyMetricGoal _weightGoal({
    required UserProfile profile,
    required double averageWeight,
    required double earliestWeight,
    required double latestWeight,
    required bool fastWeightLoss,
  }) {
    final double targetWeight = profile.weightKg * 0.95;
    final double totalDropNeeded = (profile.weightKg - targetWeight).abs();
    final double currentDrop =
        (profile.weightKg - averageWeight).clamp(0, totalDropNeeded);
    final double progress = totalDropNeeded == 0
        ? 1
        : (currentDrop / totalDropNeeded).clamp(0.0, 1.0).toDouble();
    final double dropPercent = earliestWeight == 0
        ? 0
        : ((earliestWeight - latestWeight) / earliestWeight * 100);

    return BodyMetricGoal(
      type: BodyMetricGoalType.weight,
      title: '体重下降 5%',
      currentLabel: '${averageWeight.toStringAsFixed(1)} kg',
      targetLabel: '${targetWeight.toStringAsFixed(1)} kg',
      progress: progress,
      milestoneLabel: dropPercent > 0
          ? '已较首条记录下降 ${dropPercent.toStringAsFixed(1)}%'
          : '先建立稳定记录，不评价单日体重',
      guidance:
          fastWeightLoss ? '放缓减重速度，避免恢复和训练质量下滑。' : '继续看 7 日均值，不因单日波动调整计划。',
      achieved: progress >= 1,
      needsProtection: fastWeightLoss,
    );
  }

  BodyMetricGoal _restingHrGoal(double averageRestingHr) {
    const double start = 62;
    const double target = 57;
    final double progress = ((start - averageRestingHr) / (start - target))
        .clamp(0.0, 1.0)
        .toDouble();

    return BodyMetricGoal(
      type: BodyMetricGoalType.restingHeartRate,
      title: '静息心率下降 5',
      currentLabel: '${averageRestingHr.round()} bpm',
      targetLabel: '${target.round()} bpm',
      progress: progress,
      milestoneLabel: progress >= 1 ? '已达到心肺适应里程碑' : '持续观察晨起静息心率',
      guidance: '静息心率看趋势，短期升高时优先检查睡眠和压力。',
      achieved: progress >= 1,
      needsProtection: false,
    );
  }

  BodyMetricGoal _hrvGoal(double averageHrv) {
    const double target = 55;
    final double progress = (averageHrv / target).clamp(0.0, 1.0).toDouble();

    return BodyMetricGoal(
      type: BodyMetricGoalType.hrv,
      title: 'HRV 稳定到 55ms',
      currentLabel: '${averageHrv.round()} ms',
      targetLabel: '${target.round()} ms',
      progress: progress,
      milestoneLabel: progress >= 1 ? '恢复指标进入稳定区间' : '恢复指标仍需更多睡眠和低压日支撑',
      guidance: 'HRV 低时不要硬推强度，优先使用每日调整。',
      achieved: progress >= 1,
      needsProtection: false,
    );
  }

  BodyMetricGoal _consistencyGoal(int recordCount) {
    const int targetRecords = 14;
    final double progress =
        (recordCount / targetRecords).clamp(0.0, 1.0).toDouble();

    return BodyMetricGoal(
      type: BodyMetricGoalType.consistency,
      title: '连续数据地基',
      currentLabel: '$recordCount 条',
      targetLabel: '$targetRecords 条',
      progress: progress,
      milestoneLabel: progress >= 1 ? '已具备 2 周趋势判断基础' : '补齐到 2 周后，画像会更可信',
      guidance: '漏记不惩罚；只要继续记录，趋势判断会自动跳过缺失日。',
      achieved: progress >= 1,
      needsProtection: false,
    );
  }

  double _average(Iterable<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    double total = 0;
    int count = 0;
    for (final double value in values) {
      total += value;
      count += 1;
    }
    return total / count;
  }
}
