import '../data/models/body_data_quality.dart';
import '../data/models/body_metric.dart';

class BodyDataQualityService {
  BodyDataQualityReport buildReport(List<BodyMetric> metrics) {
    if (metrics.isEmpty) {
      return const BodyDataQualityReport(
        recordCount: 0,
        coveredDays: 0,
        sourceCount: 0,
        qualityScore: 0.0,
        coverageLabel: '暂无记录',
        sourceLabel: '暂无来源',
        revisionPolicyLabel: '暂无可修订数据',
        issues: [
          BodyDataQualityIssue(
            title: '缺少身体数据',
            description: '计划、恢复和画像只能使用保守默认值；先完成一次 10 秒快录。',
            severity: BodyDataQualitySeverity.warning,
          ),
        ],
      );
    }

    final List<BodyMetric> sortedMetrics = [...metrics]
      ..sort((BodyMetric a, BodyMetric b) {
        return b.measuredAt.compareTo(a.measuredAt);
      });
    final BodyMetric latest = sortedMetrics.first;
    final BodyMetric oldest = sortedMetrics.last;
    final int coveredDays =
        latest.measuredAt.difference(oldest.measuredAt).inDays + 1;
    final int sourceCount =
        sortedMetrics.map((BodyMetric metric) => metric.source).toSet().length;
    final List<BodyDataQualityIssue> issues = [
      ..._missingIssues(latest),
      ..._outlierIssues(sortedMetrics),
      ..._sourceIssues(sourceCount),
    ];
    final double coverageScore =
        (sortedMetrics.length / 7).clamp(0.0, 1.0).toDouble();
    final double issuePenalty = issues.fold<double>(
      0,
      (double total, BodyDataQualityIssue issue) {
        return total +
            switch (issue.severity) {
              BodyDataQualitySeverity.info => 0.04,
              BodyDataQualitySeverity.warning => 0.12,
              BodyDataQualitySeverity.risk => 0.25,
            };
      },
    );

    return BodyDataQualityReport(
      recordCount: sortedMetrics.length,
      coveredDays: coveredDays,
      sourceCount: sourceCount,
      qualityScore: (0.35 + coverageScore * 0.65 - issuePenalty)
          .clamp(0.0, 1.0)
          .toDouble(),
      coverageLabel: _coverageLabel(sortedMetrics.length, coveredDays),
      sourceLabel:
          sourceCount == 1 ? '单一来源，口径一致' : '$sourceCount 类来源，需看 source',
      revisionPolicyLabel: '同日覆盖会写入本地修订留痕并持久化；正式数据库阶段仍需迁移修订表。',
      issues: issues.isEmpty
          ? const [
              BodyDataQualityIssue(
                title: '数据可用于趋势判断',
                description: '近 7 日记录连续，未发现明显体重或静息心率异常。',
                severity: BodyDataQualitySeverity.info,
              ),
            ]
          : issues,
    );
  }

  List<BodyDataQualityIssue> _missingIssues(BodyMetric latest) {
    final int daysSinceLatest =
        DateTime.now().difference(latest.measuredAt).inDays;
    if (daysSinceLatest >= 14) {
      return [
        BodyDataQualityIssue(
          title: '连续缺失超过 2 周',
          description: '趋势统计会自动跳过缺失日；这里只温和提示一次，不惩罚用户。',
          severity: BodyDataQualitySeverity.warning,
        ),
      ];
    }
    if (daysSinceLatest >= 3) {
      return [
        BodyDataQualityIssue(
          title: '最近几天未记录',
          description: '短期缺失不影响使用，但准备度会更保守。',
          severity: BodyDataQualitySeverity.info,
        ),
      ];
    }
    return const [];
  }

  List<BodyDataQualityIssue> _outlierIssues(List<BodyMetric> metrics) {
    if (metrics.length < 2) {
      return const [];
    }

    final BodyMetric latest = metrics.first;
    final BodyMetric previous = metrics[1];
    final List<BodyDataQualityIssue> issues = [];
    final double weightChange = latest.weightKg - previous.weightKg;
    if (weightChange.abs() > 2.0) {
      issues.add(
        BodyDataQualityIssue(
          title: '体重日变化偏大',
          description:
              '最近两次体重变化 ${weightChange.toStringAsFixed(1)} kg，超过 2 kg 时建议确认单位或录入错误。',
          severity: BodyDataQualitySeverity.warning,
        ),
      );
    }

    final double averageRestingHr = metrics
            .map((BodyMetric metric) => metric.restingHeartRate)
            .reduce((int a, int b) => a + b) /
        metrics.length;
    final double restingHrDelta = latest.restingHeartRate - averageRestingHr;
    if (restingHrDelta.abs() > 20) {
      issues.add(
        BodyDataQualityIssue(
          title: '静息心率偏离均值',
          description:
              '最新静息心率较均值偏离 ${restingHrDelta.toStringAsFixed(0)} bpm，建议确认是否手误或生病。',
          severity: BodyDataQualitySeverity.risk,
        ),
      );
    }

    return issues;
  }

  List<BodyDataQualityIssue> _sourceIssues(int sourceCount) {
    if (sourceCount <= 1) {
      return const [];
    }
    return [
      BodyDataQualityIssue(
        title: '存在多种数据来源',
        description: '手动、文件或设备来源的口径可能不同，趋势判断会优先看 source 标签。',
        severity: BodyDataQualitySeverity.info,
      ),
    ];
  }

  String _coverageLabel(int recordCount, int coveredDays) {
    if (recordCount >= 7 && coveredDays <= 9) {
      return '近 7 日覆盖充分';
    }
    if (recordCount >= 3) {
      return '可看短期趋势';
    }
    return '记录偏少，先保守使用';
  }
}
