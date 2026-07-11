class TrainingLoadCurvePoint {
  final String label;
  final double dailyLoadScore;
  final double ctlScore;
  final double atlScore;
  final double tsbScore;

  const TrainingLoadCurvePoint({
    required this.label,
    required this.dailyLoadScore,
    required this.ctlScore,
    required this.atlScore,
    required this.tsbScore,
  });
}
