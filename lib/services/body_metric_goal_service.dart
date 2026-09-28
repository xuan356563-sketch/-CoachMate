import '../data/models/body_metric.dart';
import '../data/models/body_metric_goal.dart';
import '../data/models/user_profile.dart';

class BodyMetricGoalService {
  BodyMetricGoalReport buildReport({
    required List<BodyMetric> bodyMetrics,
    required UserProfile profile,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toLocal();
    final start = DateTime(current.year, current.month, current.day - 6);
    final valid = bodyMetrics
        .where((m) => m.sourceVerified && !m.measuredAt.isAfter(current))
        .toList()
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final recent = valid.where((m) => !m.measuredAt.isBefore(start)).toList();
    List<BodyMetric> samples(String field) {
      final days = <String>{};
      return recent
          .where((m) =>
              m.hasValue(field) && days.add(_dateLabel(m.measuredAt.toLocal())))
          .toList();
    }

    // 档案体重和训练目标不等于已确认的身体指标目标，保留接口但不据此自动设定。
    final goals = <BodyMetricGoal>[
      _reference(
          type: BodyMetricGoalType.weight,
          title: '体重记录',
          records: samples('weightKg'),
          value: (m) => m.weightKg,
          unit: 'kg',
          reference: '下降 5%（内置参考）',
          start: start,
          end: current),
      _reference(
          type: BodyMetricGoalType.restingHeartRate,
          title: '静息心率记录',
          records: samples('restingHeartRate'),
          value: (m) => m.restingHeartRate.toDouble(),
          unit: 'bpm',
          reference: '62 → 57 bpm（内置参考）',
          start: start,
          end: current),
      _reference(
          type: BodyMetricGoalType.hrv,
          title: 'HRV 记录',
          records: samples('hrvMs'),
          value: (m) => m.hrvMs.toDouble(),
          unit: 'ms',
          reference: '55 ms（内置参考）',
          start: start,
          end: current),
      _consistencyGoal(valid),
    ];
    return BodyMetricGoalReport(
        goals: goals,
        summary: '未设置个人身体指标目标。当前值仅汇总近 7 个自然日的有效记录；内置参考不作个人目标或健康标准。',
        protectionMessage: '变化速度及工程提示见下方趋势洞察；本卡不依据参考值调整饮食或训练计划。');
  }

  BodyMetricGoal _reference({
    required BodyMetricGoalType type,
    required String title,
    required List<BodyMetric> records,
    required double Function(BodyMetric) value,
    required String unit,
    required String reference,
    required DateTime start,
    required DateTime end,
  }) {
    final average = records.isEmpty
        ? null
        : records.map((m) => value(m) / records.length).reduce((a, b) => a + b);
    final sources = records.map((m) => m.source.label).toSet().join('、');
    return BodyMetricGoal(
        type: type,
        title: title,
        currentLabel:
            average == null ? '无有效记录' : '${average.toStringAsFixed(1)} $unit',
        targetLabel: reference,
        progress: 0,
        achieved: false,
        needsProtection: false,
        isReference: true,
        milestoneLabel: '未设置个人目标，不计算达成进度。',
        guidance:
            '观察窗口 ${_dateLabel(start)} 至 ${_dateLabel(end)}；有效覆盖 ${records.length}/7 日。'
            '来源：${sources.isEmpty ? "无可用来源" : sources}。'
            '${average == null ? "缺失值不补零或沿用继承值。" : "当前值为已记录日期的均值，不代表连续七日或今日状态。"}'
            '固定参考不能证明身体改善，未确认适用性。');
  }

  BodyMetricGoal _consistencyGoal(List<BodyMetric> valid) {
    const fields = [
      'weightKg',
      'bodyFatPercentage',
      'restingHeartRate',
      'hrvMs',
      'sleepHours',
      'fatigueLevel',
      'sorenessLevel'
    ];
    final days = valid
        .where((m) => fields.any(m.hasValue))
        .map((m) => _dateLabel(m.measuredAt.toLocal()))
        .toSet()
        .length;
    const target = 14;
    return BodyMetricGoal(
        type: BodyMetricGoalType.consistency,
        title: '累计记录日',
        currentLabel: '$days 个自然日',
        targetLabel: '$target 个不同自然日（记录习惯）',
        progress: (days / target).clamp(0.0, 1.0),
        milestoneLabel: days >= target ? '已累计至少 14 个记录日。' : '按实际记录日累计，漏记不补零。',
        guidance: '统计截至当前时刻所有有有效字段的记录日，同日只计一次。'
            '累计天数不代表连续两周，也不证明数据完整或已能判断训练效果。',
        achieved: days >= target,
        needsProtection: false);
  }

  String _dateLabel(DateTime value) => '${value.year}-'
      '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
