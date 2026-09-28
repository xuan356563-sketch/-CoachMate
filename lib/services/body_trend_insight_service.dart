import '../data/models/body_metric.dart';
import '../data/models/body_trend_insight.dart';
import '../data/models/user_profile.dart';

class BodyTrendInsightService {
  BodyTrendInsightReport buildReport({
    required List<BodyMetric> bodyMetrics,
    required UserProfile profile,
    required double acuteLoadScore,
    int windowDays = 7,
    DateTime? now,
  }) {
    if (windowDays < 1) throw ArgumentError('趋势窗口天数必须大于零。');
    final current = (now ?? DateTime.now()).toLocal();
    final start =
        DateTime(current.year, current.month, current.day - windowDays + 1);
    final candidates = bodyMetrics
        .where((m) =>
            m.sourceVerified &&
            !m.measuredAt.isAfter(current) &&
            !m.measuredAt.isBefore(start))
        .toList()
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));

    // 各字段独立按自然日取最近有效值；继承值、未知来源和缺值不参与统计。
    Map<String, BodyMetric> samples(String field) {
      final days = <String, BodyMetric>{};
      for (final metric in candidates) {
        if (metric.hasValue(field)) {
          days.putIfAbsent(
              _dateLabel(metric.measuredAt.toLocal()), () => metric);
        }
      }
      return days;
    }

    final weights = samples('weightKg');
    final heartRates = samples('restingHeartRate');
    final fatigue = samples('fatigueLevel');
    final hrv = samples('hrvMs');
    final sleep = samples('sleepHours');
    final covered = {
      ...weights.keys,
      ...heartRates.keys,
      ...fatigue.keys,
      ...hrv.keys,
      ...sleep.keys
    };
    final period = '观察窗口 ${_dateLabel(start)} 至 ${_dateLabel(current)}';
    final weightList = weights.values.toList();
    final canCompareWeight = weightList.length >= 3;
    final weightChange = canCompareWeight
        ? weightList.first.weightKg - weightList.last.weightKg
        : null;
    final sourceLabels =
        weights.values.map((m) => m.source.label).toSet().join('、');
    final weightEvidence = '$period；体重 ${weights.length} 个自然日有效记录；'
        '来源：${sourceLabels.isEmpty ? "无可用来源" : sourceLabels}。'
        '未来、窗口外、未知来源及未实际提供的字段不纳入，缺失日不补零。';
    final canCompareHeart = heartRates.length >= 3;
    final heartChange = canCompareHeart
        ? heartRates.values.first.restingHeartRate -
            heartRates.values.last.restingHeartRate
        : null;
    final milestoneFacts = <String>[
      if (weightChange != null && weightChange <= -3.5)
        '体重首末记录下降 ${weightChange.abs().toStringAsFixed(1)} kg，达到原工程变化阈值 3.5 kg',
      if (heartChange != null && heartChange <= -5)
        '静息心率首末记录下降 ${heartChange.abs()} bpm，达到原工程变化阈值 5 bpm',
    ];

    double? weeklyDrop;
    if (canCompareWeight) {
      final first = weightList.last.measuredAt.toLocal();
      final last = weightList.first.measuredAt.toLocal();
      // 使用自然日跨度，避免夏令时或记录时刻造成整日取整偏差。
      final span = DateTime.utc(last.year, last.month, last.day)
          .difference(DateTime.utc(first.year, first.month, first.day))
          .inDays;
      weeklyDrop = weightChange! < 0
          ? weightChange.abs() / weightList.last.weightKg * 100 * 7 / span
          : 0;
    }

    return BodyTrendInsightReport(
      windowLabel: '$windowDays 日 · ${covered.length} 日有记录',
      weightTrendLabel:
          weightChange == null ? '无法评估' : _weightTrendLabel(weightChange),
      weightTrendDetail:
          '$weightEvidence ${weightChange == null ? "不足 3 个自然日有效体重记录，无法评估趋势。" : "首末有效记录 ${_dateLabel(weightList.last.measuredAt.toLocal())} 至 ${_dateLabel(weightList.first.measuredAt.toLocal())}，体重变化 ${weightChange.toStringAsFixed(1)} kg；仅为本窗口记录方向，不表示变化速度或训练效果。"}',
      overlays: [
        const BodyTrendOverlay(
            title: '体重 × 训练负荷',
            description: '负荷样本依据未提供，无法评估体重与负荷的关系；单个负荷分值不代表已观测的训练变化。'),
        BodyTrendOverlay(
            title: '静息心率 × 疲劳',
            description: _pairedDescription(
                left: heartRates,
                right: fatigue,
                leftName: '静息心率',
                rightName: '疲劳',
                leftValue: (m) => m.restingHeartRate.toDouble(),
                rightValue: (m) => m.fatigueLevel.toDouble(),
                leftUnit: 'bpm',
                rightUnit: '/10',
                rule: (a, b) => a >= 64 || b >= 6,
                ruleDescription: '静息心率均值 ≥64 或疲劳均值 ≥6')),
        BodyTrendOverlay(
            title: 'HRV × 睡眠',
            description: _pairedDescription(
                left: hrv,
                right: sleep,
                leftName: 'HRV',
                rightName: '睡眠',
                leftValue: (m) => m.hrvMs.toDouble(),
                rightValue: (m) => m.sleepHours,
                leftUnit: 'ms',
                rightUnit: 'h',
                rule: (a, b) => a < 45 || b < 6.5,
                ruleDescription: 'HRV 均值 <45 或睡眠均值 <6.5')),
      ],
      milestoneLabel: milestoneFacts.isNotEmpty
          ? '记录变化提示'
          : canCompareWeight || canCompareHeart
              ? '未达到原变化阈值'
              : '无法评估',
      milestoneDetail:
          '体重 ${weights.length} 日、静息心率 ${heartRates.length} 日有效记录，各自至少 3 日才比较。'
          '${milestoneFacts.isEmpty ? "未提供可确认的里程碑。" : "${milestoneFacts.join('；')}。"}'
          '记录变化不能证明恢复、有氧能力或训练成效改善。',
      fatLossProtectionLabel: weeklyDrop == null
          ? '无法评估'
          : weeklyDrop > 1.5
              ? '触发原工程提示'
              : '未触发原工程提示',
      fatLossProtectionDetail: weeklyDrop == null
          ? '不足 3 个自然日有效体重记录，无法估算变化速度，不据此判断减脂安全。'
          : '工程估算：按首末有效记录的自然日间隔折算，每周下降约 ${weeklyDrop.toStringAsFixed(1)}%；'
              '原提示阈值为 >1.5%，短窗口折算不代表实际连续一周变化。'
              '该提示不代表健康标准或安全结论，不据此自动调整饮食或训练计划。',
    );
  }

  String _pairedDescription({
    required Map<String, BodyMetric> left,
    required Map<String, BodyMetric> right,
    required String leftName,
    required String rightName,
    required double Function(BodyMetric) leftValue,
    required double Function(BodyMetric) rightValue,
    required String leftUnit,
    required String rightUnit,
    required bool Function(double, double) rule,
    required String ruleDescription,
  }) {
    final dates = left.keys.where(right.containsKey).toList();
    final evidence =
        '$leftName ${left.length} 日、$rightName ${right.length} 日，同日配对 ${dates.length} 日。';
    if (dates.length < 3) return '$evidence 不足 3 个配对自然日，无法评估；缺值不按零或继承值计算。';
    final a =
        dates.map((day) => leftValue(left[day]!)).reduce((a, b) => a + b) /
            dates.length;
    final b =
        dates.map((day) => rightValue(right[day]!)).reduce((a, b) => a + b) /
            dates.length;
    final sources = {
      for (final day in dates) left[day]!.source.label,
      for (final day in dates) right[day]!.source.label
    }.join('、');
    return '$evidence 仅配对日期均值：$leftName ${a.toStringAsFixed(1)} $leftUnit，'
        '$rightName ${b.toStringAsFixed(1)} $rightUnit；来源：$sources。'
        '原工程规则（$ruleDescription）${rule(a, b) ? "触发" : "未触发"}。'
        '均值对照不证明相关性或今日状态，训练变化仍需当日确认与审核。';
  }

  String _weightTrendLabel(double change) => change <= -0.5
      ? '下降'
      : change >= 0.5
          ? '上升'
          : '基本稳定';

  String _dateLabel(DateTime value) => '${value.year}-'
      '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
