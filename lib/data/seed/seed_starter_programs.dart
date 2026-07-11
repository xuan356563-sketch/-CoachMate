import '../models/evidence_source.dart';
import '../models/starter_program.dart';

const List<EvidenceSource> starterProgramEvidenceSources = [
  EvidenceSource(
    id: 'evidence-starter-acsm-progress',
    title: 'ACSM 新手渐进原则',
    author: 'ACSM',
    sourceType: EvidenceSourceType.paper,
    chapter: '新手训练负荷',
    pageRange: '原则摘录',
    quote: '新手阶段应采用小幅、可恢复、可持续的训练负荷推进。',
    note: '用于 30 天引导的低起点和渐进坡度。',
  ),
  EvidenceSource(
    id: 'evidence-starter-tiny-habits',
    title: 'Tiny Habits',
    author: 'BJ Fogg',
    sourceType: EvidenceSourceType.book,
    chapter: '第 2 章 行为起点',
    pageRange: 'p. 39-54',
    quote: '习惯更容易从小到几乎不会失败的行为开始。',
    note: '用于漏练不惩罚、5 分钟补救版和连击反馈。',
  ),
];

final List<StarterProgramDay> seedStarterProgramDays = [
  ..._buildGoalDays(StarterProgramGoal.habit),
  ..._buildGoalDays(StarterProgramGoal.fatLoss),
  ..._buildGoalDays(StarterProgramGoal.runningIntro),
];

List<StarterProgramDay> _buildGoalDays(StarterProgramGoal goal) {
  return [
    for (int day = 1; day <= 30; day++)
      StarterProgramDay(
        id: 'starter-${goal.jsonValue}-day-$day',
        goal: goal,
        dayIndex: day,
        weekTheme: _weekTheme(day),
        title: _titleFor(goal, day),
        durationMinutes: _durationFor(day),
        trainingSteps: _trainingStepsFor(goal, day),
        mealInstruction: _mealFor(goal, day),
        rescueVersion: '5 分钟补救版：出门快走 3 分钟 + 原地提膝 1 分钟 + 喝一杯水。',
        adjustmentRule: '签到选择“太累了”则明天不加量；“刚好”按计划推进；“太轻松”只增加 1 个最小变量。',
        isGraduationTest: day >= 28,
        evidenceSources: starterProgramEvidenceSources,
      ),
  ];
}

String _weekTheme(int day) {
  if (day <= 7) {
    return '第 1 周 · 唤醒';
  }
  if (day <= 14) {
    return '第 2 周 · 建立';
  }
  if (day <= 21) {
    return '第 3 周 · 巩固';
  }
  return '第 4 周 · 成型';
}

int _durationFor(int day) {
  if (day <= 7) {
    return 7 + day;
  }
  if (day <= 14) {
    return 14 + ((day - 7) * 6 / 7).round();
  }
  if (day <= 21) {
    return 20 + ((day - 14) * 5 / 7).round();
  }
  return 25 + ((day - 21) * 5 / 9).round();
}

String _titleFor(StarterProgramGoal goal, int day) {
  final String prefix = switch (goal) {
    StarterProgramGoal.habit => '不失败训练日',
    StarterProgramGoal.fatLoss => '低压力减脂日',
    StarterProgramGoal.runningIntro => '跑步入门日',
  };
  return '$prefix $day';
}

List<String> _trainingStepsFor(StarterProgramGoal goal, int day) {
  final int minutes = _durationFor(day);
  final bool graduation = day >= 28;
  if (graduation) {
    return ['连续慢跑或快走 15 分钟', '深蹲 8 次', '跪姿俯卧撑 6 次', '死虫每侧 6 次'];
  }

  switch (goal) {
    case StarterProgramGoal.habit:
      return ['快走 $minutes 分钟', '臀桥 8 次', '死虫每侧 6 次'];
    case StarterProgramGoal.fatLoss:
      return ['快走 ${minutes - 2} 分钟', '靠墙深蹲 8 次', '原地提膝 30 秒'];
    case StarterProgramGoal.runningIntro:
      return ['走跑交替 $minutes 分钟', 'A Skip 2 组', '提踵 12 次'];
  }
}

String _mealFor(StarterProgramGoal goal, int day) {
  if (day <= 7) {
    return '今天只改一件事：晚餐先吃蛋白质和蔬菜，再吃主食。';
  }
  if (day <= 14) {
    return '今天加第二件事：早餐加一个蛋、一盒奶或一份豆制品。';
  }
  if (day <= 21) {
    return '今天把含糖饮料换成无糖饮品或白水。';
  }
  return switch (goal) {
    StarterProgramGoal.habit => '把前三周规则合并成默认吃法，不额外增加限制。',
    StarterProgramGoal.fatLoss => '每餐保留蛋白质和蔬菜，主食减半不挨饿。',
    StarterProgramGoal.runningIntro => '训练日前后保证一份主食和一份蛋白质，避免空腹硬练。',
  };
}
