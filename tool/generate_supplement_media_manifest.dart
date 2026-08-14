import 'dart:convert';
import 'dart:io';

const String generationVersion = 'trainmate-anatomy-2026.08.02-v2';
const String mediaRoot = 'assets/images/exercises/free-exercise-db';
const String outputPath =
    'assets/images/exercises/supplement_media_manifest.json';

const Map<String, String> supplementMedia = <String, String>{
  'exercise-jumping-jack': 'jumping_jack',
  'exercise-burpee': 'burpee',
  'exercise-jump-lunge': 'jump_lunge',
  'exercise-plank-shoulder-tap': 'plank_shoulder_tap',
  'exercise-plank-up-down': 'plank_up_down',
  'exercise-inchworm': 'inchworm',
  'exercise-crunch': 'crunch',
  'exercise-bicycle-crunch': 'bicycle_crunch',
  'exercise-side-plank-hip-dip': 'side_plank_hip_dip',
  'exercise-side-lying-leg-raise': 'side_lying_leg_raise',
  'exercise-donkey-kick': 'donkey_kick',
  'exercise-fire-hydrant': 'fire_hydrant',
  'exercise-wall-sit': 'wall_sit',
  'exercise-lateral-lunge': 'lateral_lunge',
  'exercise-tibialis-raise': 'tibialis_raise',
  'exercise-prone-ytw': 'prone_ytw',
  'exercise-band-internal-rotation': 'band_internal_rotation',
  'exercise-breathing-9090': 'breathing_9090',
  'exercise-crocodile-breathing': 'crocodile_breathing',
  'exercise-downward-dog': 'downward_dog',
  'exercise-childs-pose': 'childs_pose',
  'exercise-supine-figure-4': 'supine_figure_4',
  'exercise-standing-quad-stretch': 'standing_quad_stretch',
  'exercise-seated-hamstring-stretch': 'seated_hamstring_stretch',
  'exercise-butterfly-stretch': 'butterfly_stretch',
  'exercise-hip-9090-switch': 'hip_9090_switch',
  'exercise-incline-barbell-bench-press': 'incline_barbell_bench_press',
  'exercise-smith-machine-squat': 'smith_machine_squat',
  'exercise-pec-deck-fly': 'pec_deck_fly',
  'exercise-hip-abduction-machine': 'hip_abduction_machine',
  'exercise-t-bar-row': 't_bar_row',
  'exercise-med-ball-slam': 'med_ball_slam',
};

/// 采用男性人物展示的补充动作。
///
/// 其余补充动作采用女性人物展示，保持 16:16 的素材覆盖。该信息只用于
/// 媒体审核，不代表动作仅适用于某一性别。
const Set<String> malePresentationSlugs = <String>{
  'burpee',
  'jump_lunge',
  'plank_shoulder_tap',
  'plank_up_down',
  'inchworm',
  'crunch',
  'bicycle_crunch',
  'donkey_kick',
  'wall_sit',
  'tibialis_raise',
  'prone_ytw',
  'band_internal_rotation',
  'breathing_9090',
  'crocodile_breathing',
  'supine_figure_4',
  't_bar_row',
};

void main() {
  final List<Map<String, Object>> entries = <Map<String, Object>>[];
  for (final MapEntry<String, String> item in supplementMedia.entries) {
    final List<Map<String, String>> frames = <Map<String, String>>[];
    for (int frame = 0; frame < 2; frame += 1) {
      final String path = '$mediaRoot/${item.value}_$frame.jpg';
      final File file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        stderr.writeln('媒体文件缺失或为空：$path');
        exitCode = 1;
        return;
      }
      final ProcessResult dimensions = Process.runSync(
        'sips',
        <String>['-g', 'pixelWidth', '-g', 'pixelHeight', path],
      );
      final String dimensionOutput = dimensions.stdout.toString();
      if (dimensions.exitCode != 0 ||
          !dimensionOutput.contains('pixelWidth: 720') ||
          !dimensionOutput.contains('pixelHeight: 480')) {
        stderr.writeln('媒体尺寸不是 720×480：$path');
        exitCode = 1;
        return;
      }
      final ProcessResult digest =
          Process.runSync('shasum', <String>['-a', '256', path]);
      if (digest.exitCode != 0) {
        stderr.writeln('无法计算媒体哈希：$path');
        exitCode = 1;
        return;
      }
      frames.add(<String, String>{
        'role': frame == 0 ? 'setup' : 'key_position',
        'path': path,
        'sha256': digest.stdout.toString().split(RegExp(r'\s+')).first,
      });
    }
    entries.add(<String, Object>{
      'exercise_id': item.key,
      'slug': item.value,
      'generation_version': generationVersion,
      'subject_presentation':
          malePresentationSlugs.contains(item.value) ? 'male' : 'female',
      'review_status': 'approved',
      'media_status': 'precise',
      'frames': frames,
    });
  }
  File(outputPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(<String, Object>{
          'schema_version': 2,
          'generated_at': '2026-08-02',
          'entries': entries,
        })}\n',
  );
  stdout.writeln('已校验并写入 ${entries.length} 个动作的媒体清单：$outputPath');
}
