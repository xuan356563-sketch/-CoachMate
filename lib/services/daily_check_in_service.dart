import 'dart:convert';

import '../data/models/body_metric.dart';
import '../data/models/daily_check_in.dart';
import '../data/models/pain_log.dart';

class DailyCheckInService {
  /// 昨日按本地日历取值，不以过去 24 小时替代；最新一条缺项时不回捞旧值。
  static BodyMetric? yesterdayMetric(
      Iterable<BodyMetric> metrics, DateTime now) {
    final local = now.toLocal();
    final start = DateTime(local.year, local.month, local.day - 1);
    final end = DateTime(local.year, local.month, local.day);
    final candidates = metrics
        .where((metric) =>
            !metric.measuredAt.isBefore(start) &&
            metric.measuredAt.isBefore(end))
        .toList()
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    if (candidates.isEmpty) return null;
    final metric = candidates.first;
    return ['sleepHours', 'hrvMs', 'fatigueLevel'].every(metric.hasValue)
        ? metric
        : null;
  }

  /// 仅供本机确认前复核，包含目标日和原记录全部字段，不进入网络摘要。
  static String yesterdayFingerprint(BodyMetric metric, DateTime now) {
    final local = now.toLocal();
    return jsonEncode([local.year, local.month, local.day, metric.toJson()]);
  }

  static String yesterdayDescription(BodyMetric metric) {
    final date = metric.measuredAt.toLocal();
    String value(String field, String text) =>
        metric.hasValue(field) ? text : '未记录';
    return '沿用昨日 ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}（${metric.source.label}）\n'
        '睡眠 ${value('sleepHours', '${metric.sleepHours} 小时')} · HRV ${value('hrvMs', '${metric.hrvMs} ms')} · 疲劳 ${value('fatigueLevel', '${metric.fatigueLevel}/10')}\n'
        '体重 ${value('weightKg', '${metric.weightKg} kg')} · 体脂率 ${value('bodyFatPercentage', '${metric.bodyFatPercentage}%')}\n'
        '静息心率 ${value('restingHeartRate', '${metric.restingHeartRate} 次/分')} · 酸痛 ${value('sorenessLevel', '${metric.sorenessLevel}/10')}';
  }

  DailyCheckInSummary buildSummary({
    required BodyMetric? latestBodyMetric,
    required PainLog? latestPainLog,
    required int starterProgramStreak,
    required int highConfidenceInsightCount,
    required String readinessLabel,
    required int? readinessScore,
    required String trainingStatusLabel,
    required String reminderTimeLabel,
    BodyMetric? currentBodyMetric,
    List<BodyMetric>? bodyMetrics,
    DateTime? evaluatedAt,
  }) {
    final DateTime now = (evaluatedAt ?? DateTime.now()).toLocal();
    final BodyMetric? metric = currentBodyMetric ?? latestBodyMetric;
    bool sameDay(DateTime date) => _dateLabel(date) == _dateLabel(now);
    // 记录存在不等于当天已确认；当前展示与规则只使用当日实际字段。
    bool has(String field) =>
        metric != null &&
        !metric.measuredAt.isAfter(now) &&
        sameDay(metric.measuredAt) &&
        metric.hasValue(field);
    String sourceLabel(String field) {
      if (metric == null) return '当日未记录，需要填写';
      if (!metric.sourceVerified) return '来源未确认，不作为当日输入';
      if (metric.measuredAt.isAfter(now)) return '记录时间在未来，请核对后重新填写';
      if (!metric.hasValue(field)) return '本条未记录有效值，需要填写';
      final String origin =
          '${_dateLabel(metric.measuredAt)}（${metric.source.label}）';
      return sameDay(metric.measuredAt)
          ? '当日记录 $origin，待复核'
          : '历史记录 $origin，当日待填写';
    }

    final yesterday = yesterdayMetric(
        bodyMetrics ?? [if (latestBodyMetric != null) latestBodyMetric], now);
    final bool validPain = latestPainLog != null &&
        latestPainLog.painLevel >= 0 &&
        latestPainLog.painLevel <= 10 &&
        latestPainLog.date.millisecondsSinceEpoch > 0 &&
        !latestPainLog.date.isAfter(now) &&
        !latestPainLog.createdAt.isAfter(now);
    final String painSource = latestPainLog == null
        ? '当日疼痛待确认'
        : !validPain
            ? '疼痛记录时间或数值异常，请重新确认'
            : '${sameDay(latestPainLog.date) ? '当日记录' : '历史记录'} ${_dateLabel(latestPainLog.date)}，待复核';
    final bool hasReliableDefaults = has('sleepHours') &&
        has('hrvMs') &&
        has('fatigueLevel') &&
        readinessScore != null &&
        (starterProgramStreak >= 7 || highConfidenceInsightCount >= 2);
    final int requiredQuestionCount = hasReliableDefaults ? 2 : 5;
    final String modeLabel = hasReliableDefaults ? '精简签到' : '完整签到';
    final bool recoveryRisk = trainingStatusLabel == '过度风险' ||
        trainingStatusLabel == '恢复中' ||
        (readinessScore != null && readinessScore < 60);
    final bool fatigueRisk =
        (has('fatigueLevel') && metric!.fatigueLevel >= 5) || recoveryRisk;
    final bool sleepRisk = !has('sleepHours') ||
        (has('sleepHours') && metric!.sleepHours < 6.5) ||
        (readinessScore != null && readinessScore < 65);
    final bool hrvRisk =
        !has('hrvMs') || (has('hrvMs') && metric!.hrvMs < 48) || recoveryRisk;
    final bool painRisk = latestPainLog != null && latestPainLog.painLevel >= 4;
    final List<DailyCheckInPrompt> prompts = [
      DailyCheckInPrompt(
        label: '睡眠',
        value: !has('sleepHours')
            ? '未记录'
            : '${metric!.sleepHours.toStringAsFixed(1)} h',
        sourceLabel: sourceLabel('sleepHours'),
        required: !hasReliableDefaults || sleepRisk,
        priorityRank: sleepRisk ? 3 : 5,
        priorityReason: !has('sleepHours')
            ? '缺少当日睡眠记录，提前确认'
            : sleepRisk
                ? '睡眠或准备度偏低，提前确认'
                : '已有当日记录，仍需复核',
      ),
      DailyCheckInPrompt(
        label: 'HRV',
        value: !has('hrvMs') ? '未记录' : '${metric!.hrvMs} ms',
        sourceLabel: sourceLabel('hrvMs'),
        required: !hasReliableDefaults || hrvRisk,
        priorityRank: hrvRisk ? 3 : 5,
        priorityReason: hrvRisk ? '缺少恢复记录或存在规则提示，提前确认' : '已有记录，仍需复核',
      ),
      DailyCheckInPrompt(
        label: '疲劳',
        value: !has('fatigueLevel') ? '未记录' : '${metric!.fatigueLevel}/10',
        sourceLabel: sourceLabel('fatigueLevel'),
        required: true,
        priorityRank: fatigueRisk ? 1 : 2,
        priorityReason: fatigueRisk ? '疲劳或训练状态提示风险' : '每日决策核心输入',
      ),
      DailyCheckInPrompt(
        label: '疼痛',
        value: !validPain
            ? '未记录，请确认'
            : '${latestPainLog.bodyPart} ${latestPainLog.painLevel}/10',
        sourceLabel: painSource,
        required: true,
        priorityRank: painRisk ? 1 : 2,
        priorityReason: painRisk ? '疼痛风险优先于训练安排' : '安全红线固定前置',
      ),
      DailyCheckInPrompt(
        label: '训练时间',
        value: reminderTimeLabel,
        sourceLabel: hasReliableDefaults ? '画像预填' : '需要确认',
        required: !hasReliableDefaults,
        priorityRank: hasReliableDefaults ? 5 : 4,
        priorityReason: hasReliableDefaults ? '画像已有默认时间' : '缺少稳定默认值',
      ),
    ]..sort((DailyCheckInPrompt a, DailyCheckInPrompt b) {
        final int priorityCompare = a.priorityRank.compareTo(b.priorityRank);
        if (priorityCompare != 0) {
          return priorityCompare;
        }
        if (a.required != b.required) {
          return a.required ? -1 : 1;
        }
        return a.label.compareTo(b.label);
      });

    return DailyCheckInSummary(
      modeLabel: modeLabel,
      requiredQuestionCount: requiredQuestionCount,
      confidenceLabel: hasReliableDefaults ? '可预填' : '继续学习',
      explanation: hasReliableDefaults
          ? '当前准备度为$readinessLabel；当日已有记录可供复核，仍需确认疲劳和疼痛；记录不等于已确认今日状态。'
          : '当前准备度为$readinessLabel；当日有效输入或画像证据不足，保留睡眠、HRV、疲劳、疼痛和训练时间 5 项。',
      sortExplanation: _sortExplanation(
        prompts,
        trainingStatusLabel: trainingStatusLabel,
      ),
      canUseYesterday: yesterday != null,
      yesterdayDescription: yesterday == null
          ? '昨日无记录，或最新记录缺少有效睡眠、HRV、疲劳及可信来源；请填写今天的状态。'
          : yesterdayDescription(yesterday),
      yesterdayFingerprint:
          yesterday == null ? null : yesterdayFingerprint(yesterday, now),
      prompts: prompts,
    );
  }

  String _dateLabel(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _sortExplanation(
    List<DailyCheckInPrompt> prompts, {
    required String trainingStatusLabel,
  }) {
    final String first = prompts.first.label;
    final String second = prompts.length > 1 ? prompts[1].label : first;
    return '动态排序：$first / $second 优先；依据训练状态 $trainingStatusLabel、疼痛、疲劳和画像置信度调整。';
  }
}
