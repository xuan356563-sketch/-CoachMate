class AdaptationSignals {
  final String completionRateBand;
  final String loadTrendCode;
  final String recoveryRiskCode;
  final String? selectedDirectionCode;

  const AdaptationSignals({
    required this.completionRateBand,
    required this.loadTrendCode,
    required this.recoveryRiskCode,
    this.selectedDirectionCode,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'completion_rate_band': completionRateBand,
        'load_trend_code': loadTrendCode,
        'recovery_risk_code': recoveryRiskCode,
        if (selectedDirectionCode != null)
          'selected_direction_code': selectedDirectionCode,
      };
}
