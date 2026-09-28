import '../data/models/formal_ai_plan.dart';
import '../data/models/starter_graduation_report.dart';
import '../data/models/starter_program.dart';
import '../data/models/user_profile.dart';

class FormalAiPlanService {
  FormalAiPlan generatePlan({
    required StarterGraduationReport graduationReport,
    required StarterProgramGoal starterGoal,
    required UserProfile profile,
    required String trainingStatusLabel,
    required int? readinessScore,
  }) {
    final DateTime now = DateTime.now();
    final bool needsRecoveryBridge =
        trainingStatusLabel == '过度风险' || (readinessScore != null && readinessScore < 60);
    final String title = needsRecoveryBridge
        ? '恢复过渡 + ${graduationReport.recommendedNextPlan}'
        : graduationReport.recommendedNextPlan;

    return FormalAiPlan(
      id: 'formal-ai-plan-${now.millisecondsSinceEpoch}',
      generatedAt: now,
      title: title,
      goalLabel: profile.trainingGoal,
      durationLabel: '4 周正式周期',
      weeklyStructure: _weeklyStructure(
        profile: profile,
        starterGoal: starterGoal,
        needsRecoveryBridge: needsRecoveryBridge,
      ),
      progressionRule: _progressionRule(
        starterGoal: starterGoal,
        readinessScore: readinessScore,
      ),
      safetyRule: needsRecoveryBridge
          ? '第 1 周优先恢复过渡：睡眠、HRV 或疼痛未稳定前不安排高强度课。'
          : '每周只增加一个变量：训练时长、组数或动作难度三选一。',
      weeklyFocus: _weeklyFocus(
        starterGoal: starterGoal,
        needsRecoveryBridge: needsRecoveryBridge,
      ),
      decisionRules: [
        '晨间准备度低于 60：自动降级为恢复课。',
        '疼痛 >= 7：停止相关训练并提示就医。',
        'ATL 明显高于 CTL：下一课不加量，优先技术或恢复。',
        '连续 2 次反馈太轻松：下一周才小幅加量。',
      ],
    );
  }

  String _weeklyStructure({
    required UserProfile profile,
    required StarterProgramGoal starterGoal,
    required bool needsRecoveryBridge,
  }) {
    final int trainingDays = profile.weeklyTrainingDays.clamp(2, 6).toInt();
    final int minutes = profile.dailyAvailableMinutes.clamp(20, 90).toInt();
    final String emphasis = switch (starterGoal) {
      StarterProgramGoal.habit => '2 次力量基础 + 1 次低强度有氧 + 1 次灵活性',
      StarterProgramGoal.fatLoss => '2 次力量训练 + 2 次 Zone 2 有氧 + 1 次短间歇',
      StarterProgramGoal.runningIntro => '2 次轻松跑 + 1 次跑姿技术 + 1 次力量保护',
    };
    final String bridge = needsRecoveryBridge ? '首周恢复过渡，' : '';
    return '$bridge每周 $trainingDays 天，每次约 $minutes 分钟；核心结构：$emphasis。';
  }

  String _progressionRule({
    required StarterProgramGoal starterGoal,
    required int? readinessScore,
  }) {
    if (readinessScore == null) return '当前准备度无法评估，先补充并确认状态；不据此增加训练量。';
    final String target = switch (starterGoal) {
      StarterProgramGoal.habit => '先稳定出勤，再增加动作复杂度',
      StarterProgramGoal.fatLoss => '先稳定总量，再增加有氧密度',
      StarterProgramGoal.runningIntro => '先稳定轻松跑，再增加跑姿技术量',
    };
    if (readinessScore >= 80) {
      return '$target；准备度 >= 80 时每周最多增加 5-8% 总量。';
    }
    return '$target；准备度不足 80 时保持总量，只优化动作质量。';
  }

  List<String> _weeklyFocus({
    required StarterProgramGoal starterGoal,
    required bool needsRecoveryBridge,
  }) {
    final List<String> baseFocus = switch (starterGoal) {
      StarterProgramGoal.habit => const [
          '第 1 周：固定训练时间和最小动作清单',
          '第 2 周：加入基础力量主动作',
          '第 3 周：增加一次低强度有氧',
          '第 4 周：回顾完成率并生成下一周期',
        ],
      StarterProgramGoal.fatLoss => const [
          '第 1 周：建立力量 + Zone 2 组合',
          '第 2 周：稳定蛋白质和外卖照吃卡',
          '第 3 周：加入短间歇但不牺牲恢复',
          '第 4 周：用围度和体重趋势决定是否加量',
        ],
      StarterProgramGoal.runningIntro => const [
          '第 1 周：轻松跑和跑姿技术',
          '第 2 周：加入下肢力量保护',
          '第 3 周：延长一次轻松跑',
          '第 4 周：毕业测试并决定下一周期',
        ],
    };
    if (!needsRecoveryBridge) {
      return baseFocus;
    }
    return [
      '第 1 周：恢复过渡，只保留低强度和灵活性',
      ...baseFocus.skip(1),
    ];
  }
}
