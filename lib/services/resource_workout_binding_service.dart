import '../data/models/workout_day.dart';
import '../data/models/user_profile.dart';
import '../data/models/training_plan.dart';
import '../data/seed/seed_exercises.dart';
import 'exercise_substitution_service.dart';

/// 给现有资源处方补充动作导航；不从其他课程复制组次或改写处方。
/// 未建立映射的内容留空，由完整审核阻止启用。
class ResourceWorkoutBindingService {
  const ResourceWorkoutBindingService();

  List<String> issues(TrainingPlan plan, UserProfile profile) {
    final issues = <String>[];
    for (final day in plan.workoutDays) {
      for (final text in [...day.mainSets, ...day.accessoryWork]) {
        if (_ids(text, day.trainingType).isEmpty) {
          issues.add('${day.title}的「$text」尚无明确动作关联，请调整档案或选择其他适用模板。');
        }
      }
      if (profile.equipmentAccessType == EquipmentAccessType.none ||
          profile.equipmentAccessType == EquipmentAccessType.basicHome) {
        final checked = ExerciseSubstitutionService()
            .applyNoEquipment(workout: day, exercises: seedExercises);
        if (checked.substitutions.isNotEmpty ||
            checked.unresolvedExerciseNames.isNotEmpty) {
          issues.add('${day.title}的动作需要核实器械；当前资源不自动替换原处方。');
        }
      }
    }
    return issues;
  }

  WorkoutDay bind(WorkoutDay workout, List<WorkoutExerciseLink> compiled) {
    final links = <WorkoutExerciseLink>[
      ...compiled.where((l) =>
          l.module != WorkoutExerciseModule.mainTraining &&
          l.module != WorkoutExerciseModule.accessory &&
          l.module != WorkoutExerciseModule.hipDrive &&
          l.module != WorkoutExerciseModule.calf),
    ];
    void append(String text, WorkoutExerciseModule module, {List<String>? references}) {
      final ids = references ?? _ids(text, workout.trainingType);
      for (final id in ids) {
        links.add(WorkoutExerciseLink(
          id: '${workout.id}-resource-${links.length}',
          exerciseId: id,
          sequence: links.length + 1,
          module: module,
          plannedSetCount: int.tryParse(
                  RegExp(r'(\d+)\s*组').firstMatch(text)?.group(1) ?? '') ??
              0,
          repetitionsPerSet: 0,
          plannedWeightOrIntensity: text,
          restSeconds: 0,
        ));
      }
    }

    // 原跑步准备文本已经包含这些动作；只补登记专项归属，不复制编译器的额外次数。
    for (final text in workout.dynamicStretchSteps.where((s) => s.contains('高抬腿'))) {
      append(text, WorkoutExerciseModule.hipDrive, references: ['exercise-high-knee']);
    }
    for (final text in workout.activationSteps.where((s) => s.contains('提踵'))) {
      append(text, WorkoutExerciseModule.calf, references: ['exercise-standing-calf-raise']);
    }
    for (final text in workout.mainSets) {
      append(text, WorkoutExerciseModule.mainTraining);
    }
    for (final text in workout.accessoryWork) {
      append(text, WorkoutExerciseModule.accessory);
    }
    return workout.copyWith(workoutExercises: [
      for (var i = 0; i < links.length; i++) links[i].copyWith(sequence: i + 1),
    ]);
  }

  List<String> _ids(String text, TrainingType type) {
    if (text.contains('深蹲模式') || text.contains('下肢主动作')) {
      return ['exercise-goblet-squat'];
    }
    if (text.contains('髋铰链模式')) return ['exercise-rdl'];
    if (text.contains('核心抗旋转')) return ['exercise-pallof-press'];
    if (text.contains('核心稳定') || text.contains('核心动作')) {
      return ['exercise-dead-bug'];
    }
    if (text.contains('单腿稳定')) return ['exercise-reverse-lunge'];
    if (text.contains('水平推') || text.contains('上肢主动作')) {
      return ['exercise-incline-push-up'];
    }
    if (text.contains('水平拉')) return ['exercise-seated-cable-row'];
    if (text.contains('肩胛稳定')) return ['exercise-scapular-push-up'];
    if (text.contains('负重行走')) return ['exercise-farmer-carry'];
    if (text.contains('蹲、推、拉')) {
      return [
        'exercise-goblet-squat',
        'exercise-incline-push-up',
        'exercise-seated-cable-row'
      ];
    }
    if (text.contains('划船机技术')) return ['exercise-hyrox-row-warmup'];
    if (text.contains('墙球')) return ['exercise-wall-ball'];
    if (text.contains('波比')) return ['exercise-burpee'];
    if (text.contains('活动度')) return ['exercise-hip-mobility-flow'];
    if (text.contains('节奏跑')) return ['exercise-tempo-run'];
    if (text.contains('轻松跑') ||
        text.contains('慢跑') ||
        text.contains('短加速') ||
        text.contains('全程保守完成')) {
      return ['exercise-easy-run'];
    }
    // 无明确动作的循环、恢复和状态提示不猜测成训练课程。
    return const [];
  }
}
