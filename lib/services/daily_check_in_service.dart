import '../data/models/body_metric.dart';
import '../data/models/daily_check_in.dart';
import '../data/models/pain_log.dart';

class DailyCheckInService {
  DailyCheckInSummary buildSummary({
    required BodyMetric? latestBodyMetric,
    required PainLog? latestPainLog,
    required int starterProgramStreak,
    required int highConfidenceInsightCount,
    required String readinessLabel,
    required int readinessScore,
    required String trainingStatusLabel,
    required String reminderTimeLabel,
  }) {
    final bool hasReliableDefaults = latestBodyMetric != null &&
        (starterProgramStreak >= 7 || highConfidenceInsightCount >= 2);
    final int requiredQuestionCount = hasReliableDefaults ? 2 : 5;
    final String modeLabel = hasReliableDefaults ? '精简签到' : '完整签到';
    final bool recoveryRisk = trainingStatusLabel == '过度风险' ||
        trainingStatusLabel == '恢复中' ||
        readinessScore < 60;
    final bool fatigueRisk =
        (latestBodyMetric?.fatigueLevel ?? 0) >= 5 || recoveryRisk;
    final bool sleepRisk = latestBodyMetric == null ||
        latestBodyMetric.sleepHours < 6.5 ||
        readinessScore < 65;
    final bool hrvRisk =
        latestBodyMetric == null || latestBodyMetric.hrvMs < 48 || recoveryRisk;
    final bool painRisk = latestPainLog != null && latestPainLog.painLevel >= 4;
    final List<DailyCheckInPrompt> prompts = [
      DailyCheckInPrompt(
        label: '睡眠',
        value: latestBodyMetric == null
            ? '待填写'
            : '${latestBodyMetric.sleepHours.toStringAsFixed(1)} h',
        sourceLabel: latestBodyMetric == null ? '需要填写' : '沿用昨日',
        required: !hasReliableDefaults || sleepRisk,
        priorityRank: sleepRisk ? 3 : 5,
        priorityReason: sleepRisk ? '睡眠或准备度偏低，提前确认' : '默认值可信，靠后复核',
      ),
      DailyCheckInPrompt(
        label: 'HRV',
        value:
            latestBodyMetric == null ? '待填写' : '${latestBodyMetric.hrvMs} ms',
        sourceLabel: latestBodyMetric == null ? '需要填写' : '沿用昨日',
        required: !hasReliableDefaults || hrvRisk,
        priorityRank: hrvRisk ? 3 : 5,
        priorityReason: hrvRisk ? '恢复信号偏弱，提前确认' : '恢复信号稳定，靠后复核',
      ),
      DailyCheckInPrompt(
        label: '疲劳',
        value: latestBodyMetric == null
            ? '待确认'
            : '${latestBodyMetric.fatigueLevel}/10',
        sourceLabel: '今天确认',
        required: true,
        priorityRank: fatigueRisk ? 1 : 2,
        priorityReason: fatigueRisk ? '疲劳或训练状态提示风险' : '每日决策核心输入',
      ),
      DailyCheckInPrompt(
        label: '疼痛',
        value: latestPainLog == null
            ? '无新疼痛'
            : '${latestPainLog.bodyPart} ${latestPainLog.painLevel}/10',
        sourceLabel: '今天确认',
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
          ? '当前准备度为$readinessLabel；系统已从身体数据、训练反馈和画像结论中找到稳定默认值，今天只确认疲劳和疼痛。'
          : '当前准备度为$readinessLabel；画像证据还不够，今天先保留睡眠、HRV、疲劳、疼痛和训练时间 5 项。',
      sortExplanation: _sortExplanation(
        prompts,
        trainingStatusLabel: trainingStatusLabel,
      ),
      canUseYesterday: latestBodyMetric != null,
      prompts: prompts,
    );
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
