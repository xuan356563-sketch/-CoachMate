class BodyTrendOverlay {
  final String title;
  final String description;

  const BodyTrendOverlay({
    required this.title,
    required this.description,
  });
}

class BodyTrendInsightReport {
  final String windowLabel;
  final String weightTrendLabel;
  final String weightTrendDetail;
  final List<BodyTrendOverlay> overlays;
  final String milestoneLabel;
  final String milestoneDetail;
  final String fatLossProtectionLabel;
  final String fatLossProtectionDetail;

  const BodyTrendInsightReport({
    required this.windowLabel,
    required this.weightTrendLabel,
    required this.weightTrendDetail,
    required this.overlays,
    required this.milestoneLabel,
    required this.milestoneDetail,
    required this.fatLossProtectionLabel,
    required this.fatLossProtectionDetail,
  });
}
