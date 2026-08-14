import '../data/models/monthly_summary.dart';
import '../data/models/training_metrics.dart';

/// 只基于本地结构化指标生成确定性中文叙事，不进行任何网络调用。
class GrowthNarrativeBuilder {
  const GrowthNarrativeBuilder();

  String buildWeeklyReport({
    required List<MetricAggregate> metrics,
    AcwrResult? acwr,
    AdjustmentProposal? proposal,
  }) {
    final List<MetricAggregate> sorted = List<MetricAggregate>.from(metrics)
      ..sort((MetricAggregate first, MetricAggregate second) =>
          first.metricCode.compareTo(second.metricCode));
    final List<String> lines = <String>['本周训练执行报告'];
    final MetricAggregate? consistency =
        _findMetric(sorted, 'weekly_consistency');
    if (consistency?.status == MetricStatus.ready &&
        consistency?.value != null) {
      lines.add('本周训练执行率为 ${(consistency!.value! * 100).round()}%。');
    } else if (consistency?.status == MetricStatus.accumulating) {
      lines.add('本周仍有训练项待完成或核对，执行率暂不定论。');
    } else {
      lines.add('本周暂无可计算训练计划。');
    }

    final MetricAggregate? samePaceHeartRate =
        _findMetric(sorted, 'same_pace_heart_rate');
    if (samePaceHeartRate?.status == MetricStatus.ready &&
        samePaceHeartRate?.value != null &&
        samePaceHeartRate?.baselineValue != null) {
      final double delta =
          samePaceHeartRate!.value! - samePaceHeartRate.baselineValue!;
      if (delta.abs() >= 2) {
        final String direction = delta < 0 ? '下降' : '上升';
        lines.add('同配速心率较基线$direction ${delta.abs().toStringAsFixed(0)} bpm。');
      } else {
        lines.add('同配速心率与基线差异不足 2 bpm，本周不解读为变化。');
      }
    } else if (samePaceHeartRate?.status == MetricStatus.accumulating) {
      final Object? remaining = samePaceHeartRate?.metadata['remainingSeconds'];
      lines.add(remaining is num
          ? '同配速心率仍需 ${remaining.toInt()} 秒有效稳态段。'
          : '同配速心率仍在积累有效稳态段。');
    }

    if (acwr != null) {
      lines.add('${acwr.loadStateLabel}；${acwr.reason}');
    }
    if (proposal != null &&
        proposal.status == AdjustmentProposalStatus.proposed) {
      lines.add('${proposal.explanation} 这项建议正在等待你的确认。');
    }
    return lines.join('\n');
  }

  String buildMonthlyReport({
    required List<MetricAggregate> metrics,
    SevenDayBodyAverageResult? bodyAverage,
    DeviceBestSegment? bestSegment,
    MonthlySummary? monthlySummary,
  }) {
    final List<String> lines = <String>['本月训练进步报告'];
    if (monthlySummary != null) {
      for (final MonthlyDimensionSummary dimension
          in monthlySummary.dimensions) {
        lines.add('${dimension.dimension.label}：${dimension.state.label}。');
      }
      final int readyBodyCount = monthlySummary.bodyChanges
          .where(
            (MonthlyMetricChange item) =>
                item.state != MonthlyChangeState.accumulating,
          )
          .length;
      lines.add(
        readyBodyCount == 0
            ? '身体变化仍在积累有效日，不用零值补齐。'
            : '身体变化已有 $readyBodyCount 项达到首尾窗口解释门槛。',
      );
    }
    final List<MetricAggregate> ready = metrics
        .where((MetricAggregate item) => item.status == MetricStatus.ready)
        .toList()
      ..sort((MetricAggregate first, MetricAggregate second) =>
          first.metricCode.compareTo(second.metricCode));
    if (ready.isEmpty) {
      lines.add('本月指标仍在积累，暂不生成超出数据支持的结论。');
    } else {
      lines.add('本月已有 ${ready.length} 项指标达到解释门槛。');
    }
    if (bodyAverage?.status == MetricStatus.ready &&
        bodyAverage?.average != null) {
      lines.add(
        '身体数据采用 ${bodyAverage!.validDayCount} 个有效日的日中位数计算，7 日均值为 ${bodyAverage.average!.toStringAsFixed(1)}。',
      );
    } else if (bodyAverage != null) {
      lines.add('身体数据仍需 ${bodyAverage.remainingDays} 个有效日，暂不展示趋势。');
    }
    if (bestSegment != null) {
      lines.add('${bestSegment.displayName}已记录；未经比赛确认时不作为正式 PB。');
    }
    return lines.join('\n');
  }

  MetricAggregate? _findMetric(
    List<MetricAggregate> metrics,
    String metricCode,
  ) {
    for (final MetricAggregate metric in metrics) {
      if (metric.metricCode == metricCode) return metric;
    }
    return null;
  }
}
