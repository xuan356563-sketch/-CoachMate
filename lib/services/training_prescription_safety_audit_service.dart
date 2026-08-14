import '../data/models/ai_training_prescription.dart';
import '../data/models/exercise.dart';
import '../data/models/exercise_training_profile.dart';
import '../data/models/training_plan.dart';
import '../data/models/user_profile.dart';
import '../data/models/workout_day.dart';
import '../data/seed/seed_exercises.dart';

class TrainingPrescriptionSafetyAuditReport {
  const TrainingPrescriptionSafetyAuditReport({
    required this.failures,
    required this.warnings,
  });

  final List<String> failures;
  final List<String> warnings;

  bool get canActivate => failures.isEmpty;
}

/// 对 AI 处方和本地编译结果执行不可被 Skill 覆盖的安全门槛。
class TrainingPrescriptionSafetyAuditService {
  TrainingPrescriptionSafetyAuditReport auditPrescription({
    required AiTrainingPrescription prescription,
    required UserProfile profile,
    bool hasActiveRace = false,
  }) {
    final List<String> failures = <String>[];
    final List<String> warnings = <String>[];
    final int expectedSessions = profile.weeklyTrainingDays.clamp(1, 6);

    if (!const <String>{'base', 'build', 'specific', 'taper'}
        .contains(prescription.cycleFocus)) {
      failures.add('周期重点不在允许的枚举范围内。');
    }
    if (!hasActiveRace &&
        const <String>{'specific', 'taper'}.contains(prescription.cycleFocus)) {
      failures.add('没有有效赛事时不能激活专项期或减量期处方。');
    }

    if (profile.trainingExperienceLevel == TrainingExperienceLevel.unknown) {
      failures.add('训练经验未补充，不能激活 Skill 计划。');
    }
    if (profile.age < 18) {
      failures.add('Skill 计划 V1 仅允许 18 岁及以上用户激活。');
    }
    if (profile.mainSports.contains(MainSport.rehab)) {
      failures.add('康复目标不在 Skill 计划 V1 范围内。');
    }
    if (prescription.weeklySessions.length != expectedSessions) {
      failures.add('每周课程数必须为 $expectedSessions 次，并保留至少 1 个休息日。');
    }

    final int challengingCount = prescription.weeklySessions
        .where(
          (AiSessionBlueprint item) =>
              item.intensityBand == AiIntensityBand.challenging,
        )
        .length;
    if (challengingCount > 2) {
      failures.add('挑战强度课每周不能超过 2 次。');
    }
    final bool hasLowIntensitySession = prescription.weeklySessions.any(
      (AiSessionBlueprint item) =>
          item.intensityBand == AiIntensityBand.recovery ||
          item.intensityBand == AiIntensityBand.easy,
    );
    if (!hasLowIntensitySession) {
      failures.add('每周至少需要 1 次恢复或轻松强度课程。');
    }
    if (profile.trainingExperienceLevel == TrainingExperienceLevel.beginner &&
        prescription.progressionMode != AiProgressionMode.conservative) {
      failures.add('初学者只能使用保守进阶模式。');
    }

    for (final AiSessionBlueprint session in prescription.weeklySessions) {
      if (session.trainingType == TrainingType.rehab ||
          session.trainingType == TrainingType.rest) {
        failures.add('处方包含 V1 不支持的康复或休息课程。');
      }
      if (session.durationMinutes < 20 || session.durationMinutes > 180) {
        failures.add('课程时长必须在 20–180 分钟之间。');
      }
      if (session.durationMinutes > profile.dailyAvailableMinutes) {
        failures.add(
            '课程时长 ${session.durationMinutes} 分钟超过当前可用时间 ${profile.dailyAvailableMinutes} 分钟。');
      }
    }

    if (!_isSha256(prescription.skill.sourceSha256) ||
        !_isSha256(prescription.skill.runtimeSha256)) {
      failures.add('Skill 来源或运行时哈希不是有效的 SHA-256。');
    }
    if (prescription.skill.fragmentSha256 != null &&
        !_isSha256(prescription.skill.fragmentSha256!)) {
      failures.add('Skill 专项片段哈希不是有效的 SHA-256。');
    }
    if (!_isSha256(prescription.generationMeta.clientContextDigest)) {
      failures.add('客户端上下文摘要不是有效的 SHA-256。');
    }
    if (profile.trainingExperienceLevel == TrainingExperienceLevel.beginner &&
        challengingCount > 0) {
      warnings.add('初学者的挑战课将由本地编译器降到 RPE 6。');
    }

    return TrainingPrescriptionSafetyAuditReport(
      failures: List<String>.unmodifiable(failures),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  TrainingPrescriptionSafetyAuditReport auditCompiledPlan({
    required TrainingPlan plan,
    required UserProfile profile,
    bool enforceFourWeekDeload = true,
    bool racePhaseOverride = false,
  }) {
    final List<String> failures = <String>[];
    final Map<int, List<WorkoutDay>> weeks = <int, List<WorkoutDay>>{};
    final Map<int, Set<int>> occupiedDayIndexes = <int, Set<int>>{};
    final List<int> hardDayOrdinals = <int>[];
    final Map<String, Exercise> exercisesById = <String, Exercise>{
      for (final Exercise exercise in seedExercises) exercise.id: exercise,
    };
    bool explosiveRestFailureAdded = false;
    bool beginnerAirborneFailureAdded = false;
    bool unlockFailureAdded = false;
    for (final WorkoutDay day in plan.workoutDays) {
      weeks.putIfAbsent(day.weekIndex, () => <WorkoutDay>[]).add(day);
      if (day.dayIndex < 1 || day.dayIndex > 7) {
        failures.add('第 ${day.weekIndex} 周训练日序必须在 1–7 之间。');
      } else if (!occupiedDayIndexes
          .putIfAbsent(day.weekIndex, () => <int>{})
          .add(day.dayIndex)) {
        failures.add('第 ${day.weekIndex} 周存在重复训练日 ${day.dayIndex}。');
      }
      final int maxRpe = _maxRpe(day.intensity);
      final int allowedRpe =
          profile.trainingExperienceLevel == TrainingExperienceLevel.beginner
              ? 6
              : 7;
      if (maxRpe > allowedRpe) {
        failures
            .add('${day.title}强度 ${day.intensity} 超过当前经验等级上限 RPE $allowedRpe。');
      }
      if (day.estimatedMinutes > profile.dailyAvailableMinutes) {
        failures.add('${day.title}超过每次可用时间。');
      }
      if (day.coachNotes.contains('暂未找到安全的无器械替代')) {
        failures.add('${day.title}存在未解决的器械替代。');
      }
      if (maxRpe >= 7) {
        hardDayOrdinals.add((day.weekIndex - 1) * 7 + day.dayIndex);
      }
      if (day.structurePolicyVersion == trainingStructurePolicyVersion) {
        for (final WorkoutExerciseLink link in day.workoutExercises) {
          final ExerciseTrainingProfile training =
              trainingProfileForExercise(link.exerciseId);
          if (!explosiveRestFailureAdded &&
              link.executionIntent == ExecutionIntent.explosive &&
              link.restSeconds < 90) {
            failures.add('爆发动作组间休息不得少于 90 秒。');
            explosiveRestFailureAdded = true;
          }
          if (!beginnerAirborneFailureAdded &&
              profile.trainingExperienceLevel ==
                  TrainingExperienceLevel.beginner &&
              training.airborne) {
            failures.add('初学者计划不能包含腾空动作，应使用无腾空快速向心退阶。');
            beginnerAirborneFailureAdded = true;
          }
          final Exercise? exercise = exercisesById[link.exerciseId];
          if (!unlockFailureAdded &&
              training.airborne &&
              (exercise == null ||
                  !exercise.relations.any(
                    (ExerciseRelation relation) =>
                        relation.type == ExerciseRelationType.unlockedBy &&
                        relation.targetExerciseId == 'exercise-drop-landing',
                  ))) {
            failures.add('腾空动作缺少下落着地解锁关系。');
            unlockFailureAdded = true;
          }
        }
        failures.addAll(_auditStructuredLegOrder(day));
      }
    }
    hardDayOrdinals.sort();
    for (int index = 1; index < hardDayOrdinals.length; index += 1) {
      if (hardDayOrdinals[index] - hardDayOrdinals[index - 1] < 3) {
        failures.add('挑战强度课之间必须至少间隔 2 个完整日。');
        break;
      }
    }

    for (final MapEntry<int, List<WorkoutDay>> entry in weeks.entries) {
      final List<WorkoutDay> activeDays = entry.value
          .where((WorkoutDay day) => day.trainingType != TrainingType.rest)
          .toList();
      if (activeDays.length > 6) {
        failures.add('第 ${entry.key} 周超过 6 个训练日，没有保留完整休息日。');
      }
      final int hardDays = activeDays
          .where((WorkoutDay day) => _maxRpe(day.intensity) >= 7)
          .length;
      if (hardDays > 2) {
        failures.add('第 ${entry.key} 周超过 2 次挑战强度课。');
      }
    }

    final List<int> weekIndexes = weeks.keys.toList()..sort();
    final Map<int, int> volumes = <int, int>{
      for (final int index in weekIndexes)
        index: weeks[index]!
            .where((WorkoutDay day) => day.trainingType != TrainingType.rest)
            .fold<int>(
                0, (int total, WorkoutDay day) => total + day.estimatedMinutes),
    };
    for (int index = 1; index < weekIndexes.length; index += 1) {
      final int previous = volumes[weekIndexes[index - 1]] ?? 0;
      final int current = volumes[weekIndexes[index]] ?? 0;
      if (previous > 0 && current > previous * 1.10 + 1) {
        failures.add('第 ${weekIndexes[index]} 周训练量增长超过 10%。');
      }
    }

    for (int weekIndex = 2; weekIndex <= 3; weekIndex += 1) {
      final List<WorkoutDay> previous = List<WorkoutDay>.from(
          weeks[weekIndex - 1] ?? const <WorkoutDay>[])
        ..sort(
            (WorkoutDay a, WorkoutDay b) => a.dayIndex.compareTo(b.dayIndex));
      final List<WorkoutDay> current = List<WorkoutDay>.from(
          weeks[weekIndex] ?? const <WorkoutDay>[])
        ..sort(
            (WorkoutDay a, WorkoutDay b) => a.dayIndex.compareTo(b.dayIndex));
      for (int session = 0;
          session < previous.length && session < current.length;
          session += 1) {
        final bool durationChanged = previous[session].estimatedMinutes !=
            current[session].estimatedMinutes;
        final bool intensityChanged =
            previous[session].intensity != current[session].intensity;
        final bool isRaceSafetyDowngrade = racePhaseOverride &&
            current[session].estimatedMinutes <
                previous[session].estimatedMinutes &&
            _maxRpe(current[session].intensity) <
                _maxRpe(previous[session].intensity);
        if (durationChanged && intensityChanged && !isRaceSafetyDowngrade) {
          failures.add('第 $weekIndex 周同一课程同时推进了时长和强度。');
          break;
        }
      }
    }

    if (enforceFourWeekDeload && volumes.length == 4) {
      final int peak = <int>[
        volumes[1] ?? 0,
        volumes[2] ?? 0,
        volumes[3] ?? 0,
      ].reduce((int first, int second) => first > second ? first : second);
      final int deload = volumes[4] ?? 0;
      final double ratio = peak == 0 ? 0 : deload / peak;
      if (ratio < 0.40 || ratio > 0.60) {
        failures.add('第 4 周训练量必须位于峰值周的 40%–60%。');
      }
    }

    final Map<int, int> eccentricVolumes = <int, int>{};
    for (final WorkoutDay day in plan.workoutDays.where(
      (WorkoutDay item) =>
          item.structurePolicyVersion == trainingStructurePolicyVersion,
    )) {
      eccentricVolumes.update(
        day.weekIndex,
        (int current) => current + _eccentricVolume(day),
        ifAbsent: () => _eccentricVolume(day),
      );
    }
    for (int weekIndex = 2; weekIndex <= 3; weekIndex += 1) {
      final int previous = eccentricVolumes[weekIndex - 1] ?? 0;
      final int current = eccentricVolumes[weekIndex] ?? 0;
      if (previous > 0 && current > previous * 1.20) {
        failures.add('第 $weekIndex 周离心训练量增长超过 20%。');
      }
    }

    failures.addAll(_auditAbcStrengthCycle(plan));

    return TrainingPrescriptionSafetyAuditReport(
      failures: List<String>.unmodifiable(failures),
      warnings: const <String>[],
    );
  }

  int _eccentricVolume(WorkoutDay day) {
    return day.workoutExercises
        .where(
          (WorkoutExerciseLink link) => trainingProfileForExercise(
            link.exerciseId,
          ).dimensions.contains(TrainingDimension.eccentric),
        )
        .fold<int>(
          0,
          (int total, WorkoutExerciseLink link) =>
              total +
              link.plannedSetCount *
                  (link.repetitionsPerSet <= 0 ? 1 : link.repetitionsPerSet),
        );
  }

  List<String> _auditStructuredLegOrder(WorkoutDay day) {
    final List<WorkoutExerciseLink> working = day.workoutExercises
        .where(
          (WorkoutExerciseLink link) =>
              link.module == WorkoutExerciseModule.mainTraining ||
              link.module == WorkoutExerciseModule.accessory ||
              link.module == WorkoutExerciseModule.calf,
        )
        .toList()
      ..sort(
        (WorkoutExerciseLink first, WorkoutExerciseLink second) =>
            first.sequence.compareTo(second.sequence),
      );
    final bool isLegSession = working.any(
      (WorkoutExerciseLink link) =>
          trainingProfileForExercise(link.exerciseId).legElements.isNotEmpty,
    );
    if (!isLegSession) return const <String>[];

    bool encounteredNonExplosive = false;
    for (final WorkoutExerciseLink link in working.where(
      (WorkoutExerciseLink item) =>
          item.module == WorkoutExerciseModule.mainTraining,
    )) {
      if (link.executionIntent == ExecutionIntent.explosive) {
        if (encounteredNonExplosive) {
          return <String>['${day.title}的爆发动作必须排在主训练最前。'];
        }
      } else {
        encounteredNonExplosive = true;
      }
    }

    bool encounteredCalfFinish = false;
    for (final WorkoutExerciseLink link in working) {
      final ExerciseTrainingProfile profile =
          trainingProfileForExercise(link.exerciseId);
      final bool calfStrength = link.module == WorkoutExerciseModule.calf ||
          (profile.legElements.contains(LegTrainingElement.footAnkle) &&
              profile.dimensions.contains(TrainingDimension.strength));
      if (calfStrength) {
        encounteredCalfFinish = true;
      } else if (encounteredCalfFinish) {
        return <String>['${day.title}的足踝力量动作必须作为腿部主训练收尾。'];
      }
    }
    return const <String>[];
  }

  List<String> _auditAbcStrengthCycle(TrainingPlan plan) {
    final List<WorkoutDay> abcDays = plan.workoutDays
        .where((WorkoutDay day) => _abcSessionKey(day.title) != null)
        .toList();
    if (abcDays.isEmpty) return const <String>[];

    final List<String> failures = <String>[];
    final RegExp fixedLoadOrFailure = RegExp(
      r'(?:\d+(?:\.\d+)?\s*(?:公斤|千克|kg))|力竭',
      caseSensitive: false,
    );
    if (abcDays.any(
      (WorkoutDay day) => day.workoutExercises.any(
        (WorkoutExerciseLink link) =>
            fixedLoadOrFailure.hasMatch(link.plannedWeightOrIntensity),
      ),
    )) {
      failures.add('ABC 计划包含固定重量或力竭指令。');
    }

    final Map<String, List<WorkoutDay>> sessions = <String, List<WorkoutDay>>{};
    final Map<int, List<WorkoutDay>> daysByWeek = <int, List<WorkoutDay>>{};
    for (final WorkoutDay day in abcDays) {
      daysByWeek.putIfAbsent(day.weekIndex, () => <WorkoutDay>[]).add(day);
    }
    for (final List<WorkoutDay> weekDays in daysByWeek.values) {
      weekDays.sort(
        (WorkoutDay first, WorkoutDay second) =>
            first.dayIndex.compareTo(second.dayIndex),
      );
      final Map<String, int> occurrences = <String, int>{};
      for (final WorkoutDay day in weekDays) {
        final String title = _abcSessionKey(day.title)!;
        final int occurrence = occurrences[title] ?? 0;
        occurrences[title] = occurrence + 1;
        sessions
            .putIfAbsent('$title#$occurrence', () => <WorkoutDay>[])
            .add(day);
      }
    }
    bool actionDrift = false;
    bool progressionInvalid = false;
    for (final List<WorkoutDay> workouts in sessions.values) {
      workouts.sort(
        (WorkoutDay first, WorkoutDay second) =>
            first.weekIndex.compareTo(second.weekIndex),
      );
      if (workouts.length != 4) {
        progressionInvalid = true;
        continue;
      }
      final List<String> expectedExercises = _abcWorkingExerciseIds(
        workouts.first,
      );
      if (workouts.skip(1).any(
            (WorkoutDay day) =>
                !_sameStrings(expectedExercises, _abcWorkingExerciseIds(day)),
          )) {
        actionDrift = true;
      }
      final List<WorkoutExerciseLink?> firstMainLinks = workouts
          .map(
            (WorkoutDay day) => _firstMainExercise(day),
          )
          .toList();
      if (firstMainLinks.any((WorkoutExerciseLink? link) => link == null)) {
        progressionInvalid = true;
        continue;
      }
      final List<int> repetitions = firstMainLinks
          .map((WorkoutExerciseLink? link) => link!.repetitionsPerSet)
          .toList();
      final bool balanced = _sameInts(repetitions, const <int>[12, 10, 8, 10]);
      final bool conservative =
          _sameInts(repetitions, const <int>[12, 12, 12, 12]);
      final int peakSets = firstMainLinks
          .take(3)
          .map((WorkoutExerciseLink? link) => link!.plannedSetCount)
          .reduce((int first, int second) => first > second ? first : second);
      if ((!balanced && !conservative) ||
          firstMainLinks.last!.plannedSetCount >= peakSets) {
        progressionInvalid = true;
      }
    }
    if (actionDrift) {
      failures.add('ABC 动作必须在四周保持稳定，当前计划存在动作漂移。');
    }
    if (progressionInvalid) {
      failures.add('ABC 渐进或第四周减量结构不完整。');
    }
    return failures;
  }

  String? _abcSessionKey(String title) {
    final int separator = title.indexOf(' · ');
    final String candidate =
        separator < 0 ? title : title.substring(separator + 3);
    return candidate.startsWith('ABC ') ? candidate : null;
  }

  List<String> _abcWorkingExerciseIds(WorkoutDay day) => day.workoutExercises
      .where(
        (WorkoutExerciseLink link) =>
            link.module == WorkoutExerciseModule.mainTraining ||
            link.module == WorkoutExerciseModule.accessory,
      )
      .map((WorkoutExerciseLink link) => link.exerciseId)
      .toList(growable: false);

  WorkoutExerciseLink? _firstMainExercise(WorkoutDay day) {
    for (final WorkoutExerciseLink link in day.workoutExercises) {
      if (link.module == WorkoutExerciseModule.mainTraining) return link;
    }
    return null;
  }

  bool _sameStrings(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (int index = 0; index < first.length; index += 1) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  bool _sameInts(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (int index = 0; index < first.length; index += 1) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  int _maxRpe(String value) {
    final Iterable<RegExpMatch> matches = RegExp(r'\d+').allMatches(value);
    int maximum = 0;
    for (final RegExpMatch match in matches) {
      final int parsed = int.tryParse(match.group(0) ?? '') ?? 0;
      if (parsed > maximum) maximum = parsed;
    }
    return maximum;
  }

  bool _isSha256(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
}
