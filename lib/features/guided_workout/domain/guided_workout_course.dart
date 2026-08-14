import '../../../data/models/exercise_prescription.dart';

enum GuidedWorkoutCourseKind { timedCourse, functionalCircuit }

GuidedWorkoutCourseKind guidedWorkoutCourseKindFromJson(String? value) =>
    switch (value) {
      'functional_circuit' => GuidedWorkoutCourseKind.functionalCircuit,
      _ => GuidedWorkoutCourseKind.timedCourse,
    };

enum GuidedWorkoutCompletionMode { timed, repetitions }

GuidedWorkoutCompletionMode guidedWorkoutCompletionModeFromJson(
  String? value,
) => switch (value) {
      'repetitions' => GuidedWorkoutCompletionMode.repetitions,
      _ => GuidedWorkoutCompletionMode.timed,
    };

class GuidedWorkoutCatalog {
  final List<GuidedWorkoutCourse> courses;
  final List<String> errors;

  const GuidedWorkoutCatalog({
    required this.courses,
    this.errors = const <String>[],
  });

  factory GuidedWorkoutCatalog.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? rawCourses = json['courses'] as List<dynamic>?;
    if (rawCourses == null || rawCourses.isEmpty) {
      throw const FormatException('跳绳课程配置不能为空。');
    }
    final List<GuidedWorkoutCourse> courses = <GuidedWorkoutCourse>[];
    final List<String> errors = <String>[];
    for (int index = 0; index < rawCourses.length; index += 1) {
      try {
        courses.add(
          GuidedWorkoutCourse.fromJson(
            _stringMap(rawCourses[index], fieldLabel: '课程'),
          ),
        );
      } on FormatException catch (error) {
        errors.add('第 ${index + 1} 门课程：${error.message}');
      }
    }
    if (courses.isEmpty) {
      throw FormatException('没有可用的跳绳课程。${errors.join('；')}');
    }
    _ensureUniqueIds(
      courses.map((GuidedWorkoutCourse item) => item.id),
      label: '课程',
    );
    return GuidedWorkoutCatalog(
      courses: List<GuidedWorkoutCourse>.unmodifiable(courses),
      errors: List<String>.unmodifiable(errors),
    );
  }

  GuidedWorkoutCourse? findById(String id) {
    for (final GuidedWorkoutCourse course in courses) {
      if (course.id == id) return course;
    }
    return null;
  }
}

class GuidedWorkoutCourse {
  final String id;
  final String title;
  final String level;
  final String description;
  final int expectedDurationSeconds;
  final List<GuidedWorkoutPhase> phases;
  final GuidedWorkoutVoiceConfig voice;
  final GuidedWorkoutCourseKind kind;
  final List<int> roundOptions;
  final int defaultRounds;
  final List<String> preflightChecks;

  const GuidedWorkoutCourse({
    required this.id,
    required this.title,
    required this.level,
    required this.description,
    required this.expectedDurationSeconds,
    required this.phases,
    required this.voice,
    this.kind = GuidedWorkoutCourseKind.timedCourse,
    this.roundOptions = const <int>[1],
    this.defaultRounds = 1,
    this.preflightChecks = const <String>[],
  });

  factory GuidedWorkoutCourse.fromJson(Map<String, dynamic> json) {
    final String id = _requiredString(json, 'id', '课程 ID');
    final List<dynamic>? rawPhases = json['phases'] as List<dynamic>?;
    if (rawPhases == null || rawPhases.isEmpty) {
      throw FormatException('课程 $id 至少需要一个训练阶段。');
    }
    final List<GuidedWorkoutPhase> phases = rawPhases
        .map(
          (dynamic item) => GuidedWorkoutPhase.fromJson(
            _stringMap(item, fieldLabel: '训练阶段'),
          ),
        )
        .toList(growable: false);
    _ensureUniqueIds(
      phases.map((GuidedWorkoutPhase item) => item.id),
      label: '课程 $id 的阶段',
    );
    final GuidedWorkoutCourse course = GuidedWorkoutCourse(
      id: id,
      title: _requiredString(json, 'title', '课程名称'),
      level: _requiredString(json, 'level', '课程难度'),
      description: (json['description'] as String? ?? '').trim(),
      expectedDurationSeconds: _positiveInt(
        json['expectedDurationSeconds'],
        label: '课程 $id 的声明时长',
      ),
      phases: List<GuidedWorkoutPhase>.unmodifiable(phases),
      voice: GuidedWorkoutVoiceConfig.fromJson(
        _stringMap(json['voice'], fieldLabel: '语音配置'),
      ),
      kind: guidedWorkoutCourseKindFromJson(json['kind'] as String?),
      roundOptions: _roundOptions(json['roundOptions']),
      defaultRounds: (json['defaultRounds'] as num?)?.toInt() ?? 1,
      preflightChecks: (json['preflightChecks'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList(growable: false),
    );
    if (!course.roundOptions.contains(course.defaultRounds)) {
      throw FormatException('课程 $id 的默认轮数不在可选轮数中。');
    }
    if (course.kind == GuidedWorkoutCourseKind.timedCourse &&
        course.expectedDurationSeconds != course.totalDurationSeconds) {
      throw FormatException(
        '课程 $id 声明时长 ${course.expectedDurationSeconds} 秒与计算时长 '
        '${course.totalDurationSeconds} 秒不一致。',
      );
    }
    return course;
  }

  int get totalDurationSeconds => phases.fold<int>(
        0,
        (int sum, GuidedWorkoutPhase phase) => sum + phase.totalDurationSeconds,
      );

  int get exerciseSetCount => phases.fold<int>(
        0,
        (int sum, GuidedWorkoutPhase phase) => sum + phase.exerciseSetCount,
      );

  int exerciseSetCountForRounds(int rounds) =>
      exerciseSetCount * (kind == GuidedWorkoutCourseKind.functionalCircuit
          ? normalizedRounds(rounds)
          : 1);

  int normalizedRounds(int? rounds) {
    if (kind != GuidedWorkoutCourseKind.functionalCircuit) return 1;
    if (rounds != null && roundOptions.contains(rounds)) return rounds;
    return defaultRounds;
  }

  int expectedDurationSecondsForRounds(int rounds) =>
      expectedDurationSeconds *
      (kind == GuidedWorkoutCourseKind.functionalCircuit
          ? normalizedRounds(rounds)
          : 1);

  bool containsExercise(String name) {
    return phases.any(
      (GuidedWorkoutPhase phase) => phase.exercises.any(
        (GuidedWorkoutExercise exercise) => exercise.name == name,
      ),
    );
  }

  String get durationLabel {
    if (kind == GuidedWorkoutCourseKind.functionalCircuit) {
      return '$defaultRounds 轮 · 自定节奏';
    }
    return '${expectedDurationSecondsForRounds(defaultRounds) ~/ 60} 分钟';
  }

  String get levelLabel => switch (level) {
        'beginner' => '入门',
        'advanced' => '进阶',
        _ => '标准',
      };
}

class GuidedWorkoutPhase {
  final String id;
  final String name;
  final List<GuidedWorkoutExercise> exercises;

  const GuidedWorkoutPhase({
    required this.id,
    required this.name,
    required this.exercises,
  });

  factory GuidedWorkoutPhase.fromJson(Map<String, dynamic> json) {
    final String id = _requiredString(json, 'id', '阶段 ID');
    final List<dynamic>? rawExercises = json['exercises'] as List<dynamic>?;
    if (rawExercises == null || rawExercises.isEmpty) {
      throw FormatException('阶段 $id 至少需要一个动作。');
    }
    final List<GuidedWorkoutExercise> exercises = rawExercises
        .map(
          (dynamic item) => GuidedWorkoutExercise.fromJson(
            _stringMap(item, fieldLabel: '动作'),
          ),
        )
        .toList(growable: false);
    _ensureUniqueIds(
      exercises.map((GuidedWorkoutExercise item) => item.id),
      label: '阶段 $id 的动作',
    );
    return GuidedWorkoutPhase(
      id: id,
      name: _requiredString(json, 'name', '阶段名称'),
      exercises: List<GuidedWorkoutExercise>.unmodifiable(exercises),
    );
  }

  int get totalDurationSeconds => exercises.fold<int>(
        0,
        (int sum, GuidedWorkoutExercise exercise) =>
            sum + exercise.totalDurationSeconds,
      );

  int get exerciseSetCount => exercises.fold<int>(
        0,
        (int sum, GuidedWorkoutExercise exercise) => sum + exercise.repeat,
      );
}

class GuidedWorkoutExercise {
  final String id;
  final String name;
  final int durationSeconds;
  final int restSeconds;
  final int repeat;
  final String announce;
  final List<String> cues;
  final String? libraryExerciseId;
  final GuidedWorkoutCompletionMode completionMode;
  final int? targetRepetitions;
  final ExerciseRepetitionUnit repetitionUnit;

  const GuidedWorkoutExercise({
    required this.id,
    required this.name,
    required this.durationSeconds,
    required this.restSeconds,
    required this.repeat,
    required this.announce,
    required this.cues,
    this.libraryExerciseId,
    this.completionMode = GuidedWorkoutCompletionMode.timed,
    this.targetRepetitions,
    this.repetitionUnit = ExerciseRepetitionUnit.total,
  });

  factory GuidedWorkoutExercise.fromJson(Map<String, dynamic> json) {
    final String id = _requiredString(json, 'id', '动作 ID');
    final int durationSeconds = (json['durationSeconds'] as num?)?.toInt() ?? 0;
    if (durationSeconds <= 0) {
      throw FormatException('动作 $id 的动作时长必须大于 0 秒。');
    }
    final int restSeconds = (json['restSeconds'] as num?)?.toInt() ?? 0;
    if (restSeconds < 0) {
      throw FormatException('动作 $id 的休息时长不得小于 0 秒。');
    }
    final int repeat = (json['repeat'] as num?)?.toInt() ?? 0;
    if (repeat <= 0) {
      throw FormatException('动作 $id 的重复次数必须大于 0。');
    }
    final List<String> cues = (json['cues'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    final GuidedWorkoutCompletionMode completionMode =
        guidedWorkoutCompletionModeFromJson(json['completionMode'] as String?);
    final int? targetRepetitions =
        (json['targetRepetitions'] as num?)?.toInt();
    if (completionMode == GuidedWorkoutCompletionMode.repetitions &&
        (targetRepetitions == null || targetRepetitions <= 0)) {
      throw FormatException('动作 $id 的次数跟练必须声明正整数目标次数。');
    }
    return GuidedWorkoutExercise(
      id: id,
      name: _requiredString(json, 'name', '动作名称'),
      durationSeconds: durationSeconds,
      restSeconds: restSeconds,
      repeat: repeat,
      announce: (json['announce'] as String? ?? '').trim(),
      cues: List<String>.unmodifiable(cues),
      libraryExerciseId: (json['libraryExerciseId'] as String? ?? '').trim()
              .isEmpty
          ? null
          : (json['libraryExerciseId'] as String).trim(),
      completionMode: completionMode,
      targetRepetitions: targetRepetitions,
      repetitionUnit:
          exerciseRepetitionUnitFromJson(json['repetitionUnit'] as String?),
    );
  }

  int get totalDurationSeconds => (durationSeconds + restSeconds) * repeat;

  String get repetitionLabel {
    if (targetRepetitions == null) return '';
    return repetitionUnit == ExerciseRepetitionUnit.perSide
        ? '每侧 $targetRepetitions 次'
        : '$targetRepetitions 次';
  }
}

class GuidedWorkoutVoiceConfig {
  final int countdownLast;
  final bool preAnnounceOnRest;
  final double rate;
  final bool enabled;
  final String? voiceName;

  const GuidedWorkoutVoiceConfig({
    required this.countdownLast,
    required this.preAnnounceOnRest,
    required this.rate,
    required this.enabled,
    required this.voiceName,
  });

  factory GuidedWorkoutVoiceConfig.fromJson(Map<String, dynamic> json) {
    final int countdownLast = (json['countdownLast'] as num?)?.toInt() ?? 5;
    if (countdownLast < 0 || countdownLast > 10) {
      throw const FormatException('语音倒数秒数必须在 0 到 10 之间。');
    }
    final double rate = (json['rate'] as num?)?.toDouble() ?? 1;
    if (rate < 0.5 || rate > 2) {
      throw const FormatException('语音语速必须在 0.5 到 2.0 之间。');
    }
    final String voiceName = (json['voiceName'] as String? ?? '').trim();
    return GuidedWorkoutVoiceConfig(
      countdownLast: countdownLast,
      preAnnounceOnRest: json['preAnnounceOnRest'] != false,
      rate: rate,
      enabled: json['enabled'] != false,
      voiceName: voiceName.isEmpty ? null : voiceName,
    );
  }
}

Map<String, dynamic> _stringMap(
  dynamic value, {
  required String fieldLabel,
}) {
  if (value is! Map) {
    throw FormatException('$fieldLabel格式无效。');
  }
  return value.map<String, dynamic>(
    (dynamic key, dynamic item) => MapEntry<String, dynamic>(
      key.toString(),
      item,
    ),
  );
}

String _requiredString(
  Map<String, dynamic> json,
  String field,
  String label,
) {
  final String value = (json[field] as String? ?? '').trim();
  if (value.isEmpty) {
    throw FormatException('$label不能为空。');
  }
  return value;
}

int _positiveInt(dynamic value, {required String label}) {
  final int result = (value as num?)?.toInt() ?? 0;
  if (result <= 0) {
    throw FormatException('$label必须大于 0 秒。');
  }
  return result;
}

List<int> _roundOptions(dynamic raw) {
  final List<int> values = (raw as List<dynamic>? ?? const <dynamic>[1])
      .whereType<num>()
      .map((num item) => item.toInt())
      .where((int item) => item >= 1 && item <= 12)
      .toSet()
      .toList()
    ..sort();
  return List<int>.unmodifiable(values.isEmpty ? <int>[1] : values);
}

void _ensureUniqueIds(Iterable<String> ids, {required String label}) {
  final Set<String> unique = <String>{};
  for (final String id in ids) {
    if (!unique.add(id)) {
      throw FormatException('$label ID 重复：$id。');
    }
  }
}
