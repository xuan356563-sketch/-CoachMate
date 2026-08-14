import 'exercise.dart';

/// 动作库的发现标签。
///
/// 这是纯展示与筛选维度，不写入 [Exercise] JSON，也不会改变计划生成。
enum ExerciseFocusTag { smallMuscle, functional }

extension ExerciseFocusTagLabel on ExerciseFocusTag {
  String get label => switch (this) {
        ExerciseFocusTag.smallMuscle => '小肌群',
        ExerciseFocusTag.functional => '功能性',
      };
}

/// 小肌群与功能性动作的训练区域。
enum ExerciseFocusArea {
  shoulderNeck,
  rotatorCuffScapula,
  forearmWrist,
  deepCore,
  hipStability,
  kneeControl,
  calfAnkle,
}

extension ExerciseFocusAreaLabel on ExerciseFocusArea {
  String get label => switch (this) {
        ExerciseFocusArea.shoulderNeck => '肩颈控制',
        ExerciseFocusArea.rotatorCuffScapula => '肩袖肩胛',
        ExerciseFocusArea.forearmWrist => '前臂手腕',
        ExerciseFocusArea.deepCore => '深层核心',
        ExerciseFocusArea.hipStability => '臀髋稳定',
        ExerciseFocusArea.kneeControl => '膝控制',
        ExerciseFocusArea.calfAnkle => '小腿足踝',
      };

  int get displayOrder => ExerciseFocusArea.values.indexOf(this);
}

class ExerciseFocusProfile {
  final Set<ExerciseFocusTag> tags;
  final Set<ExerciseFocusArea> areas;

  const ExerciseFocusProfile({
    required this.tags,
    required this.areas,
  });

  static const ExerciseFocusProfile empty = ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{},
    areas: <ExerciseFocusArea>{},
  );

  bool get isEmpty => tags.isEmpty || areas.isEmpty;
}

final Map<String, ExerciseFocusProfile> _profiles =
    <String, ExerciseFocusProfile>{
  // 肩颈控制
  'exercise-chin-tuck': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.smallMuscle},
    areas: <ExerciseFocusArea>{ExerciseFocusArea.shoulderNeck},
  ),
  'exercise-neck-isometric-four-way': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.smallMuscle},
    areas: <ExerciseFocusArea>{ExerciseFocusArea.shoulderNeck},
  ),
  'exercise-neck-controlled-rotation': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{
      ExerciseFocusTag.smallMuscle,
      ExerciseFocusTag.functional,
    },
    areas: <ExerciseFocusArea>{ExerciseFocusArea.shoulderNeck},
  ),

  // 肩袖与肩胛
  'exercise-band-face-pull': _small(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-wall-slide': _both(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-shoulder-car': _both(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-band-external-rotation':
      _small(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-band-internal-rotation':
      _small(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-prone-ytw': _small(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-scapular-pull-up': _both(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-rear-delt-fly': _small(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-kettlebell-windmill': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{
      ExerciseFocusTag.smallMuscle,
      ExerciseFocusTag.functional,
    },
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.rotatorCuffScapula,
      ExerciseFocusArea.deepCore,
    },
  ),
  'exercise-landmine-press':
      _functional(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-push-up-side-plank': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.rotatorCuffScapula,
      ExerciseFocusArea.deepCore,
    },
  ),
  'exercise-scapular-push-up':
      _both(ExerciseFocusArea.rotatorCuffScapula),
  'exercise-serratus-punch':
      _small(ExerciseFocusArea.rotatorCuffScapula),

  // 前臂与手腕
  'exercise-wrist-curl': _small(ExerciseFocusArea.forearmWrist),
  'exercise-reverse-curl': _small(ExerciseFocusArea.forearmWrist),
  'exercise-hammer-curl': _small(ExerciseFocusArea.forearmWrist),
  'exercise-farmer-carry': _both(ExerciseFocusArea.forearmWrist),
  'exercise-suitcase-carry': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{
      ExerciseFocusTag.smallMuscle,
      ExerciseFocusTag.functional,
    },
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.forearmWrist,
      ExerciseFocusArea.deepCore,
    },
  ),
  'exercise-wrist-extension': _small(ExerciseFocusArea.forearmWrist),
  'exercise-forearm-pronation-supination':
      _small(ExerciseFocusArea.forearmWrist),
  'exercise-wrist-radial-ulnar-deviation':
      _small(ExerciseFocusArea.forearmWrist),
  'exercise-band-finger-extension':
      _small(ExerciseFocusArea.forearmWrist),
  'exercise-quadruped-wrist-rock': _both(ExerciseFocusArea.forearmWrist),

  // 深层核心
  'exercise-dead-bug': _both(ExerciseFocusArea.deepCore),
  'exercise-bird-dog': _both(ExerciseFocusArea.deepCore),
  'exercise-pallof-press': _both(ExerciseFocusArea.deepCore),
  'exercise-side-plank': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{
      ExerciseFocusTag.smallMuscle,
      ExerciseFocusTag.functional,
    },
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.deepCore,
      ExerciseFocusArea.hipStability,
    },
  ),
  'exercise-hollow-hold': _small(ExerciseFocusArea.deepCore),
  'exercise-plank': _both(ExerciseFocusArea.deepCore),
  'exercise-side-plank-hip-dip': _both(ExerciseFocusArea.deepCore),
  'exercise-breathing-9090': _small(ExerciseFocusArea.deepCore),
  'exercise-crocodile-breathing': _small(ExerciseFocusArea.deepCore),
  'exercise-superman': _small(ExerciseFocusArea.deepCore),
  'exercise-bear-crawl': _functional(ExerciseFocusArea.deepCore),
  'exercise-plank-shoulder-tap': _both(ExerciseFocusArea.deepCore),
  'exercise-one-arm-dumbbell-row': _functional(ExerciseFocusArea.deepCore),

  // 臀髋稳定
  'exercise-single-leg-glute-bridge': _both(ExerciseFocusArea.hipStability),
  'exercise-clamshell': _small(ExerciseFocusArea.hipStability),
  'exercise-lateral-band-walk': _both(ExerciseFocusArea.hipStability),
  'exercise-monster-walk': _both(ExerciseFocusArea.hipStability),
  'exercise-side-lying-leg-raise': _small(ExerciseFocusArea.hipStability),
  'exercise-fire-hydrant': _small(ExerciseFocusArea.hipStability),
  'exercise-hip-abduction-machine': _small(ExerciseFocusArea.hipStability),
  'exercise-single-leg-balance': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{
      ExerciseFocusTag.smallMuscle,
      ExerciseFocusTag.functional,
    },
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.hipStability,
      ExerciseFocusArea.kneeControl,
      ExerciseFocusArea.calfAnkle,
    },
  ),
  'exercise-single-leg-rdl': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.hipStability,
      ExerciseFocusArea.kneeControl,
    },
  ),
  'exercise-split-squat': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.hipStability,
      ExerciseFocusArea.kneeControl,
    },
  ),
  'exercise-rear-foot-elevated-split-squat': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.hipStability,
      ExerciseFocusArea.kneeControl,
    },
  ),
  'exercise-box-pistol-squat': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.hipStability,
      ExerciseFocusArea.kneeControl,
    },
  ),
  'exercise-trail-lateral-bound': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.hipStability,
      ExerciseFocusArea.kneeControl,
    },
  ),
  'exercise-trail-single-cone-drill':
      _functional(ExerciseFocusArea.hipStability),
  'exercise-lateral-lunge': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.hipStability,
      ExerciseFocusArea.kneeControl,
    },
  ),
  'exercise-hip-airplane': _both(ExerciseFocusArea.hipStability),
  'exercise-copenhagen-side-plank': _both(ExerciseFocusArea.hipStability),
  'exercise-wall-hip-lock': _both(ExerciseFocusArea.hipStability),

  // 膝控制
  'exercise-reverse-step-down': _functional(ExerciseFocusArea.kneeControl),
  'exercise-drop-landing': ExerciseFocusProfile(
    tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
    areas: <ExerciseFocusArea>{
      ExerciseFocusArea.kneeControl,
      ExerciseFocusArea.calfAnkle,
    },
  ),
  'exercise-reverse-lunge': _functional(ExerciseFocusArea.kneeControl),
  'exercise-trail-downhill-control':
      _functional(ExerciseFocusArea.kneeControl),
  'exercise-wall-sit': _functional(ExerciseFocusArea.kneeControl),
  'exercise-step-up': _functional(ExerciseFocusArea.kneeControl),
  'exercise-peterson-step-down':
      _functional(ExerciseFocusArea.kneeControl),
  'exercise-band-terminal-knee-extension':
      _functional(ExerciseFocusArea.kneeControl),

  // 小腿与足踝
  'exercise-standing-calf-raise': _small(ExerciseFocusArea.calfAnkle),
  'exercise-seated-calf-isometric': _small(ExerciseFocusArea.calfAnkle),
  'exercise-single-leg-calf-raise': _both(ExerciseFocusArea.calfAnkle),
  'exercise-seated-calf-raise': _small(ExerciseFocusArea.calfAnkle),
  'exercise-tibialis-raise': _small(ExerciseFocusArea.calfAnkle),
  'exercise-short-foot': _small(ExerciseFocusArea.calfAnkle),
  'exercise-toe-yoga': _small(ExerciseFocusArea.calfAnkle),
  'exercise-ankle-dorsiflexion':
      _functional(ExerciseFocusArea.calfAnkle),
  'exercise-ankle-pogo': _functional(ExerciseFocusArea.calfAnkle),
  'exercise-trail-balance-board': _both(ExerciseFocusArea.calfAnkle),
  'exercise-trail-ankle-circle':
      _functional(ExerciseFocusArea.calfAnkle),
  'exercise-trail-peroneal-stretch': _small(ExerciseFocusArea.calfAnkle),
  'exercise-calf-wall-stretch': _small(ExerciseFocusArea.calfAnkle),
  'exercise-calf-press-leg-press': _small(ExerciseFocusArea.calfAnkle),
  'exercise-split-stance-bent-knee-calf-raise':
      _both(ExerciseFocusArea.calfAnkle),
  'exercise-band-ankle-inversion': _small(ExerciseFocusArea.calfAnkle),
  'exercise-band-ankle-eversion': _small(ExerciseFocusArea.calfAnkle),
};

ExerciseFocusProfile _small(ExerciseFocusArea area) =>
    ExerciseFocusProfile(
      tags: <ExerciseFocusTag>{ExerciseFocusTag.smallMuscle},
      areas: <ExerciseFocusArea>{area},
    );

ExerciseFocusProfile _functional(ExerciseFocusArea area) =>
    ExerciseFocusProfile(
      tags: <ExerciseFocusTag>{ExerciseFocusTag.functional},
      areas: <ExerciseFocusArea>{area},
    );

ExerciseFocusProfile _both(ExerciseFocusArea area) =>
    ExerciseFocusProfile(
      tags: <ExerciseFocusTag>{
        ExerciseFocusTag.smallMuscle,
        ExerciseFocusTag.functional,
      },
      areas: <ExerciseFocusArea>{area},
    );

ExerciseFocusProfile exerciseFocusProfileForExercise(String exerciseId) =>
    _profiles[exerciseId] ?? ExerciseFocusProfile.empty;

ExerciseFocusProfile exerciseFocusProfile(Exercise exercise) =>
    exerciseFocusProfileForExercise(exercise.id);

List<Exercise> filterExercisesByFocus({
  required Iterable<Exercise> exercises,
  ExerciseFocusTag? tag,
  ExerciseFocusArea? area,
}) {
  return exercises.where((Exercise exercise) {
    final ExerciseFocusProfile profile = exerciseFocusProfile(exercise);
    return (tag == null || profile.tags.contains(tag)) &&
        (area == null || profile.areas.contains(area));
  }).toList(growable: false);
}

Map<ExerciseFocusArea, List<Exercise>> groupExercisesByFocusArea(
  Iterable<Exercise> exercises,
) {
  final Map<ExerciseFocusArea, List<Exercise>> grouped =
      <ExerciseFocusArea, List<Exercise>>{};
  for (final Exercise exercise in exercises) {
    final ExerciseFocusProfile profile = exerciseFocusProfile(exercise);
    for (final ExerciseFocusArea area in profile.areas) {
      (grouped[area] ??= <Exercise>[]).add(exercise);
    }
  }
  return <ExerciseFocusArea, List<Exercise>>{
    for (final ExerciseFocusArea area in ExerciseFocusArea.values)
      if (grouped[area]?.isNotEmpty ?? false) area: grouped[area]!,
  };
}
