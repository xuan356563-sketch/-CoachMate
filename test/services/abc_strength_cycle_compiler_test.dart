import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/exercise.dart';
import 'package:trainflow_ai/data/models/plan_generation_preferences.dart';
import 'package:trainflow_ai/data/seed/seed_exercises.dart';
import 'package:trainflow_ai/services/abc_strength_cycle_compiler.dart';

void main() {
  final AbcStrengthCycleCompiler compiler = AbcStrengthCycleCompiler();

  test('按力量课程数确定 AB、ABC、ABCD 与 ABC 循环', () {
    expect(
      _kinds(compiler.sessionsFor(strengthSessionCount: 2)),
      const <AbcStrengthSessionKind>[
        AbcStrengthSessionKind.fullBodyA,
        AbcStrengthSessionKind.fullBodyB,
      ],
    );
    expect(
      _kinds(compiler.sessionsFor(strengthSessionCount: 3)),
      const <AbcStrengthSessionKind>[
        AbcStrengthSessionKind.push,
        AbcStrengthSessionKind.pull,
        AbcStrengthSessionKind.legs,
      ],
    );
    expect(
      _kinds(compiler.sessionsFor(strengthSessionCount: 4)),
      const <AbcStrengthSessionKind>[
        AbcStrengthSessionKind.push,
        AbcStrengthSessionKind.pull,
        AbcStrengthSessionKind.legs,
        AbcStrengthSessionKind.weakPoint,
      ],
    );
    expect(
      _kinds(compiler.sessionsFor(strengthSessionCount: 5)),
      const <AbcStrengthSessionKind>[
        AbcStrengthSessionKind.push,
        AbcStrengthSessionKind.pull,
        AbcStrengthSessionKind.legs,
        AbcStrengthSessionKind.push,
        AbcStrengthSessionKind.pull,
      ],
    );
    expect(
      _kinds(compiler.sessionsFor(strengthSessionCount: 6)),
      const <AbcStrengthSessionKind>[
        AbcStrengthSessionKind.push,
        AbcStrengthSessionKind.pull,
        AbcStrengthSessionKind.legs,
        AbcStrengthSessionKind.push,
        AbcStrengthSessionKind.pull,
        AbcStrengthSessionKind.legs,
      ],
    );
  });

  test('平衡模式前三周只改变目标次数，第四周降低组数', () {
    final List<AbcStrengthWeekPrescription> weeks = <int>[1, 2, 3, 4]
        .map(
          (int week) => compiler.progressionFor(
            weekIndex: week,
            mode: PlanProgressionMode.balanced,
          ),
        )
        .toList();

    expect(
      weeks.map((AbcStrengthWeekPrescription item) => item.repetitionsPerSet),
      const <int>[12, 10, 8, 10],
    );
    expect(
      weeks.take(3).map(
            (AbcStrengthWeekPrescription item) => item.mainSetCount,
          ),
      everyElement(3),
    );
    expect(weeks.last.mainSetCount, 2);
    expect(weeks.last.accessorySetCount, 1);
    expect(
      weeks.map((AbcStrengthWeekPrescription item) => item.intensityLabel),
      everyElement('可控负荷，保留明显余量'),
    );
  });

  test('保守模式前三周保持高次数与低组数，不引入强度升级', () {
    final List<AbcStrengthWeekPrescription> weeks = <int>[1, 2, 3]
        .map(
          (int week) => compiler.progressionFor(
            weekIndex: week,
            mode: PlanProgressionMode.conservative,
          ),
        )
        .toList();

    expect(
      weeks.map((AbcStrengthWeekPrescription item) => item.repetitionsPerSet),
      everyElement(12),
    );
    expect(
      weeks.map((AbcStrengthWeekPrescription item) => item.mainSetCount),
      everyElement(2),
    );
    expect(
      weeks.map((AbcStrengthWeekPrescription item) => item.intensityLabel),
      everyElement('可控负荷，保留明显余量'),
    );
  });

  test('所有 ABC 动作都来自本地带媒体和依据的动作目录', () {
    final Map<String, Exercise> exercises = <String, Exercise>{
      for (final Exercise exercise in seedExercises) exercise.id: exercise,
    };
    final List<AbcStrengthSessionTemplate> sessions =
        compiler.sessionsFor(strengthSessionCount: 4);

    for (final AbcStrengthSessionTemplate session in sessions) {
      for (final AbcStrengthExerciseTemplate exercise
          in <AbcStrengthExerciseTemplate>[
        ...session.mainExercises,
        ...session.accessoryExercises,
      ]) {
        final Exercise? local = exercises[exercise.exerciseId];
        expect(local, isNotNull, reason: exercise.exerciseId);
        final Exercise resolved = local!;
        expect(resolved.mediaUrl, isNotEmpty, reason: exercise.exerciseId);
        expect(
          resolved.evidenceSources,
          isNotEmpty,
          reason: exercise.exerciseId,
        );
      }
    }
  });
}

List<AbcStrengthSessionKind> _kinds(
  List<AbcStrengthSessionTemplate> sessions,
) =>
    sessions
        .map((AbcStrengthSessionTemplate item) => item.kind)
        .toList(growable: false);
