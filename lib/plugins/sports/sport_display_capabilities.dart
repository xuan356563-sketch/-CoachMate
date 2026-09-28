import '../core/feature_contribution.dart';

/// 宿主按类型读取展示声明；专项为空表示当前没有额外专项展示能力。
class SportDisplayCapabilities {
  const SportDisplayCapabilities({
    required this.workout,
    required this.weeklyReport,
    this.specialty,
  });
  final CardContribution workout;
  final ReportContribution weeklyReport;
  final CardContribution? specialty;

  Iterable<FeatureContribution> get contributions => [
        workout,
        weeklyReport,
        if (specialty case final value?) value,
      ];
}
