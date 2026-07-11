import '../data/models/exercise.dart';
import '../data/models/workout_day.dart';

class ExerciseSubstitution {
  final String originalExerciseId;
  final String originalName;
  final String replacementExerciseId;
  final String replacementName;
  final String reason;

  const ExerciseSubstitution({
    required this.originalExerciseId,
    required this.originalName,
    required this.replacementExerciseId,
    required this.replacementName,
    required this.reason,
  });

  String get summary {
    return '$originalName → $replacementName（$reason）';
  }
}

class WorkoutSubstitutionResult {
  final WorkoutDay workout;
  final List<ExerciseSubstitution> substitutions;
  final List<String> unresolvedExerciseNames;

  const WorkoutSubstitutionResult({
    required this.workout,
    required this.substitutions,
    required this.unresolvedExerciseNames,
  });

  bool get changed => substitutions.isNotEmpty;
}

class ExerciseSubstitutionService {
  WorkoutSubstitutionResult applyNoEquipment({
    required WorkoutDay workout,
    required List<Exercise> exercises,
  }) {
    final Map<String, Exercise> exercisesById = {
      for (final Exercise exercise in exercises) exercise.id: exercise,
    };
    final List<ExerciseSubstitution> substitutions = [];
    final List<String> unresolved = [];
    final Map<String, String> names = {};
    final List<WorkoutExerciseLink> links = [];

    for (final WorkoutExerciseLink link in workout.workoutExercises) {
      final Exercise? original = exercisesById[link.exerciseId];
      if (original == null || _isNoEquipmentCompatible(original)) {
        links.add(link);
        continue;
      }

      final Exercise? replacement = _findReplacement(
        original: original,
        exercisesById: exercisesById,
      );
      if (replacement == null) {
        links.add(link);
        unresolved.add(original.name);
        continue;
      }

      final String reason = _reasonFor(original, replacement);
      substitutions.add(
        ExerciseSubstitution(
          originalExerciseId: original.id,
          originalName: original.name,
          replacementExerciseId: replacement.id,
          replacementName: replacement.name,
          reason: reason,
        ),
      );
      names[original.name] = replacement.name;
      links.add(link.copyWith(exerciseId: replacement.id));
    }

    if (substitutions.isEmpty && unresolved.isEmpty) {
      return WorkoutSubstitutionResult(
        workout: workout,
        substitutions: substitutions,
        unresolvedExerciseNames: unresolved,
      );
    }

    final List<String> notes = [
      workout.coachNotes,
      if (substitutions.isNotEmpty)
        '无器械替代已生效：${substitutions.map((ExerciseSubstitution item) => item.summary).join('；')}。',
      if (unresolved.isNotEmpty)
        '以下动作暂未找到安全的无器械替代，开始前需要人工确认：${unresolved.join('、')}。',
    ];

    return WorkoutSubstitutionResult(
      workout: workout.copyWith(
        foamRollingSteps: _replaceNames(workout.foamRollingSteps, names),
        dynamicStretchSteps: _replaceNames(workout.dynamicStretchSteps, names),
        activationSteps: _replaceNames(workout.activationSteps, names),
        warmupSteps: _replaceNames(workout.warmupSteps, names),
        mainSets: _replaceNames(workout.mainSets, names),
        accessoryWork: _replaceNames(workout.accessoryWork, names),
        cooldownSteps: _replaceNames(workout.cooldownSteps, names),
        coachNotes: notes.where((String item) => item.isNotEmpty).join('\n'),
        workoutExercises: links,
      ),
      substitutions: substitutions,
      unresolvedExerciseNames: unresolved,
    );
  }

  Exercise? _findReplacement({
    required Exercise original,
    required Map<String, Exercise> exercisesById,
  }) {
    for (final ExerciseRelation relation in original.relations) {
      if (relation.type == ExerciseRelationType.replacement ||
          relation.type == ExerciseRelationType.regression) {
        final Exercise? target = exercisesById[relation.targetExerciseId];
        if (target != null && _isNoEquipmentCompatible(target)) {
          return target;
        }
      }
    }

    final String? fallbackId = _fallbackIds[original.id];
    if (fallbackId == null) {
      return null;
    }
    final Exercise? fallback = exercisesById[fallbackId];
    return fallback != null && _isNoEquipmentCompatible(fallback)
        ? fallback
        : null;
  }

  String _reasonFor(Exercise original, Exercise replacement) {
    for (final ExerciseRelation relation in original.relations) {
      if (relation.targetExerciseId == replacement.id &&
          relation.reason.isNotEmpty) {
        return relation.reason;
      }
    }
    return '当前无器械条件，保留相近训练目的';
  }

  bool _isNoEquipmentCompatible(Exercise exercise) {
    final List<String> requiredEquipment = exercise.equipment
        .where(
          (String item) =>
              !item.contains('可选') && !item.toLowerCase().contains('optional'),
        )
        .toList();
    if (requiredEquipment.isEmpty) {
      return true;
    }
    return requiredEquipment.every((String item) {
      final String normalized = item.trim();
      const List<String> allowed = [
        '空地',
        '地面',
        '瑜伽垫',
        '墙面',
        '墙面或沙发',
        '墙面或椅子',
        '椅子',
        '沙发',
        '徒手',
        '跑步鞋',
        '舒适运动鞋',
        '平坦路线',
        '平坦地面',
        '跑道',
        '路线',
      ];
      return allowed.any(normalized.contains);
    });
  }

  List<String> _replaceNames(List<String> values, Map<String, String> names) {
    return [
      for (final String value in values)
        names.entries.fold<String>(
          value,
          (String current, MapEntry<String, String> entry) =>
              current.replaceAll(entry.key, entry.value),
        ),
    ];
  }

  static const Map<String, String> _fallbackIds = {
    'exercise-goblet-squat': 'exercise-bodyweight-squat',
    'exercise-rdl': 'exercise-good-morning',
    'exercise-lower-body-foam-roll': 'exercise-lower-body-cooldown-flow',
    'exercise-hyrox-foam-flow': 'exercise-lower-body-cooldown-flow',
    'exercise-hyrox-row-warmup': 'exercise-thoracic-rotation',
    'exercise-hyrox-run-sled-push': 'exercise-walk-recovery',
    'exercise-farmer-carry': 'exercise-bear-crawl',
    'exercise-kettlebell-swing': 'exercise-glute-bridge',
    'exercise-lateral-band-walk': 'exercise-clamshell',
    'exercise-strength-activation-flow': 'exercise-mobility-activation-flow',
  };
}
