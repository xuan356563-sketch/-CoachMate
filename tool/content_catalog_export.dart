import 'dart:convert';
import 'package:trainflow_ai/data/seed/seed_sport_resources.dart';
import 'dart:io';

import 'package:trainflow_ai/data/models/exercise.dart';
import 'package:trainflow_ai/data/seed/seed_achievements.dart';
import 'package:trainflow_ai/data/seed/seed_body_metrics.dart';
import 'package:trainflow_ai/data/seed/seed_exercise_builder.dart';
import 'package:trainflow_ai/data/seed/seed_exercises.dart';
import 'package:trainflow_ai/data/seed/seed_knowledge_entries.dart';
import 'package:trainflow_ai/data/seed/seed_meal_guides.dart';
import 'package:trainflow_ai/data/seed/seed_motion_checks.dart';
import 'package:trainflow_ai/data/seed/seed_races.dart';
import 'package:trainflow_ai/data/seed/seed_starter_programs.dart';
import 'package:trainflow_ai/data/seed/seed_training_plans.dart';

Map<String, dynamic> buildFlutterContentSource({
  required Directory projectRoot,
}) {
  final List<Map<String, dynamic>> courses = <Map<String, dynamic>>[
    ..._readCourses(
      projectRoot,
      'assets/training/jump_rope_courses.json',
    ),
    ..._readCourses(
      projectRoot,
      'assets/training/functional_circuits.json',
    ),
  ];
  final List<Exercise> exercisesWithMedia = seedExercises
      .where((Exercise exercise) => exercise.mediaUrls.isNotEmpty)
      .toList(growable: false);
  final int pairedMediaCount = exercisesWithMedia
      .where((Exercise exercise) => exercise.mediaUrls.length == 2)
      .length;
  final int singleMediaCount = exercisesWithMedia
      .where((Exercise exercise) => exercise.mediaUrls.length == 1)
      .length;
  final int activeAiMediaExerciseCount = exercisesWithMedia.where(
    (Exercise exercise) {
      return exercise.mediaUrls.any(
        (String path) => path.startsWith('assets/images/exercises/ai-'),
      );
    },
  ).length;

  return <String, dynamic>{
    'source_schema_version': 1,
    'sport_resources': seedSportResources,
    'source_id': 'flutter_seed',
    'exercises': seedExercises
        .map((Exercise exercise) => exercise.toJson())
        .toList(growable: false),
    'guided_courses': courses,
    'training_plans':
        seedTrainingPlans.map((plan) => plan.toJson()).toList(growable: false),
    'starter_program_days': seedStarterProgramDays
        .map((day) => day.toJson())
        .toList(growable: false),
    'motion_checks':
        seedMotionChecks.map((rule) => rule.toJson()).toList(growable: false),
    'meal_guides':
        seedMealGuides.map((guide) => guide.toJson()).toList(growable: false),
    'achievements': seedAchievements
        .map((definition) => definition.toJson())
        .toList(growable: false),
    'knowledge_books':
        seedTrainingBooks.map((book) => book.toJson()).toList(growable: false),
    'knowledge_quotes':
        seedBookQuotes.map((quote) => quote.toJson()).toList(growable: false),
    'knowledge_citation_links': seedCitationLinks
        .map((citation) => citation.toJson())
        .toList(growable: false),
    'demo_fixtures': <String, dynamic>{
      'races': seedRaces.map((race) => race.toJson()).toList(growable: false),
      'body_metrics': seedBodyMetrics
          .map((metric) => metric.toJson())
          .toList(growable: false),
    },
    'statistics': <String, dynamic>{
      'exercise_count': seedExercises.length,
      'exercise_with_media_count': exercisesWithMedia.length,
      'exercise_media_file_count': exercisesWithMedia.fold<int>(
        0,
        (int total, Exercise exercise) => total + exercise.mediaUrls.length,
      ),
      'exercise_paired_media_count': pairedMediaCount,
      'exercise_single_media_count': singleMediaCount,
      'exercise_placeholder_count':
          seedExercises.length - exercisesWithMedia.length,
      'ai_demo_slug_count': seedAiDemoSlugCount,
      'active_ai_media_exercise_count': activeAiMediaExerciseCount,
      'active_exercise_demo_set': activeExerciseDemoSet.name,
    },
  };
}

List<Map<String, dynamic>> _readCourses(
  Directory projectRoot,
  String relativePath,
) {
  final File file = File('${projectRoot.path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('课程资源文件不存在：$relativePath');
  }
  final dynamic decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('课程资源根节点必须是对象。');
  }
  final dynamic courses = decoded['courses'];
  if (courses is! List<dynamic>) {
    throw FormatException('课程资源缺少 courses 数组：$relativePath');
  }
  return courses.map((dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw FormatException('课程条目必须是对象：$relativePath');
    }
    return item;
  }).toList(growable: false);
}

void main() {
  final Map<String, dynamic> source = buildFlutterContentSource(
    projectRoot: Directory.current,
  );
  stdout.writeln(jsonEncode(source));
}
