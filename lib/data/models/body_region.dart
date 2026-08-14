import 'exercise.dart';

/// 训练部位。用于动作库的部位筛选与分组展示。
///
/// 这是一个**派生维度**：不作为 Exercise 的持久化字段，而是由
/// [bodyRegionsForExercise] 从 targetMuscles / bodyProfile.primaryMuscles
/// 推导得到，因此不影响 Exercise 的 JSON 契约与 SQLite schema。
enum BodyRegion {
  chest,
  back,
  shoulder,
  arm,
  core,
  glute,
  quad,
  hamstring,
  calf,
  fullBody,
  cardio,
}

extension BodyRegionJson on BodyRegion {
  String get jsonValue {
    switch (this) {
      case BodyRegion.chest:
        return 'chest';
      case BodyRegion.back:
        return 'back';
      case BodyRegion.shoulder:
        return 'shoulder';
      case BodyRegion.arm:
        return 'arm';
      case BodyRegion.core:
        return 'core';
      case BodyRegion.glute:
        return 'glute';
      case BodyRegion.quad:
        return 'quad';
      case BodyRegion.hamstring:
        return 'hamstring';
      case BodyRegion.calf:
        return 'calf';
      case BodyRegion.fullBody:
        return 'full_body';
      case BodyRegion.cardio:
        return 'cardio';
    }
  }

  String get label {
    switch (this) {
      case BodyRegion.chest:
        return '胸';
      case BodyRegion.back:
        return '背';
      case BodyRegion.shoulder:
        return '肩';
      case BodyRegion.arm:
        return '手臂';
      case BodyRegion.core:
        return '核心';
      case BodyRegion.glute:
        return '臀髋';
      case BodyRegion.quad:
        return '大腿前侧';
      case BodyRegion.hamstring:
        return '大腿后侧';
      case BodyRegion.calf:
        return '小腿足踝';
      case BodyRegion.fullBody:
        return '全身';
      case BodyRegion.cardio:
        return '心肺';
    }
  }

  /// 页面上的固定展示顺序：上肢 → 核心 → 下肢 → 全身 → 心肺。
  int get displayOrder {
    return BodyRegion.values.indexOf(this);
  }
}

BodyRegion bodyRegionFromJson(String? value) {
  switch (value) {
    case 'chest':
      return BodyRegion.chest;
    case 'back':
      return BodyRegion.back;
    case 'shoulder':
      return BodyRegion.shoulder;
    case 'arm':
      return BodyRegion.arm;
    case 'core':
      return BodyRegion.core;
    case 'glute':
      return BodyRegion.glute;
    case 'quad':
      return BodyRegion.quad;
    case 'hamstring':
      return BodyRegion.hamstring;
    case 'calf':
      return BodyRegion.calf;
    case 'cardio':
      return BodyRegion.cardio;
    case 'full_body':
    default:
      return BodyRegion.fullBody;
  }
}

/// 肌群关键词 → 部位。
///
/// 顺序敏感：先匹配更具体的写法。例如「胸椎」「胸廓」必须排在「胸」前面，
/// 否则胸椎活动度动作会被错判成胸大肌训练。
const List<MapEntry<String, List<BodyRegion>>> _muscleRegionRules = [
  // ---- 需要优先拦截的易混词 ----
  MapEntry('胸椎', [BodyRegion.back]),
  MapEntry('胸廓', [BodyRegion.back]),
  MapEntry('胸肩', [BodyRegion.chest, BodyRegion.shoulder]),
  MapEntry('髋屈肌', [BodyRegion.quad]),
  MapEntry('髂腰肌', [BodyRegion.quad]),
  MapEntry('髋外展', [BodyRegion.glute]),
  MapEntry('髋外旋', [BodyRegion.glute]),
  MapEntry('髋伸', [BodyRegion.glute]),
  MapEntry('髋稳定', [BodyRegion.glute]),
  MapEntry('髋部稳定', [BodyRegion.glute]),
  MapEntry('髋关节', [BodyRegion.glute]),
  MapEntry('髋部', [BodyRegion.glute]),
  MapEntry('臀腿', [BodyRegion.glute, BodyRegion.quad, BodyRegion.hamstring]),
  MapEntry('下肢耐力', [BodyRegion.cardio, BodyRegion.quad]),
  MapEntry('下肢弹性', [BodyRegion.calf, BodyRegion.quad]),
  MapEntry('下肢协调', [BodyRegion.quad, BodyRegion.calf]),
  MapEntry('下肢稳定', [BodyRegion.quad, BodyRegion.glute]),
  MapEntry('下肢', [BodyRegion.quad, BodyRegion.glute, BodyRegion.calf]),
  MapEntry('核心抗旋转', [BodyRegion.core]),

  // ---- 胸 ----
  MapEntry('胸大肌', [BodyRegion.chest]),
  MapEntry('胸', [BodyRegion.chest]),

  // ---- 背 ----
  MapEntry('背阔肌', [BodyRegion.back]),
  MapEntry('上背', [BodyRegion.back]),
  MapEntry('菱形肌', [BodyRegion.back]),
  MapEntry('斜方肌', [BodyRegion.back]),
  MapEntry('竖脊肌', [BodyRegion.back]),
  MapEntry('多裂肌', [BodyRegion.back]),
  MapEntry('脊柱', [BodyRegion.back]),
  MapEntry('后链', [BodyRegion.back, BodyRegion.glute, BodyRegion.hamstring]),
  MapEntry('背', [BodyRegion.back]),

  // ---- 肩 ----
  MapEntry('深颈屈肌', [BodyRegion.shoulder]),
  MapEntry('颈部稳定', [BodyRegion.shoulder]),
  MapEntry('肩胛', [BodyRegion.shoulder]),
  MapEntry('肩袖', [BodyRegion.shoulder]),
  MapEntry('三角肌', [BodyRegion.shoulder]),
  MapEntry('后三角', [BodyRegion.shoulder]),
  MapEntry('前锯肌', [BodyRegion.shoulder]),
  MapEntry('肩', [BodyRegion.shoulder]),

  // ---- 手臂 ----
  MapEntry('手腕', [BodyRegion.arm]),
  MapEntry('手指', [BodyRegion.arm]),
  MapEntry('肱三头肌', [BodyRegion.arm]),
  MapEntry('肱二头肌', [BodyRegion.arm]),
  MapEntry('三头肌', [BodyRegion.arm]),
  MapEntry('二头肌', [BodyRegion.arm]),
  MapEntry('前臂', [BodyRegion.arm]),
  MapEntry('握力', [BodyRegion.arm]),

  // ---- 核心 ----
  MapEntry('腹直肌', [BodyRegion.core]),
  MapEntry('腹横肌', [BodyRegion.core]),
  MapEntry('腹斜肌', [BodyRegion.core]),
  MapEntry('腹', [BodyRegion.core]),
  MapEntry('核心', [BodyRegion.core]),
  MapEntry('呼吸控制', [BodyRegion.core]),

  // ---- 臀髋 ----
  MapEntry('臀大肌', [BodyRegion.glute]),
  MapEntry('臀中肌', [BodyRegion.glute]),
  MapEntry('臀', [BodyRegion.glute]),

  // ---- 大腿前侧 ----
  MapEntry('股四头肌', [BodyRegion.quad]),
  MapEntry('股四头', [BodyRegion.quad]),

  // ---- 大腿后侧（含内收肌，同属大腿后内侧链，训练动作高度重叠）----
  MapEntry('腘绳肌', [BodyRegion.hamstring]),
  MapEntry('内收肌', [BodyRegion.hamstring]),

  // ---- 小腿足踝 ----
  MapEntry('胫骨前肌', [BodyRegion.calf]),
  MapEntry('胫后肌', [BodyRegion.calf]),
  MapEntry('腓肠肌', [BodyRegion.calf]),
  MapEntry('比目鱼肌', [BodyRegion.calf]),
  MapEntry('腓骨肌', [BodyRegion.calf]),
  MapEntry('跟腱', [BodyRegion.calf]),
  MapEntry('小腿', [BodyRegion.calf]),
  MapEntry('足踝', [BodyRegion.calf]),
  MapEntry('踝', [BodyRegion.calf]),
  MapEntry('足弓', [BodyRegion.calf]),
  MapEntry('足底', [BodyRegion.calf]),
  MapEntry('足', [BodyRegion.calf]),

  // ---- 心肺 ----
  MapEntry('心肺', [BodyRegion.cardio]),
  MapEntry('跑步经济性', [BodyRegion.cardio]),
  MapEntry('跑步协调', [BodyRegion.cardio]),
];

const Set<BodyRegion> _upperRegions = {
  BodyRegion.chest,
  BodyRegion.back,
  BodyRegion.shoulder,
  BodyRegion.arm,
};

const Set<BodyRegion> _lowerRegions = {
  BodyRegion.glute,
  BodyRegion.quad,
  BodyRegion.hamstring,
  BodyRegion.calf,
};

/// 分类兜底：肌群词表推不出部位时，按动作分类给一个合理归属。
List<BodyRegion> _fallbackRegionsForCategory(ExerciseCategory category) {
  switch (category) {
    case ExerciseCategory.endurance:
      return [BodyRegion.cardio];
    case ExerciseCategory.runningDrill:
      return [BodyRegion.cardio, BodyRegion.calf];
    case ExerciseCategory.hyrox:
      return [BodyRegion.fullBody, BodyRegion.cardio];
    case ExerciseCategory.core:
      return [BodyRegion.core];
    case ExerciseCategory.warmup:
    case ExerciseCategory.cooldown:
    case ExerciseCategory.mobility:
    case ExerciseCategory.activation:
    case ExerciseCategory.rehab:
    case ExerciseCategory.strength:
      return [BodyRegion.fullBody];
  }
}

/// 从一个肌群描述里解析出部位。命中第一条规则即返回，避免「胸椎」同时算进胸和背。
List<BodyRegion> _regionsForMuscle(String muscle) {
  for (final MapEntry<String, List<BodyRegion>> rule in _muscleRegionRules) {
    if (muscle.contains(rule.key)) {
      return rule.value;
    }
  }
  return const [];
}

/// targetMuscles 里被视为「主要肌群」的条数。
///
/// seed 的书写约定是把主要发力肌群写在前面，后面跟稳定肌与辅助系统。
/// 部位筛选只看前几个，否则「肩胛稳定肌」「握力」这类几乎无处不在的稳定肌
/// 会把深蹲、硬拉一起塞进肩和手臂的筛选结果里。
const int _primaryMuscleCount = 2;

Set<BodyRegion> _regionsForMuscles(Iterable<String> muscles) {
  final Set<BodyRegion> regions = <BodyRegion>{};
  for (final String muscle in muscles) {
    regions.addAll(_regionsForMuscle(muscle));
  }
  return regions;
}

/// 推导动作所属部位。
///
/// 筛选结果取 targetMuscles 的前 [_primaryMuscleCount] 项加上
/// bodyProfile.primaryMuscles；前几项推不出结果时退回读取全部肌群，
/// 仍然为空则按动作分类兜底。
///
/// 「全身」标签单独按**完整**肌群列表判定：只要上肢和下肢同时被覆盖
/// （波比、深蹲推举、土耳其起立等），就额外补上。
List<BodyRegion> bodyRegionsForExercise(Exercise exercise) {
  final List<String> allMuscles = <String>[
    ...exercise.targetMuscles,
    ...exercise.bodyEngineProfile.primaryMuscles,
  ];
  final List<String> primaryMuscles = <String>[
    ...exercise.targetMuscles.take(_primaryMuscleCount),
    ...exercise.bodyEngineProfile.primaryMuscles,
  ];

  Set<BodyRegion> regions = _regionsForMuscles(primaryMuscles);
  if (regions.isEmpty) {
    regions = _regionsForMuscles(allMuscles);
  }
  if (regions.isEmpty) {
    regions = _fallbackRegionsForCategory(exercise.category).toSet();
  }

  // 耐力与跑姿类动作始终带上心肺，方便按训练目的筛选。
  if (exercise.category == ExerciseCategory.endurance ||
      exercise.category == ExerciseCategory.runningDrill) {
    regions.add(BodyRegion.cardio);
  }

  final Set<BodyRegion> fullMuscleRegions = _regionsForMuscles(allMuscles);
  final bool hitsUpper = fullMuscleRegions.any(_upperRegions.contains);
  final bool hitsLower = fullMuscleRegions.any(_lowerRegions.contains);
  if (hitsUpper && hitsLower) {
    regions.add(BodyRegion.fullBody);
  }

  final List<BodyRegion> sorted = regions.toList()
    ..sort((BodyRegion a, BodyRegion b) {
      return a.displayOrder.compareTo(b.displayOrder);
    });
  return List<BodyRegion>.unmodifiable(sorted);
}

/// 把动作列表按部位分组，返回顺序与 [BodyRegion.values] 一致。
/// 一个动作可能出现在多个部位分组里（例如深蹲推举同时在腿和肩下）。
Map<BodyRegion, List<Exercise>> groupExercisesByBodyRegion(
  List<Exercise> exercises,
) {
  final Map<BodyRegion, List<Exercise>> grouped =
      <BodyRegion, List<Exercise>>{};
  for (final BodyRegion region in BodyRegion.values) {
    final List<Exercise> matched = exercises
        .where(
          (Exercise exercise) =>
              bodyRegionsForExercise(exercise).contains(region),
        )
        .toList();
    if (matched.isNotEmpty) {
      grouped[region] = matched;
    }
  }
  return grouped;
}
