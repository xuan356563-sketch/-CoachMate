import '../models/exercise.dart';
import 'seed_exercise_builder.dart';

class _Media {
  final String slug;
  final ExerciseMediaStatus status;

  const _Media(this.slug, this.status);
}

/// 动作示范图清单。
///
/// 图片来自 free-exercise-db（Unlicense 公有领域），本地文件位于
/// `assets/images/exercises/free-exercise-db/<slug>_0.jpg` 与 `_1.jpg`。
///
/// 这里只登记「条目定义里没有内联写图片」的动作。新增动作在各自的 seed 文件里
/// 直接通过 [seedExerciseImages] 指定，清单不会覆盖它们。
///
/// [ExerciseMediaStatus.precise] 表示图片与动作名一一对应；
/// [ExerciseMediaStatus.reference] 表示只是同类动作的通用参考，
/// 详情页会明确提示「通用参考，精确纠错示范待补充」。
const Map<String, _Media> _exerciseMediaManifest = <String, _Media>{
  'exercise-box-squat': _Media('box_squat', ExerciseMediaStatus.precise),
  'exercise-front-squat': _Media('front_squat', ExerciseMediaStatus.precise),
  'exercise-single-leg-calf-raise':
      _Media('single_leg_calf_raise', ExerciseMediaStatus.reference),
  'exercise-seated-calf-isometric':
      _Media('seated_calf_isometric', ExerciseMediaStatus.reference),
  'exercise-glute-bridge': _Media('glute_bridge', ExerciseMediaStatus.precise),
  'exercise-lateral-band-walk':
      _Media('lateral_band_walk', ExerciseMediaStatus.precise),
  'exercise-farmer-carry': _Media('farmer_carry', ExerciseMediaStatus.precise),
  'exercise-suitcase-carry':
      _Media('suitcase_carry', ExerciseMediaStatus.reference),
  'exercise-kettlebell-swing':
      _Media('kettlebell_swing', ExerciseMediaStatus.reference),
  'exercise-bodyweight-squat':
      _Media('bodyweight_squat', ExerciseMediaStatus.precise),
  'exercise-split-squat': _Media('split_squat', ExerciseMediaStatus.precise),
  'exercise-step-up': _Media('step_up', ExerciseMediaStatus.precise),
  'exercise-hip-thrust': _Media('hip_thrust', ExerciseMediaStatus.precise),
  'exercise-single-leg-glute-bridge':
      _Media('single_leg_glute_bridge', ExerciseMediaStatus.reference),
  'exercise-good-morning': _Media('good_morning', ExerciseMediaStatus.precise),
  'exercise-kettlebell-deadlift':
      _Media('kettlebell_deadlift', ExerciseMediaStatus.reference),
  'exercise-dumbbell-row': _Media('dumbbell_row', ExerciseMediaStatus.precise),
  'exercise-one-arm-dumbbell-row':
      _Media('one_arm_dumbbell_row', ExerciseMediaStatus.precise),
  'exercise-dumbbell-overhead-press':
      _Media('dumbbell_overhead_press', ExerciseMediaStatus.precise),
  'exercise-band-chest-press':
      _Media('band_chest_press', ExerciseMediaStatus.reference),
  'exercise-band-row': _Media('band_row', ExerciseMediaStatus.reference),
  'exercise-band-face-pull':
      _Media('band_face_pull', ExerciseMediaStatus.precise),
  'exercise-side-plank': _Media('side_plank', ExerciseMediaStatus.precise),
  'exercise-mountain-climber':
      _Media('mountain_climber', ExerciseMediaStatus.precise),
  'exercise-bear-crawl': _Media('bear_crawl', ExerciseMediaStatus.reference),
  'exercise-calf-wall-stretch':
      _Media('calf_wall_stretch', ExerciseMediaStatus.precise),
  'exercise-monster-walk': _Media('monster_walk', ExerciseMediaStatus.precise),
  'exercise-cat-cow': _Media('cat_cow', ExerciseMediaStatus.precise),
  'exercise-couch-stretch':
      _Media('couch_stretch', ExerciseMediaStatus.reference),
  'exercise-adductor-rockback':
      _Media('adductor_rockback', ExerciseMediaStatus.reference),
  'exercise-hamstring-sweep':
      _Media('hamstring_sweep', ExerciseMediaStatus.reference),
  'exercise-ankle-dorsiflexion':
      _Media('ankle_dorsiflexion', ExerciseMediaStatus.reference),
  'exercise-easy-run': _Media('easy_run', ExerciseMediaStatus.reference),
  'exercise-tempo-run': _Media('tempo_run', ExerciseMediaStatus.reference),
  'exercise-run-walk-interval':
      _Media('run_walk_interval', ExerciseMediaStatus.reference),
  'exercise-walk-recovery':
      _Media('walk_recovery', ExerciseMediaStatus.reference),
  'exercise-hill-walk': _Media('hill_walk', ExerciseMediaStatus.reference),
  'exercise-running-strides':
      _Media('running_strides', ExerciseMediaStatus.reference),
  'exercise-hyrox-row-warmup':
      _Media('hyrox_row_warmup', ExerciseMediaStatus.reference),
  'exercise-hyrox-run-sled-push':
      _Media('hyrox_run_sled_push', ExerciseMediaStatus.precise),
  'exercise-ski-erg-pull':
      _Media('ski_erg_pull', ExerciseMediaStatus.reference),
  'exercise-wall-ball': _Media('wall_ball', ExerciseMediaStatus.reference),
  'exercise-open-book': _Media('open_book', ExerciseMediaStatus.reference),
  'exercise-jumping-jack': _Media('jumping_jack', ExerciseMediaStatus.precise),
  'exercise-burpee': _Media('burpee', ExerciseMediaStatus.precise),
  'exercise-jump-lunge': _Media('jump_lunge', ExerciseMediaStatus.precise),
  'exercise-plank-shoulder-tap':
      _Media('plank_shoulder_tap', ExerciseMediaStatus.precise),
  'exercise-plank-up-down':
      _Media('plank_up_down', ExerciseMediaStatus.precise),
  'exercise-inchworm': _Media('inchworm', ExerciseMediaStatus.precise),
  'exercise-crunch': _Media('crunch', ExerciseMediaStatus.precise),
  'exercise-bicycle-crunch':
      _Media('bicycle_crunch', ExerciseMediaStatus.precise),
  'exercise-side-plank-hip-dip':
      _Media('side_plank_hip_dip', ExerciseMediaStatus.precise),
  'exercise-side-lying-leg-raise':
      _Media('side_lying_leg_raise', ExerciseMediaStatus.precise),
  'exercise-donkey-kick': _Media('donkey_kick', ExerciseMediaStatus.precise),
  'exercise-fire-hydrant': _Media('fire_hydrant', ExerciseMediaStatus.precise),
  'exercise-wall-sit': _Media('wall_sit', ExerciseMediaStatus.precise),
  'exercise-lateral-lunge':
      _Media('lateral_lunge', ExerciseMediaStatus.precise),
  'exercise-tibialis-raise':
      _Media('tibialis_raise', ExerciseMediaStatus.precise),
  'exercise-prone-ytw': _Media('prone_ytw', ExerciseMediaStatus.precise),
  'exercise-band-internal-rotation':
      _Media('band_internal_rotation', ExerciseMediaStatus.precise),
  'exercise-breathing-9090':
      _Media('breathing_9090', ExerciseMediaStatus.precise),
  'exercise-crocodile-breathing':
      _Media('crocodile_breathing', ExerciseMediaStatus.precise),
  'exercise-downward-dog': _Media('downward_dog', ExerciseMediaStatus.precise),
  'exercise-childs-pose': _Media('childs_pose', ExerciseMediaStatus.precise),
  'exercise-supine-figure-4':
      _Media('supine_figure_4', ExerciseMediaStatus.precise),
  'exercise-standing-quad-stretch':
      _Media('standing_quad_stretch', ExerciseMediaStatus.precise),
  'exercise-seated-hamstring-stretch':
      _Media('seated_hamstring_stretch', ExerciseMediaStatus.precise),
  'exercise-butterfly-stretch':
      _Media('butterfly_stretch', ExerciseMediaStatus.precise),
  'exercise-hip-9090-switch':
      _Media('hip_9090_switch', ExerciseMediaStatus.precise),
  'exercise-incline-barbell-bench-press':
      _Media('incline_barbell_bench_press', ExerciseMediaStatus.precise),
  'exercise-smith-machine-squat':
      _Media('smith_machine_squat', ExerciseMediaStatus.precise),
  'exercise-pec-deck-fly': _Media('pec_deck_fly', ExerciseMediaStatus.precise),
  'exercise-hip-abduction-machine':
      _Media('hip_abduction_machine', ExerciseMediaStatus.precise),
  'exercise-t-bar-row': _Media('t_bar_row', ExerciseMediaStatus.precise),
  'exercise-med-ball-slam':
      _Media('med_ball_slam', ExerciseMediaStatus.precise),
};

/// 按清单为尚未配图的动作补上示范图。已内联配图的条目保持原样。
List<Exercise> applyExerciseMedia(List<Exercise> exercises) {
  return exercises.map((Exercise exercise) {
    if (exercise.mediaUrls.isNotEmpty) {
      return exercise;
    }
    final _Media? media = _exerciseMediaManifest[exercise.id];
    if (media == null) {
      return exercise;
    }
    return exercise.withMedia(
      mediaUrls: seedExerciseImages(media.slug),
      mediaStatus: media.status,
    );
  }).toList();
}
