/// 单组重复次数的计量方式。
enum ExerciseRepetitionUnit { total, perSide }

extension ExerciseRepetitionUnitLabel on ExerciseRepetitionUnit {
  String get jsonValue => switch (this) {
        ExerciseRepetitionUnit.total => 'total',
        ExerciseRepetitionUnit.perSide => 'per_side',
      };

  String get label => switch (this) {
        ExerciseRepetitionUnit.total => '次',
        ExerciseRepetitionUnit.perSide => '每侧',
      };
}

ExerciseRepetitionUnit exerciseRepetitionUnitFromJson(String? value) =>
    switch (value) {
      'per_side' => ExerciseRepetitionUnit.perSide,
      _ => ExerciseRepetitionUnit.total,
    };
