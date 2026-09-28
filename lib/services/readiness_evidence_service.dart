import '../data/models/body_metric.dart';
import '../data/models/pain_log.dart';
import '../data/models/user_profile.dart';

class ReadinessEvidence {
  const ReadinessEvidence(
      {required this.score,
      required this.inputs,
      required this.missing,
      required this.confirmed,
      required this.observedAt});
  final int? score;
  final List<String> inputs, missing;
  final bool confirmed;
  final DateTime? observedAt;
  String get valueLabel => score == null ? '无法评估' : '$score';
  String get explanation => [
        '工程估算，不代表临床测量',
        if (!confirmed) '尚未确认今日状态',
        if (observedAt != null) '记录时间：${observedAt!.toLocal()}',
        ...inputs,
        if (missing.isNotEmpty) '未记录：${missing.join('、')}',
      ].join('；');
}

/// 保留既有计算系数，逐项剔除未记录输入；缺少当日主观资料时不产生分数。
class ReadinessEvidenceService {
  const ReadinessEvidenceService();
  ReadinessEvidence evaluate(
      {required UserProfile profile,
      required List<BodyMetric> metrics,
      required PainLog? pain,
      required DateTime now,
      required DateTime? confirmedAt}) {
    bool today(DateTime date) =>
        date.toLocal().year == now.toLocal().year &&
        date.toLocal().month == now.toLocal().month &&
        date.toLocal().day == now.toLocal().day;
    final current = metrics
        .where((m) =>
            m.sourceVerified &&
            !m.measuredAt.isAfter(now) &&
            today(m.measuredAt))
        .toList()
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final metric = current.firstOrNull;
    final confirmed =
        confirmedAt != null && !confirmedAt.isAfter(now) && today(confirmedAt);
    const labels = {
      'sleepHours': '睡眠',
      'fatigueLevel': '疲劳',
      'hrvMs': 'HRV',
      'restingHeartRate': '静息心率'
    };
    final missing = [
      for (final item in labels.entries)
        if (!(metric?.hasValue(item.key) ?? false)) item.value
    ];
    // 展示与计算共用同一批记录，不另建基线或改变原有七日比较规则。
    final hrs = metrics.where((m) =>
        m.hasValue('restingHeartRate') && !m.measuredAt.isAfter(now) &&
        now.difference(m.measuredAt) < const Duration(days: 7)).toList();
    final averageHr = hrs.isEmpty ? null
        : hrs.fold<int>(0, (s, m) => s + m.restingHeartRate) / hrs.length;
    final inputs = <String>[
      '已确认档案：每周 ${profile.weeklyTrainingDays} 天、单次 ${profile.dailyAvailableMinutes} 分钟；${profile.workScheduleType.label}',
      '档案伤病记录 ${profile.injuryHistory.length} 项',
      pain == null ? '未有疼痛记录，不代表已排除疼痛' : '疼痛记录 ${pain.painLevel}/10，记录时间 ${pain.createdAt.toLocal()}',
      if (metric != null) '来源：${metric.source.label}',
      if (metric?.hasValue('sleepHours') ?? false)
        '睡眠 ${metric!.sleepHours} 小时',
      if (metric?.hasValue('fatigueLevel') ?? false)
        '疲劳 ${metric!.fatigueLevel}/10',
      if (metric?.hasValue('hrvMs') ?? false) 'HRV ${metric!.hrvMs} ms',
      if (metric?.hasValue('restingHeartRate') ?? false)
        '静息心率 ${metric!.restingHeartRate} 次/分',
      if ((metric?.hasValue('restingHeartRate') ?? false) && averageHr != null)
        '静息心率比较：截至 ${now.toLocal()} 的过去 7 天，${hrs.length} 条有效记录（含本次）；均值 ${averageHr.toStringAsFixed(1)} 次/分',
    ];
    int? score;
    if (confirmed &&
        metric != null &&
        metric.hasValue('sleepHours') &&
        metric.hasValue('fatigueLevel')) {
      final painPenalty = pain == null
          ? 0
          : pain.requiresMedicalAttention
              ? 36
              : pain.painLevel >= 4
                  ? 18
                  : 5;
      score = (48 +
              profile.weeklyTrainingDays * 5 +
              profile.dailyAvailableMinutes * 0.35 -
              (profile.injuryHistory.isEmpty ? 0 : 8) -
              (profile.workScheduleType == WorkScheduleType.overtimeHeavy
                  ? 8
                  : 0) -
              painPenalty -
              (metric.sleepHours < 6.5 ? 8 : 0) -
              (metric.hasValue('hrvMs') && metric.hrvMs < 45 ? 6 : 0) -
              (metric.fatigueLevel >= 7 ? 8 : 0) -
              (metric.hasValue('restingHeartRate') &&
                      averageHr != null &&
                      metric.restingHeartRate > averageHr + 6
                  ? 6
                  : 0))
          .clamp(35, 94)
          .round();
    }
    return ReadinessEvidence(
        score: score,
        inputs: inputs,
        missing: missing,
        confirmed: confirmed,
        observedAt: metric?.measuredAt);
  }
}
