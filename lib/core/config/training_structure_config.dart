class TrainingStructureConfig {
  TrainingStructureConfig._();

  /// 发布构建默认关闭，内部验收时通过 dart-define 显式开启。
  static const bool enabled = bool.fromEnvironment(
    'TRAINING_STRUCTURE_V1_ENABLED',
    defaultValue: false,
  );
}
