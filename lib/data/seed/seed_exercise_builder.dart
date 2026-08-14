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

/// free-exercise-db 图片的统一路径前缀。
const String seedExerciseImageBase = 'assets/images/exercises/free-exercise-db';

/// 生成一个动作的两张示范图路径。`slug` 对应本地文件名前缀。
List<String> seedExerciseImages(String slug) {
  return <String>[
    '$seedExerciseImageBase/${slug}_0.jpg',
    '$seedExerciseImageBase/${slug}_1.jpg',
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
