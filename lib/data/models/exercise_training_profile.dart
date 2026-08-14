enum TrainingDimension {
  strength,
  stability,
  neural,
  eccentric,
  breathing,
}

extension TrainingDimensionJson on TrainingDimension {
  String get jsonValue => switch (this) {
        TrainingDimension.strength => 'strength',
        TrainingDimension.stability => 'stability',
        TrainingDimension.neural => 'neural',
        TrainingDimension.eccentric => 'eccentric',
        TrainingDimension.breathing => 'breathing',
      };

  String get label => switch (this) {
        TrainingDimension.strength => '力量',
        TrainingDimension.stability => '稳定',
        TrainingDimension.neural => '神经募集',
        TrainingDimension.eccentric => '离心能力',
        TrainingDimension.breathing => '呼吸',
      };
}

TrainingDimension? trainingDimensionFromJson(String? value) => switch (value) {
      'strength' => TrainingDimension.strength,
      'stability' => TrainingDimension.stability,
      'neural' => TrainingDimension.neural,
      'eccentric' => TrainingDimension.eccentric,
      'breathing' => TrainingDimension.breathing,
      _ => null,
    };

enum LegTrainingElement {
  footAnkle,
  eccentricLanding,
  dynamicStability,
  power,
}

extension LegTrainingElementJson on LegTrainingElement {
  String get jsonValue => switch (this) {
        LegTrainingElement.footAnkle => 'foot_ankle',
        LegTrainingElement.eccentricLanding => 'eccentric_landing',
        LegTrainingElement.dynamicStability => 'dynamic_stability',
        LegTrainingElement.power => 'power',
      };

  String get label => switch (this) {
        LegTrainingElement.footAnkle => '足踝基础',
        LegTrainingElement.eccentricLanding => '离心与落地',
        LegTrainingElement.dynamicStability => '动态稳定',
        LegTrainingElement.power => '爆发输出',
      };
}

LegTrainingElement? legTrainingElementFromJson(String? value) =>
    switch (value) {
      'foot_ankle' => LegTrainingElement.footAnkle,
      'eccentric_landing' => LegTrainingElement.eccentricLanding,
      'dynamic_stability' => LegTrainingElement.dynamicStability,
      'power' => LegTrainingElement.power,
      _ => null,
    };

enum ExecutionIntent {
  controlled,
  fastConcentric,
  explosive,
}

extension ExecutionIntentJson on ExecutionIntent {
  String get jsonValue => switch (this) {
        ExecutionIntent.controlled => 'controlled',
        ExecutionIntent.fastConcentric => 'fast_concentric',
        ExecutionIntent.explosive => 'explosive',
      };

  String get label => switch (this) {
        ExecutionIntent.controlled => '控制完成',
        ExecutionIntent.fastConcentric => '快速向心',
        ExecutionIntent.explosive => '爆发完成',
      };
}

ExecutionIntent executionIntentFromJson(String? value) => switch (value) {
      'fast_concentric' => ExecutionIntent.fastConcentric,
      'explosive' => ExecutionIntent.explosive,
      _ => ExecutionIntent.controlled,
    };

const String trainingStructurePolicyVersion = 'training-structure-v1';

class DimensionFocus {
  const DimensionFocus({
    this.primary = const <TrainingDimension>[],
    this.touch = const <TrainingDimension>[],
  });

  final List<TrainingDimension> primary;
  final List<TrainingDimension> touch;

  factory DimensionFocus.fromJson(Map<String, dynamic> json) {
    List<TrainingDimension> decode(Object? raw) =>
        (raw as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .map(trainingDimensionFromJson)
            .whereType<TrainingDimension>()
            .toSet()
            .toList(growable: false);

    final List<TrainingDimension> primary = decode(json['primary']);
    return DimensionFocus(
      primary: primary.take(2).toList(growable: false),
      touch: decode(json['touch'])
          .where((TrainingDimension item) => !primary.contains(item))
          .toList(growable: false),
    );
  }

  bool get isEmpty => primary.isEmpty && touch.isEmpty;

  List<TrainingDimension> get all =>
      <TrainingDimension>{...primary, ...touch}.toList(growable: false);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'primary': primary
            .map((TrainingDimension item) => item.jsonValue)
            .toList(growable: false),
        'touch': touch
            .map((TrainingDimension item) => item.jsonValue)
            .toList(growable: false),
      };
}

class ExerciseTrainingProfile {
  const ExerciseTrainingProfile({
    this.dimensions = const <TrainingDimension>[],
    this.legElements = const <LegTrainingElement>[],
    this.airborne = false,
    this.defaultIntent = ExecutionIntent.controlled,
  });

  final List<TrainingDimension> dimensions;
  final List<LegTrainingElement> legElements;
  final bool airborne;
  final ExecutionIntent defaultIntent;

  factory ExerciseTrainingProfile.fromJson(Map<String, dynamic> json) {
    final List<TrainingDimension> dimensions =
        (json['dimensions'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .map(trainingDimensionFromJson)
            .whereType<TrainingDimension>()
            .toSet()
            .toList(growable: false);
    final List<LegTrainingElement> legElements =
        (json['legElements'] as List<dynamic>? ??
                json['leg_elements'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<String>()
            .map(legTrainingElementFromJson)
            .whereType<LegTrainingElement>()
            .toSet()
            .toList(growable: false);
    return ExerciseTrainingProfile(
      dimensions: dimensions,
      legElements: legElements,
      airborne: json['airborne'] == true,
      defaultIntent: executionIntentFromJson(
        json['defaultIntent'] as String? ?? json['default_intent'] as String?,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dimensions': dimensions
            .map((TrainingDimension item) => item.jsonValue)
            .toList(growable: false),
        'legElements': legElements
            .map((LegTrainingElement item) => item.jsonValue)
            .toList(growable: false),
        'airborne': airborne,
        'defaultIntent': defaultIntent.jsonValue,
      };
}

/// 集中维护需要参与结构编排的动作画像，避免在全部动作种子中重复字段。
ExerciseTrainingProfile trainingProfileForExercise(String exerciseId) {
  return _exerciseTrainingProfiles[exerciseId] ??
      const ExerciseTrainingProfile();
}

const Map<String, ExerciseTrainingProfile> _exerciseTrainingProfiles =
    <String, ExerciseTrainingProfile>{
  'exercise-short-foot': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[TrainingDimension.stability],
    legElements: <LegTrainingElement>[LegTrainingElement.footAnkle],
  ),
  'exercise-toe-yoga': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[TrainingDimension.stability],
    legElements: <LegTrainingElement>[LegTrainingElement.footAnkle],
  ),
  'exercise-single-leg-calf-raise': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.footAnkle],
  ),
  'exercise-standing-calf-raise': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[TrainingDimension.strength],
    legElements: <LegTrainingElement>[LegTrainingElement.footAnkle],
  ),
  'exercise-ankle-dorsiflexion': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[TrainingDimension.stability],
    legElements: <LegTrainingElement>[LegTrainingElement.footAnkle],
  ),
  'exercise-single-leg-balance': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[TrainingDimension.stability],
    legElements: <LegTrainingElement>[
      LegTrainingElement.footAnkle,
      LegTrainingElement.dynamicStability,
    ],
  ),
  'exercise-seated-calf-isometric': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.footAnkle],
  ),
  'exercise-drop-landing': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.stability,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.eccentricLanding],
  ),
  'exercise-nordic-curl-eccentric': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.eccentricLanding],
  ),
  'exercise-goblet-squat': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.eccentricLanding],
  ),
  'exercise-bodyweight-squat': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.eccentricLanding],
  ),
  'exercise-rdl': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.eccentricLanding],
  ),
  'exercise-reverse-step-down': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.stability,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[
      LegTrainingElement.eccentricLanding,
      LegTrainingElement.dynamicStability,
    ],
  ),
  'exercise-single-leg-rdl': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.dynamicStability],
  ),
  'exercise-reverse-lunge': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.dynamicStability],
  ),
  'exercise-split-squat': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.dynamicStability],
  ),
  'exercise-step-up': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.dynamicStability],
  ),
  'exercise-rear-foot-elevated-split-squat': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
    ],
    legElements: <LegTrainingElement>[LegTrainingElement.dynamicStability],
  ),
  'exercise-monster-walk': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[TrainingDimension.stability],
    legElements: <LegTrainingElement>[LegTrainingElement.dynamicStability],
  ),
  'exercise-pallof-press': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.strength,
      TrainingDimension.stability,
      TrainingDimension.breathing,
    ],
  ),
  'exercise-box-jump': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.neural,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[
      LegTrainingElement.eccentricLanding,
      LegTrainingElement.power,
    ],
    airborne: true,
    defaultIntent: ExecutionIntent.explosive,
  ),
  'exercise-freehand-jump-squat': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.neural,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[
      LegTrainingElement.eccentricLanding,
      LegTrainingElement.power,
    ],
    airborne: true,
    defaultIntent: ExecutionIntent.explosive,
  ),
  'exercise-trail-depth-jump': ExerciseTrainingProfile(
    dimensions: <TrainingDimension>[
      TrainingDimension.neural,
      TrainingDimension.eccentric,
    ],
    legElements: <LegTrainingElement>[
      LegTrainingElement.eccentricLanding,
      LegTrainingElement.power,
    ],
    airborne: true,
    defaultIntent: ExecutionIntent.explosive,
  ),
};
