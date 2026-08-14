import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_region.dart';
import 'package:trainflow_ai/data/models/exercise.dart';
import 'package:trainflow_ai/data/models/exercise_focus_profile.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/seed/seed_exercises.dart';

Exercise _byId(String id) {
  return seedExercises.singleWhere((Exercise item) => item.id == id);
}

List<Exercise> _withSport(MainSport sport) {
  return seedExercises
      .where((Exercise item) => item.sportTags.contains(sport))
      .toList();
}

void main() {
  test('动作库固定为 239 个动作，并保持 185 个可验证配图动作完整', () {
    final List<Exercise> exercisesWithMedia = seedExercises
        .where((Exercise exercise) => exercise.mediaUrls.isNotEmpty)
        .toList();
    final int imageCount = exercisesWithMedia.fold<int>(
      0,
      (int total, Exercise exercise) => total + exercise.mediaUrls.length,
    );
    final List<Exercise> pairedExercises = exercisesWithMedia
        .where((Exercise exercise) => exercise.mediaUrls.length == 2)
        .toList();
    final List<Exercise> legacySingleImageExercises = exercisesWithMedia
        .where((Exercise exercise) => exercise.mediaUrls.length == 1)
        .toList();

    expect(seedExercises, hasLength(239));
    expect(exercisesWithMedia, hasLength(185));
    expect(imageCount, 368);
    expect(pairedExercises, hasLength(183));
    expect(
      legacySingleImageExercises.map((Exercise exercise) => exercise.id),
      <String>['exercise-high-knee', 'exercise-running-side-form'],
    );
  });

  group('小肌群与功能性画像', () {
    test('焦点标签只指向真实动作，并覆盖 82 个唯一动作', () {
      final List<Exercise> focused = seedExercises
          .where((Exercise item) => !exerciseFocusProfile(item).isEmpty)
          .toList(growable: false);

      expect(focused, hasLength(82));
      expect(
        focused.where(
          (Exercise item) => exerciseFocusProfile(item)
              .tags
              .contains(ExerciseFocusTag.smallMuscle),
        ),
        isNotEmpty,
      );
      expect(
        focused.where(
          (Exercise item) => exerciseFocusProfile(item)
              .tags
              .contains(ExerciseFocusTag.functional),
        ),
        isNotEmpty,
      );
      for (final Exercise item in focused) {
        expect(exerciseFocusProfile(item).areas, isNotEmpty);
      }
    });

    test('七个焦点区域均有完整覆盖', () {
      final Map<ExerciseFocusArea, int> counts = <ExerciseFocusArea, int>{
        for (final ExerciseFocusArea area in ExerciseFocusArea.values) area: 0,
      };
      for (final Exercise item in seedExercises) {
        for (final ExerciseFocusArea area in exerciseFocusProfile(item).areas) {
          counts[area] = (counts[area] ?? 0) + 1;
        }
      }
      expect(counts[ExerciseFocusArea.shoulderNeck], greaterThanOrEqualTo(3));
      expect(
        counts[ExerciseFocusArea.rotatorCuffScapula],
        greaterThanOrEqualTo(13),
      );
      expect(counts[ExerciseFocusArea.forearmWrist], greaterThanOrEqualTo(10));
      expect(counts[ExerciseFocusArea.deepCore], greaterThanOrEqualTo(16));
      expect(counts[ExerciseFocusArea.hipStability], greaterThanOrEqualTo(19));
      expect(counts[ExerciseFocusArea.kneeControl], greaterThanOrEqualTo(15));
      expect(counts[ExerciseFocusArea.calfAnkle], greaterThanOrEqualTo(19));
    });

    test('已落地示范图的动作使用双帧，缺失素材明确降为占位', () {
      final List<String> availableIds = <String>[
        'exercise-single-leg-glute-bridge',
        'exercise-single-leg-calf-raise',
        'exercise-tibialis-raise',
      ];
      for (final String id in availableIds) {
        expect(_byId(id).mediaUrls, hasLength(2));
      }
      for (final String id in <String>[
        'exercise-peterson-step-down',
        'exercise-split-stance-bent-knee-calf-raise',
      ]) {
        expect(_byId(id).mediaUrls, isEmpty);
        expect(_byId(id).mediaStatus, ExerciseMediaStatus.placeholder);
      }
      expect(
        _byId('exercise-peterson-step-down').name,
        'Peterson 下台阶',
      );
      expect(
        _byId('exercise-split-stance-bent-knee-calf-raise').name,
        '分腿站姿屈膝提踵',
      );
    });
  });

  test('32 个补充动作全部使用已审核双帧媒体清单', () {
    final Map<String, dynamic> manifest = jsonDecode(
      File('assets/images/exercises/supplement_media_manifest.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final List<dynamic> entries = manifest['entries'] as List<dynamic>;
    expect(manifest['schema_version'], 2);
    expect(entries, hasLength(32));
    expect(
      entries
          .where(
            (dynamic entry) =>
                (entry as Map<String, dynamic>)['subject_presentation'] ==
                'male',
          )
          .length,
      16,
    );
    expect(
      entries
          .where(
            (dynamic entry) =>
                (entry as Map<String, dynamic>)['subject_presentation'] ==
                'female',
          )
          .length,
      16,
    );
    for (final Map<String, dynamic> entry
        in entries.cast<Map<String, dynamic>>()) {
      final Exercise exercise = _byId(entry['exercise_id'] as String);
      expect(exercise.mediaStatus, ExerciseMediaStatus.precise);
      expect(exercise.mediaUrls, hasLength(2));
      expect(entry['review_status'], 'approved');
      final List<dynamic> frames = entry['frames'] as List<dynamic>;
      expect(frames, hasLength(2));
      for (final Map<String, dynamic> frame
          in frames.cast<Map<String, dynamic>>()) {
        expect(File(frame['path'] as String).existsSync(), isTrue);
        expect(frame['sha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
      }
    }
  });

  test('腿部结构新增动作完整且爆发动作声明落地解锁条件', () {
    for (final String id in <String>[
      'exercise-short-foot',
      'exercise-toe-yoga',
      'exercise-drop-landing',
      'exercise-reverse-step-down',
      'exercise-single-leg-rdl',
    ]) {
      expect(_byId(id).mediaStatus, ExerciseMediaStatus.placeholder);
    }

    for (final String id in <String>[
      'exercise-freehand-jump-squat',
      'exercise-box-jump',
      'exercise-trail-depth-jump',
    ]) {
      expect(
        _byId(id).relations,
        contains(
          isA<ExerciseRelation>()
              .having(
                (ExerciseRelation item) => item.type,
                '关系类型',
                ExerciseRelationType.unlockedBy,
              )
              .having(
                (ExerciseRelation item) => item.targetExerciseId,
                '解锁动作',
                'exercise-drop-landing',
              ),
        ),
      );
    }
  });

  group('部位推导', () {
    test('每个动作至少归入一个部位', () {
      for (final Exercise exercise in seedExercises) {
        expect(
          bodyRegionsForExercise(exercise),
          isNotEmpty,
          reason: '${exercise.id} 未能推导出部位',
        );
      }
    });

    test('胸椎类动作归到背而不是胸', () {
      final List<BodyRegion> regions =
          bodyRegionsForExercise(_byId('exercise-thoracic-rotation'));
      expect(regions, contains(BodyRegion.back));
      expect(regions, isNot(contains(BodyRegion.chest)));
    });

    test('下肢复合动作归到腿臀而不是心肺', () {
      final List<BodyRegion> regions =
          bodyRegionsForExercise(_byId('exercise-goblet-squat'));
      expect(
        regions,
        containsAll(<BodyRegion>[BodyRegion.quad, BodyRegion.glute]),
      );
      expect(regions, isNot(contains(BodyRegion.cardio)));
    });

    test('稳定肌不会把下肢动作拉进上肢筛选', () {
      // 高脚杯深蹲的 targetMuscles 里有「核心」，罗马尼亚硬拉里有「竖脊肌」，
      // 但它们都不应该出现在肩或手臂的筛选结果中。
      expect(
        bodyRegionsForExercise(_byId('exercise-goblet-squat')),
        isNot(contains(BodyRegion.shoulder)),
      );
      expect(
        bodyRegionsForExercise(_byId('exercise-farmer-carry')),
        isNot(contains(BodyRegion.chest)),
      );
    });

    test('上下肢同时参与的动作会额外标记为全身', () {
      expect(
        bodyRegionsForExercise(_byId('exercise-cf-thruster')),
        contains(BodyRegion.fullBody),
      );
      expect(
        bodyRegionsForExercise(_byId('exercise-burpee-step-back')),
        contains(BodyRegion.fullBody),
      );
    });

    test('跑步类动作始终带心肺标签', () {
      for (final String id in <String>[
        'exercise-easy-run',
        'exercise-tempo-run',
        'exercise-a-skip',
        'exercise-trail-downhill-control',
      ]) {
        expect(
          bodyRegionsForExercise(_byId(id)),
          contains(BodyRegion.cardio),
          reason: '$id 应该带心肺标签',
        );
      }
    });

    test('分组结果按 BodyRegion.values 的固定顺序返回且非空', () {
      final Map<BodyRegion, List<Exercise>> grouped =
          groupExercisesByBodyRegion(seedExercises);
      expect(grouped, isNotEmpty);
      final List<int> orders =
          grouped.keys.map((BodyRegion region) => region.displayOrder).toList();
      final List<int> sorted = List<int>.from(orders)..sort();
      expect(orders, sorted);
      for (final List<Exercise> items in grouped.values) {
        expect(items, isNotEmpty);
      }
    });

    test('每个部位都有动作可用，上肢不再是空档', () {
      final Map<BodyRegion, List<Exercise>> grouped =
          groupExercisesByBodyRegion(seedExercises);
      for (final BodyRegion region in BodyRegion.values) {
        expect(
          grouped[region]?.length ?? 0,
          greaterThanOrEqualTo(5),
          reason: '${region.label} 的动作数量不足',
        );
      }
    });

    test('部位枚举的 JSON 值可以往返', () {
      for (final BodyRegion region in BodyRegion.values) {
        expect(bodyRegionFromJson(region.jsonValue), region);
        expect(region.label, isNotEmpty);
      }
    });
  });

  group('新增动作内容', () {
    test('自重、CrossFit、越野跑三条线各自有足够条目', () {
      final List<Exercise> bodyweight = seedExercises
          .where((Exercise item) => item.id.startsWith('exercise-bodyweight'))
          .toList();
      final List<Exercise> crossFit = seedExercises
          .where((Exercise item) => item.id.startsWith('exercise-cf-'))
          .toList();
      final List<Exercise> trail = seedExercises
          .where((Exercise item) => item.id.startsWith('exercise-trail-'))
          .toList();

      expect(crossFit.length, greaterThanOrEqualTo(12));
      expect(trail.length, greaterThanOrEqualTo(12));
      expect(bodyweight, isNotEmpty);
      expect(
          _withSport(MainSport.trailRunning).length, greaterThanOrEqualTo(30));
    });

    test('高技术门槛的举重动作都写明了门槛并挂了退阶', () {
      for (final String id in <String>[
        'exercise-cf-hang-power-clean',
        'exercise-cf-power-clean',
        'exercise-cf-muscle-snatch',
        'exercise-cf-thruster',
      ]) {
        final Exercise exercise = _byId(id);
        expect(
          exercise.contraindications.any(
            (String item) => item.contains('技术门槛'),
          ),
          isTrue,
          reason: '$id 缺少技术门槛说明',
        );
        expect(
          exercise.relations.any(
            (ExerciseRelation relation) =>
                relation.type == ExerciseRelationType.regression,
          ),
          isTrue,
          reason: '$id 缺少退阶动作',
        );
      }
    });

    test('所有关联动作都指向库内真实存在的 ID', () {
      final Set<String> ids =
          seedExercises.map((Exercise item) => item.id).toSet();
      for (final Exercise exercise in seedExercises) {
        for (final ExerciseRelation relation in exercise.relations) {
          expect(
            ids,
            contains(relation.targetExerciseId),
            reason: '${exercise.id} 指向了不存在的 ${relation.targetExerciseId}',
          );
          expect(relation.reason, isNotEmpty);
        }
      }
    });

    test('每个动作的步骤、常见错误和禁忌都不为空', () {
      for (final Exercise exercise in seedExercises) {
        expect(exercise.steps, isNotEmpty, reason: '${exercise.id} 缺少步骤');
        expect(
          exercise.commonMistakes,
          isNotEmpty,
          reason: '${exercise.id} 缺少常见错误',
        );
        expect(
          exercise.contraindications,
          isNotEmpty,
          reason: '${exercise.id} 缺少禁忌提示',
        );
        expect(exercise.setsAndReps, isNotEmpty);
        expect(exercise.equipment, isNotEmpty);
      }
    });
  });

  group('示范图', () {
    test('大部分动作已配图，且配图动作都是成对的两张 assets 路径', () {
      int withMedia = 0;
      for (final Exercise exercise in seedExercises) {
        if (exercise.mediaUrls.isEmpty) {
          expect(
            exercise.mediaStatus,
            ExerciseMediaStatus.placeholder,
            reason: '${exercise.id} 没有图片却不是占位状态',
          );
          continue;
        }
        withMedia += 1;
        for (final String url in exercise.mediaUrls) {
          expect(url, startsWith('assets/'));
        }
        expect(
          exercise.mediaStatus,
          isNot(ExerciseMediaStatus.placeholder),
          reason: '${exercise.id} 有图片却仍是占位状态',
        );
      }
      expect(withMedia, greaterThanOrEqualTo(140));
    });

    test('所有引用的图片文件都真实存在于 assets 目录', () {
      final List<String> missing = <String>[];
      for (final Exercise exercise in seedExercises) {
        for (final String url in exercise.mediaUrls) {
          if (!File(url).existsSync()) {
            missing.add('${exercise.id} -> $url');
          }
        }
      }
      expect(missing, isEmpty, reason: '缺失的图片文件：${missing.join('、')}');
    });
  });
}
