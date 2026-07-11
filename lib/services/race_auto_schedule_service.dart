import '../data/models/race.dart';

class RaceAutoScheduleService {
  RaceAutoSchedule buildSchedule({
    required RacePlan race,
    required DateTime now,
    required int readinessScore,
    required bool hasPainRedline,
  }) {
    final DateTime today = _dateOnly(now);
    final DateTime raceDate = _dateOnly(race.raceDate);
    final int daysUntilRace = raceDate.difference(today).inDays;
    final int itemCount = daysUntilRace <= 0 ? 1 : 4;
    final List<RaceAutoScheduleItem> items = [
      for (int index = 0; index < itemCount; index++)
        _buildItem(
          race: race,
          weekOffset: index,
          weekStart: today.add(Duration(days: index * 7)),
          daysUntilRace: daysUntilRace - index * 7,
          readinessScore: readinessScore,
          hasPainRedline: hasPainRedline,
        ),
    ];

    return RaceAutoSchedule(
      raceId: race.id,
      raceName: race.name,
      generatedAt: now,
      daysUntilRace: daysUntilRace,
      statusLabel: _statusLabel(daysUntilRace, items.first.phaseType),
      items: items,
    );
  }

  RaceAutoScheduleItem _buildItem({
    required RacePlan race,
    required int weekOffset,
    required DateTime weekStart,
    required int daysUntilRace,
    required int readinessScore,
    required bool hasPainRedline,
  }) {
    final RacePhaseType phaseType = _phaseForDaysUntilRace(daysUntilRace);
    final RaceTrainingPhase phase = _phaseTemplate(race, phaseType);
    final List<String> workouts = _keyWorkoutsForPhase(race, phase);
    return RaceAutoScheduleItem(
      weekOffset: weekOffset,
      weekStart: weekStart,
      weekEnd: weekStart.add(const Duration(days: 6)),
      phaseType: phaseType,
      focus: phase.focus,
      keyWorkouts: workouts,
      nutritionCue: _nutritionCue(race.type, phaseType),
      recoveryRule: _recoveryRule(readinessScore, phaseType),
      safetyGate:
          hasPainRedline ? '疼痛红线优先：本周只保留恢复和无痛技术练习。' : '若疼痛 ≥7 或疲劳 ≥8，自动改为恢复周。',
    );
  }

  RacePhaseType _phaseForDaysUntilRace(int daysUntilRace) {
    if (daysUntilRace <= 7) {
      return RacePhaseType.raceWeek;
    }
    if (daysUntilRace <= 21) {
      return RacePhaseType.taper;
    }
    if (daysUntilRace <= 49) {
      return RacePhaseType.specific;
    }
    if (daysUntilRace <= 84) {
      return RacePhaseType.build;
    }
    return RacePhaseType.base;
  }

  RaceTrainingPhase _phaseTemplate(RacePlan race, RacePhaseType phaseType) {
    for (final RaceTrainingPhase phase in race.phases) {
      if (phase.phaseType == phaseType) {
        return phase;
      }
    }
    if (phaseType == RacePhaseType.raceWeek) {
      return RaceTrainingPhase(
        phaseType: RacePhaseType.raceWeek,
        weekRange: '比赛周',
        focus: '保留状态，确认装备、补给和比赛日流程。',
        keyWorkouts: ['20 分钟轻松唤醒', '装备检查', '比赛日执行'],
      );
    }
    return race.phases.isEmpty
        ? const RaceTrainingPhase(
            phaseType: RacePhaseType.base,
            weekRange: '自动排期',
            focus: '先建立可恢复的训练节奏。',
            keyWorkouts: ['轻松训练', '技术练习', '恢复检查'],
          )
        : race.phases.first;
  }

  List<String> _keyWorkoutsForPhase(
    RacePlan race,
    RaceTrainingPhase phase,
  ) {
    if (phase.phaseType == RacePhaseType.raceWeek) {
      return ['比赛日流程确认', ...race.taperPlan.take(2)];
    }
    return phase.keyWorkouts.take(3).toList();
  }

  String _nutritionCue(RaceType raceType, RacePhaseType phaseType) {
    if (phaseType == RacePhaseType.raceWeek ||
        phaseType == RacePhaseType.taper) {
      return '确认比赛日早餐、补给和水站策略，不尝试新食物。';
    }
    switch (raceType) {
      case RaceType.hyrox:
        return '训练后 30 分钟补碳水和蛋白，站点课前避免空腹。';
      case RaceType.marathon:
      case RaceType.roadRunning:
      case RaceType.trailRunning:
        return '长课前练习碳水补给，记录肠胃反应。';
    }
  }

  String _recoveryRule(int readinessScore, RacePhaseType phaseType) {
    if (readinessScore < 55) {
      return '准备度偏低：本周减少 30% 总量，强度课改技术课。';
    }
    if (phaseType == RacePhaseType.taper ||
        phaseType == RacePhaseType.raceWeek) {
      return '减量期不补课，睡眠和轻量活动优先。';
    }
    return '关键课后至少保留 24 小时恢复窗口。';
  }

  String _statusLabel(int daysUntilRace, RacePhaseType phaseType) {
    if (daysUntilRace <= 0) {
      return '比赛日复盘';
    }
    return '自动排期 · ${phaseType.label} · 距比赛 $daysUntilRace 天';
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
