import '../data/models/body_data_quality.dart';
import '../data/models/body_metric.dart';

class BodyDataQualityService {
  BodyDataQualityReport buildReport(List<BodyMetric> metrics, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final today = DateTime(current.year, current.month, current.day);
    final start = DateTime(today.year, today.month, today.day - 6);
    const fields = [
      'weightKg',
      'bodyFatPercentage',
      'restingHeartRate',
      'hrvMs',
      'sleepHours',
      'fatigueLevel',
      'sorenessLevel'
    ];
    final valid = metrics
        .where((m) =>
            m.sourceVerified &&
            !m.measuredAt.isAfter(current) &&
            fields.any(m.hasValue))
        .toList()
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final recent =
        valid.where((m) => !m.measuredAt.toLocal().isBefore(start)).toList();
    String dayKey(BodyMetric m) {
      final date = m.measuredAt.toLocal();
      return '${date.year}-${date.month}-${date.day}';
    }

    final days = recent.map(dayKey).toSet().length;
    final sources = recent.map((m) => m.source).toSet().length;
    final issues = <BodyDataQualityIssue>[
      BodyDataQualityIssue(
        title: days == 7 ? '七日记录覆盖完整' : '本窗口记录不足',
        description: '观察窗口 ${_dateLabel(start)} 至 ${_dateLabel(today)}；'
            '${recent.length} 条有效记录、$days/7 个自然日。'
            '${days == 7 ? '七个自然日均有记录，日期覆盖连续；不代表每项指标完整或健康状态正常。' : '日期覆盖尚不完整；未记录的日期不补零。'}',
        severity: BodyDataQualitySeverity.info,
      ),
      if (metrics.length != recent.length)
        BodyDataQualityIssue(
          title: '历史与不可用记录仍保留',
          description: '共保存 ${metrics.length} 条；窗口外、未来、来源未确认或无有效字段的 '
              '${metrics.length - recent.length} 条记录不纳入本窗口计算。',
          severity: BodyDataQualitySeverity.info,
        ),
      if (valid.isNotEmpty) ..._missingIssues(valid.first, current),
      ..._outlierIssues(recent),
      ..._sourceIssues(sources),
    ];
    // 保留原评分系数和异常阈值，覆盖率改用七日内实际记录的不同日期。
    // 窗口与缺失依据是说明，不另加扣分规则。
    final scoredIssues = [
      if (valid.isNotEmpty) ..._missingIssues(valid.first, current),
      ..._outlierIssues(recent)
          .where((e) => e.severity != BodyDataQualitySeverity.info),
      ..._sourceIssues(sources),
    ];
    final penalty = scoredIssues.fold<double>(
        0,
        (total, issue) =>
            total +
            switch (issue.severity) {
              BodyDataQualitySeverity.info => 0.04,
              BodyDataQualitySeverity.warning => 0.12,
              BodyDataQualitySeverity.risk => 0.25,
            });
    return BodyDataQualityReport(
      recordCount: metrics.length,
      coveredDays: days,
      sourceCount: sources,
      qualityScore: days == 0
          ? 0
          : (0.35 + days / 7 * 0.65 - penalty).clamp(0.0, 1.0).toDouble(),
      coverageLabel: '近 7 个自然日：$days/7 日有有效记录',
      sourceLabel: sources == 0
          ? '本窗口无可用来源'
          : sources == 1
              ? '单一来源，不代表已验证准确性'
              : '$sources 类来源，需核对记录口径',
      revisionPolicyLabel: '同日覆盖会保留旧值、新值、来源和原因；历史记录继续可读。',
      issues: issues,
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  List<BodyDataQualityIssue> _missingIssues(BodyMetric latest, DateTime now) {
    final int daysSinceLatest = now.difference(latest.measuredAt).inDays;
    if (daysSinceLatest >= 14) {
      return const [
        BodyDataQualityIssue(
          title: '连续缺失超过 2 周',
          description: '趋势统计会跳过缺失日；旧记录不代表今日状态。',
          severity: BodyDataQualitySeverity.warning,
        )
      ];
    }
    if (daysSinceLatest >= 3) {
      return const [
        BodyDataQualityIssue(
          title: '最近几天未记录',
          description: '未记录不代表状态正常；旧记录不作为今日身体输入。',
          severity: BodyDataQualitySeverity.info,
        )
      ];
    }
    return const [];
  }

  List<BodyDataQualityIssue> _outlierIssues(List<BodyMetric> metrics) {
    // 每项指标独立选择当天最近的有效值，重复记录不能增加比较样本天数。
    List<BodyMetric> forField(String field) {
      final days = <String>{};
      return metrics
          .where((m) =>
              m.hasValue(field) && days.add(_dateLabel(m.measuredAt.toLocal())))
          .toList();
    }

    final weights = forField('weightKg');
    final heartRates = forField('restingHeartRate');
    final issues = <BodyDataQualityIssue>[];
    if (weights.length < 2) {
      issues.add(BodyDataQualityIssue(
        title: '体重变化无法比较',
        description: '本窗口有 ${weights.length} 个自然日的有效体重记录；不足两日，无法比较变化，缺值不按零处理。',
        severity: BodyDataQualitySeverity.info,
      ));
    } else {
      final change = weights[0].weightKg - weights[1].weightKg;
      if (change.abs() > 2.0) {
        issues.add(BodyDataQualityIssue(
          title: '最近两次体重变化偏大',
          description:
              '${weights[1].measuredDateLabel} 至 ${weights[0].measuredDateLabel} '
              '体重变化 ${change.toStringAsFixed(1)} kg，超过 2 kg 时建议确认单位或录入错误。',
          severity: BodyDataQualitySeverity.warning,
        ));
      }
    }
    if (heartRates.length < 2) {
      issues.add(BodyDataQualityIssue(
        title: '静息心率变化无法比较',
        description:
            '本窗口有 ${heartRates.length} 个自然日的有效静息心率记录；不足两日，无法比较变化，缺值不按零处理。',
        severity: BodyDataQualitySeverity.info,
      ));
    } else {
      final average =
          heartRates.fold<int>(0, (sum, m) => sum + m.restingHeartRate) /
              heartRates.length;
      final delta = heartRates.first.restingHeartRate - average;
      if (delta.abs() > 20) {
        issues.add(BodyDataQualityIssue(
          title: '静息心率偏离均值',
          description:
              '本窗口 ${heartRates.length} 日有效记录均值 ${average.toStringAsFixed(1)} bpm；'
              '最新静息心率偏离 ${delta.toStringAsFixed(0)} bpm，建议核对录入。',
          severity: BodyDataQualitySeverity.risk,
        ));
      }
    }
    return issues;
  }

  List<BodyDataQualityIssue> _sourceIssues(int sourceCount) {
    if (sourceCount <= 1) return const [];
    return const [
      BodyDataQualityIssue(
        title: '存在多种数据来源',
        description: '手动、文件或设备来源的口径可能不同；请核对来源标签。',
        severity: BodyDataQualitySeverity.info,
      )
    ];
  }
}
