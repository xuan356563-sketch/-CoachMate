import '../data/models/plan_generation_preferences.dart';

enum AbcStrengthSessionKind {
  fullBodyA,
  fullBodyB,
  push,
  pull,
  legs,
  weakPoint,
}

class AbcStrengthExerciseTemplate {
  final String exerciseId;
  final String label;

  const AbcStrengthExerciseTemplate({
    required this.exerciseId,
    required this.label,
  });
}

class AbcStrengthSessionTemplate {
  final AbcStrengthSessionKind kind;
  final String title;
  final String purpose;
  final List<AbcStrengthExerciseTemplate> mainExercises;
  final List<AbcStrengthExerciseTemplate> accessoryExercises;

  const AbcStrengthSessionTemplate({
    required this.kind,
    required this.title,
    required this.purpose,
    required this.mainExercises,
    required this.accessoryExercises,
  });
}

class AbcStrengthWeekPrescription {
  final int mainSetCount;
  final int accessorySetCount;
  final int repetitionsPerSet;
  final String intensityLabel;
  final int mainRestSeconds;
  final int accessoryRestSeconds;

  const AbcStrengthWeekPrescription({
    required this.mainSetCount,
    required this.accessorySetCount,
    required this.repetitionsPerSet,
    required this.intensityLabel,
    required this.mainRestSeconds,
    required this.accessoryRestSeconds,
  });
}

/// 把审核后的 ABC 方法编译为本地动作目录可以执行的确定性模板。
class AbcStrengthCycleCompiler {
  List<AbcStrengthSessionTemplate> sessionsFor({
    required int strengthSessionCount,
  }) {
    if (strengthSessionCount <= 0) {
      return const <AbcStrengthSessionTemplate>[];
    }
    final List<AbcStrengthSessionKind> kinds = switch (strengthSessionCount) {
      1 => const <AbcStrengthSessionKind>[
          AbcStrengthSessionKind.fullBodyA,
        ],
      2 => const <AbcStrengthSessionKind>[
          AbcStrengthSessionKind.fullBodyA,
          AbcStrengthSessionKind.fullBodyB,
        ],
      3 => const <AbcStrengthSessionKind>[
          AbcStrengthSessionKind.push,
          AbcStrengthSessionKind.pull,
          AbcStrengthSessionKind.legs,
        ],
      4 => const <AbcStrengthSessionKind>[
          AbcStrengthSessionKind.push,
          AbcStrengthSessionKind.pull,
          AbcStrengthSessionKind.legs,
          AbcStrengthSessionKind.weakPoint,
        ],
      5 => const <AbcStrengthSessionKind>[
          AbcStrengthSessionKind.push,
          AbcStrengthSessionKind.pull,
          AbcStrengthSessionKind.legs,
          AbcStrengthSessionKind.push,
          AbcStrengthSessionKind.pull,
        ],
      _ => const <AbcStrengthSessionKind>[
          AbcStrengthSessionKind.push,
          AbcStrengthSessionKind.pull,
          AbcStrengthSessionKind.legs,
          AbcStrengthSessionKind.push,
          AbcStrengthSessionKind.pull,
          AbcStrengthSessionKind.legs,
        ],
    };
    return List<AbcStrengthSessionTemplate>.unmodifiable(
      kinds.map(_templateFor),
    );
  }

  AbcStrengthWeekPrescription progressionFor({
    required int weekIndex,
    required PlanProgressionMode mode,
  }) {
    if (weekIndex < 1 || weekIndex > 4) {
      throw RangeError.range(weekIndex, 1, 4, 'weekIndex');
    }
    if (mode == PlanProgressionMode.conservative) {
      return AbcStrengthWeekPrescription(
        mainSetCount: weekIndex == 4 ? 1 : 2,
        accessorySetCount: 1,
        repetitionsPerSet: 12,
        intensityLabel: '可控负荷，保留明显余量',
        mainRestSeconds: 60,
        accessoryRestSeconds: 45,
      );
    }
    return AbcStrengthWeekPrescription(
      mainSetCount: weekIndex == 4 ? 2 : 3,
      accessorySetCount: weekIndex == 4 ? 1 : 2,
      repetitionsPerSet: switch (weekIndex) {
        1 => 12,
        2 => 10,
        3 => 8,
        _ => 10,
      },
      intensityLabel: '可控负荷，保留明显余量',
      mainRestSeconds: 60,
      accessoryRestSeconds: 45,
    );
  }

  AbcStrengthSessionTemplate _templateFor(AbcStrengthSessionKind kind) =>
      switch (kind) {
        AbcStrengthSessionKind.fullBodyA => _fullBodyA,
        AbcStrengthSessionKind.fullBodyB => _fullBodyB,
        AbcStrengthSessionKind.push => _push,
        AbcStrengthSessionKind.pull => _pull,
        AbcStrengthSessionKind.legs => _legs,
        AbcStrengthSessionKind.weakPoint => _weakPoint,
      };

  static const AbcStrengthSessionTemplate _fullBodyA =
      AbcStrengthSessionTemplate(
    kind: AbcStrengthSessionKind.fullBodyA,
    title: 'ABC 全身 A',
    purpose: '用蹲、推、拉建立全身动作基础',
    mainExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-goblet-squat',
        label: '高脚杯深蹲',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-incline-push-up',
        label: '上斜俯卧撑',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-dumbbell-row',
        label: '俯身哑铃划船',
      ),
    ],
    accessoryExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-plank',
        label: '平板支撑',
      ),
    ],
  );

  static const AbcStrengthSessionTemplate _fullBodyB =
      AbcStrengthSessionTemplate(
    kind: AbcStrengthSessionKind.fullBodyB,
    title: 'ABC 全身 B',
    purpose: '用髋铰链、垂直推和单侧拉完成全身互补',
    mainExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-rdl',
        label: '罗马尼亚硬拉',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-dumbbell-overhead-press',
        label: '哑铃肩推',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-one-arm-dumbbell-row',
        label: '单臂哑铃划船',
      ),
    ],
    accessoryExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-side-plank',
        label: '侧桥',
      ),
    ],
  );

  static const AbcStrengthSessionTemplate _push = AbcStrengthSessionTemplate(
    kind: AbcStrengthSessionKind.push,
    title: 'ABC 推',
    purpose: '建立水平推、垂直推和肩胛控制',
    mainExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-incline-push-up',
        label: '上斜俯卧撑',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-dumbbell-overhead-press',
        label: '哑铃肩推',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-band-chest-press',
        label: '弹力带胸前推',
      ),
    ],
    accessoryExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-plank',
        label: '平板支撑',
      ),
    ],
  );

  static const AbcStrengthSessionTemplate _pull = AbcStrengthSessionTemplate(
    kind: AbcStrengthSessionKind.pull,
    title: 'ABC 拉',
    purpose: '建立双侧拉、单侧拉和后链控制',
    mainExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-dumbbell-row',
        label: '俯身哑铃划船',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-one-arm-dumbbell-row',
        label: '单臂哑铃划船',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-rdl',
        label: '罗马尼亚硬拉',
      ),
    ],
    accessoryExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-band-face-pull',
        label: '弹力带面拉',
      ),
    ],
  );

  static const AbcStrengthSessionTemplate _legs = AbcStrengthSessionTemplate(
    kind: AbcStrengthSessionKind.legs,
    title: 'ABC 腿',
    purpose: '建立蹲、髋铰链和单腿稳定',
    mainExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-goblet-squat',
        label: '高脚杯深蹲',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-rdl',
        label: '罗马尼亚硬拉',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-reverse-lunge',
        label: '反向弓步蹲',
      ),
    ],
    accessoryExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-standing-calf-raise',
        label: '站姿提踵',
      ),
    ],
  );

  static const AbcStrengthSessionTemplate _weakPoint =
      AbcStrengthSessionTemplate(
    kind: AbcStrengthSessionKind.weakPoint,
    title: 'ABC D 肩部稳定',
    purpose: '用推举、肩胛控制和负重行走补充弱项',
    mainExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-dumbbell-overhead-press',
        label: '哑铃肩推',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-band-face-pull',
        label: '弹力带面拉',
      ),
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-suitcase-carry',
        label: '单侧手提走',
      ),
    ],
    accessoryExercises: <AbcStrengthExerciseTemplate>[
      AbcStrengthExerciseTemplate(
        exerciseId: 'exercise-side-plank',
        label: '侧桥',
      ),
    ],
  );
}
