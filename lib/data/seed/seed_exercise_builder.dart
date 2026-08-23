import '../models/evidence_source.dart';
import '../models/exercise.dart';
import '../models/user_profile.dart';

/// 动作条目构造器。
///
/// 动作库扩展后条目分散在多个 seed 文件里，用同一个构造器保证字段口径一致：
/// mediaUrl 统一走 `placeholder://<id>-motion-loop`，禁忌和适用场景至少各有一条。
Exercise buildSeedExercise({
  required List<EvidenceSource> evidenceSources,
  required String id,
  required String name,
  required ExerciseCategory category,
  required List<String> targetMuscles,
  required List<MainSport> sportTags,
  required String description,
  required List<String> steps,
  required List<String> commonMistakes,
  required String setsAndReps,
  required List<String> equipment,
  required String breathingCue,
  List<String> mediaUrls = const <String>[],
  ExerciseMediaStatus mediaStatus = ExerciseMediaStatus.placeholder,
  List<ExerciseRelation> relations = const <ExerciseRelation>[],
  List<String> safetyNotes = const <String>['出现尖锐疼痛、头晕或动作失稳时停止。'],
  List<String> useCases = const <String>['基础训练'],
}) {
  return Exercise(
    id: id,
    name: name,
    category: category,
    targetMuscles: targetMuscles,
    sportTags: sportTags,
    description: description,
    steps: steps,
    commonMistakes: commonMistakes,
    setsAndReps: setsAndReps,
    equipment: equipment,
    mediaUrl: 'placeholder://$id-motion-loop',
    mediaUrls: mediaUrls,
    mediaStatus: mediaStatus,
    breathingCue: breathingCue,
    contraindications: safetyNotes,
    suitableFor: useCases,
    evidenceSources: evidenceSources,
    relations: relations,
  );
}

/// 动作示范图数据集：默认免费库，另有两套 AI 模特图（女/男）。
enum ExerciseDemoSet { freeDb, female, male }

/// 当前启用的示范图数据集（切换即可换图）。
const ExerciseDemoSet activeExerciseDemoSet = ExerciseDemoSet.female;

/// 与免费库重叠、已生成 AI 模特图的动作 slug 集合。
const Set<String> _aiDemoSlugs = <String>{
    'ab_wheel_rollout', 'arnold_press', 'back_extension', 'band_assisted_pull_up', 'band_chest_press', 'band_face_pull',
    'band_row', 'barbell_back_squat', 'barbell_bench_press', 'barbell_curl', 'barbell_overhead_press', 'barbell_row',
    'barbell_shrug', 'bear_crawl', 'bench_dip', 'bodyweight_fly', 'bodyweight_squat', 'box_jump',
    'box_pistol_squat', 'box_squat', 'breathing_9090', 'butterfly_stretch', 'cable_crossover', 'cable_crunch',
    'cable_pull_through', 'calf_press_leg_press', 'calf_wall_stretch', 'cat_cow', 'cf_air_bike', 'cf_battle_rope',
    'cf_dumbbell_snatch', 'cf_hang_power_clean', 'cf_kettlebell_clean', 'cf_kettlebell_sumo_high_pull', 'cf_power_clean', 'cf_push_press',
    'cf_rope_climb', 'cf_thruster', 'cf_turkish_get_up', 'chest_dip', 'chest_supported_row', 'childs_pose',
    'close_grip_bench_press', 'conventional_deadlift', 'couch_stretch', 'crocodile_breathing', 'crunch', 'decline_push_up',
    'diamond_push_up', 'donkey_kick', 'doorway_chest_stretch', 'downward_dog', 'dumbbell_bench_press', 'dumbbell_curl',
    'dumbbell_fly', 'dumbbell_overhead_press', 'dumbbell_row', 'easy_run', 'farmer_carry', 'feet_elevated_push_up',
    'fire_hydrant', 'freehand_jump_squat', 'front_raise', 'front_squat', 'glute_bridge', 'glute_kickback',
    'goblet_squat', 'good_morning', 'hack_squat', 'hammer_curl', 'hamstring_sweep', 'hanging_leg_raise',
    'hill_walk', 'hip_9090_switch', 'hip_thrust', 'hyrox_row_warmup', 'inchworm', 'incline_barbell_bench_press',
    'incline_dumbbell_curl', 'incline_dumbbell_press', 'incline_push_up', 'jackknife_sit_up', 'jump_lunge', 'jumping_jack',
    'kettlebell_deadlift', 'kettlebell_swing', 'kettlebell_windmill', 'landmine_press', 'lat_pulldown', 'lateral_band_walk',
    'lateral_lunge', 'lateral_raise', 'leg_extension', 'leg_press', 'lying_leg_curl', 'machine_chest_press',
    'med_ball_slam', 'monster_walk', 'mountain_climber', 'nordic_curl_eccentric', 'one_arm_dumbbell_row', 'overhead_triceps_extension',
    'pallof_press', 'pec_deck_fly', 'pike_push_up', 'plank', 'plank_shoulder_tap', 'plank_up_down',
    'preacher_curl', 'prone_ytw', 'pull_up', 'pull_up_negative', 'push_up_side_plank', 'rack_pull',
    'rear_delt_fly', 'rear_foot_elevated_split_squat', 'reverse_crunch', 'reverse_curl', 'reverse_lunge', 'run_walk_interval',
    'running_strides', 'russian_twist', 'scapular_pull_up', 'seated_cable_row', 'seated_calf_isometric', 'seated_calf_raise',
    'seated_dumbbell_press', 'seated_hamstring_stretch', 'side_lying_leg_raise', 'side_plank', 'single_leg_calf_raise', 'single_leg_glute_bridge',
    'sit_up', 'ski_erg_pull', 'skull_crusher', 'smith_machine_squat', 'split_squat', 'standard_push_up',
    'standing_calf_raise', 'standing_quad_stretch', 'step_up', 'straight_arm_pulldown', 'suitcase_carry', 'sumo_deadlift',
    'superman', 'supine_figure_4', 't_bar_row', 'tibialis_raise', 'trail_balance_board', 'trail_butt_kick',
    'trail_carioca', 'trail_depth_jump', 'trail_elevated_back_lunge', 'trail_peroneal_stretch', 'trail_single_cone_drill', 'trail_stair_climb',
    'trail_uphill_sprint', 'triceps_pushdown', 'upright_row', 'walk_recovery', 'walking_lunge', 'wall_ball',
    'wall_sit',
};

/// 解析某个动作的示范图路径前缀：重叠动作优先用当前启用的 AI 套，否则回退免费库。
String _seedExerciseImageBase(String slug) {
  if (activeExerciseDemoSet == ExerciseDemoSet.freeDb || !_aiDemoSlugs.contains(slug)) {
    return 'assets/images/exercises/free-exercise-db';
  }
  return activeExerciseDemoSet == ExerciseDemoSet.female
      ? 'assets/images/exercises/ai-female'
      : 'assets/images/exercises/ai-male';
}

/// 生成一个动作的两张示范图路径。`slug` 对应本地文件名前缀。
List<String> seedExerciseImages(String slug) {
  final String base = _seedExerciseImageBase(slug);
  return <String>[
    '$base/${slug}_0.jpg',
    '$base/${slug}_1.jpg',
  ];
}

/// 退阶关系快捷构造。
ExerciseRelation regressionTo(String targetExerciseId, String reason) {
  return ExerciseRelation(
    type: ExerciseRelationType.regression,
    targetExerciseId: targetExerciseId,
    reason: reason,
  );
}

/// 进阶关系快捷构造。
ExerciseRelation progressionTo(String targetExerciseId, String reason) {
  return ExerciseRelation(
    type: ExerciseRelationType.progression,
    targetExerciseId: targetExerciseId,
    reason: reason,
  );
}

/// 替代关系快捷构造。
ExerciseRelation replacementWith(String targetExerciseId, String reason) {
  return ExerciseRelation(
    type: ExerciseRelationType.replacement,
    targetExerciseId: targetExerciseId,
    reason: reason,
  );
}

/// 解锁条件快捷构造。
ExerciseRelation unlockedBy(String targetExerciseId, String reason) {
  return ExerciseRelation(
    type: ExerciseRelationType.unlockedBy,
    targetExerciseId: targetExerciseId,
    reason: reason,
  );
}
