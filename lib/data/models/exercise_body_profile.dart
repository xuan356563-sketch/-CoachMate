class ExerciseBodyProfile {
  final String movementPattern;
  final List<String> involvedJoints;
  final List<String> primaryMuscles;
  final List<String> stabilizerMuscles;
  final List<String> commonCompensations;
  final List<String> riskAreas;

  const ExerciseBodyProfile({
    required this.movementPattern,
    required this.involvedJoints,
    required this.primaryMuscles,
    required this.stabilizerMuscles,
    required this.commonCompensations,
    required this.riskAreas,
  });

  bool get isStructured {
    return movementPattern.isNotEmpty &&
        involvedJoints.isNotEmpty &&
        primaryMuscles.isNotEmpty;
  }

  String get bodyEngineSummary {
    if (!isStructured) {
      return '该动作暂未完成结构化身体知识建档。';
    }
    return [
      '动作模式：$movementPattern',
      '涉及关节：${involvedJoints.join('、')}',
      '主要肌群：${primaryMuscles.join('、')}',
      '稳定肌群：${stabilizerMuscles.join('、')}',
      '风险区域：${riskAreas.join('、')}',
    ].join('；');
  }

  factory ExerciseBodyProfile.fromJson(Map<String, dynamic> json) {
    return ExerciseBodyProfile(
      movementPattern: json['movementPattern'] as String? ?? '',
      involvedJoints:
          List<String>.from(json['involvedJoints'] as List<dynamic>? ?? []),
      primaryMuscles:
          List<String>.from(json['primaryMuscles'] as List<dynamic>? ?? []),
      stabilizerMuscles: List<String>.from(
        json['stabilizerMuscles'] as List<dynamic>? ?? [],
      ),
      commonCompensations: List<String>.from(
        json['commonCompensations'] as List<dynamic>? ?? [],
      ),
      riskAreas: List<String>.from(json['riskAreas'] as List<dynamic>? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'movementPattern': movementPattern,
      'involvedJoints': involvedJoints,
      'primaryMuscles': primaryMuscles,
      'stabilizerMuscles': stabilizerMuscles,
      'commonCompensations': commonCompensations,
      'riskAreas': riskAreas,
    };
  }
}

ExerciseBodyProfile bodyProfileForExercise(String exerciseId) {
  switch (exerciseId) {
    case 'exercise-goblet-squat':
      return const ExerciseBodyProfile(
        movementPattern: '双侧膝主导蹲',
        involvedJoints: ['髋', '膝', '踝', '胸椎'],
        primaryMuscles: ['股四头肌', '臀大肌'],
        stabilizerMuscles: ['核心', '臀中肌', '足弓稳定肌'],
        commonCompensations: ['膝内扣', '脚跟离地', '躯干过度前倾'],
        riskAreas: ['膝关节', '腰背'],
      );
    case 'exercise-rdl':
      return const ExerciseBodyProfile(
        movementPattern: '髋铰链',
        involvedJoints: ['髋', '膝', '腰椎', '胸椎'],
        primaryMuscles: ['臀大肌', '腘绳肌'],
        stabilizerMuscles: ['核心', '背阔肌', '足底'],
        commonCompensations: ['腰椎弯曲', '膝盖锁死', '重量远离身体'],
        riskAreas: ['腰背', '腘绳肌'],
      );
    case 'exercise-reverse-lunge':
      return const ExerciseBodyProfile(
        movementPattern: '单侧膝主导蹲',
        involvedJoints: ['髋', '膝', '踝', '骨盆'],
        primaryMuscles: ['股四头肌', '臀大肌'],
        stabilizerMuscles: ['臀中肌', '核心', '足踝'],
        commonCompensations: ['前膝内扣', '骨盆侧倾', '后脚蹬地借力'],
        riskAreas: ['膝关节', '踝关节'],
      );
    case 'exercise-incline-push-up':
      return const ExerciseBodyProfile(
        movementPattern: '水平推 + 核心抗伸展',
        involvedJoints: ['肩', '肘', '腕', '胸椎', '腰椎'],
        primaryMuscles: ['胸大肌', '肱三头肌'],
        stabilizerMuscles: ['前锯肌', '核心', '臀肌'],
        commonCompensations: ['塌腰', '耸肩', '肘部完全外展'],
        riskAreas: ['肩前侧', '腕部', '腰背'],
      );
    case 'exercise-plank':
      return const ExerciseBodyProfile(
        movementPattern: '核心抗伸展',
        involvedJoints: ['肩', '肘', '胸椎', '腰椎', '髋'],
        primaryMuscles: ['腹横肌', '腹直肌'],
        stabilizerMuscles: ['肩胛稳定肌', '臀大肌', '股四头肌'],
        commonCompensations: ['腰椎塌陷', '翘臀', '耸肩'],
        riskAreas: ['腰椎', '肩关节'],
      );
    case 'exercise-standing-calf-raise':
      return const ExerciseBodyProfile(
        movementPattern: '踝跖屈',
        involvedJoints: ['踝', '跖趾', '膝'],
        primaryMuscles: ['腓肠肌', '比目鱼肌'],
        stabilizerMuscles: ['足底稳定肌', '胫骨后肌', '臀中肌'],
        commonCompensations: ['踝内翻', '踝外翻', '下降过快'],
        riskAreas: ['跟腱', '足底', '小腿'],
      );
    case 'exercise-high-knee':
      return const ExerciseBodyProfile(
        movementPattern: '跑步抬腿与单脚支撑',
        involvedJoints: ['髋', '膝', '踝', '胸椎'],
        primaryMuscles: ['髂腰肌', '股四头肌', '小腿'],
        stabilizerMuscles: ['核心', '臀中肌', '足踝'],
        commonCompensations: ['身体后仰', '脚掌砸地', '骨盆失控'],
        riskAreas: ['小腿', '髋屈肌', '足踝'],
      );
    case 'exercise-running-side-form':
      return const ExerciseBodyProfile(
        movementPattern: '跑步步态与单脚落地',
        involvedJoints: ['髋', '膝', '踝', '脊柱'],
        primaryMuscles: ['髋伸肌群', '小腿'],
        stabilizerMuscles: ['核心', '臀中肌', '肩胛稳定肌'],
        commonCompensations: ['跨步过大', '身体后仰', '脚跟重砸地'],
        riskAreas: ['小腿', '跟腱', '膝部'],
      );
    case 'exercise-box-squat':
      return const ExerciseBodyProfile(
        movementPattern: '受限深度双侧蹲',
        involvedJoints: ['髋', '膝', '踝'],
        primaryMuscles: ['股四头肌', '臀大肌'],
        stabilizerMuscles: ['核心', '臀中肌'],
        commonCompensations: ['完全放松坐下', '膝内扣', '借惯性弹起'],
        riskAreas: ['膝关节', '腰背'],
      );
    case 'exercise-seated-calf-isometric':
      return const ExerciseBodyProfile(
        movementPattern: '坐姿踝跖屈等长',
        involvedJoints: ['踝', '跖趾', '膝'],
        primaryMuscles: ['比目鱼肌', '腓肠肌'],
        stabilizerMuscles: ['足底稳定肌'],
        commonCompensations: ['疼痛范围内硬顶', '脚踝偏移', '屏住呼吸'],
        riskAreas: ['跟腱', '足底', '小腿'],
      );
    default:
      return const ExerciseBodyProfile(
        movementPattern: '',
        involvedJoints: [],
        primaryMuscles: [],
        stabilizerMuscles: [],
        commonCompensations: [],
        riskAreas: [],
      );
  }
}
