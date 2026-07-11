class TrustReviewItem {
  final String title;
  final String detail;
  final String evidenceLabel;

  const TrustReviewItem({
    required this.title,
    required this.detail,
    required this.evidenceLabel,
  });
}

class UserTrustReviewReport {
  final String predictionAccuracyLabel;
  final String predictionAccuracyDetail;
  final String uncertaintyLabel;
  final String uncertaintyDetail;
  final String dataOwnershipLabel;
  final String dataOwnershipDetail;
  final List<TrustReviewItem> reviewItems;

  const UserTrustReviewReport({
    required this.predictionAccuracyLabel,
    required this.predictionAccuracyDetail,
    required this.uncertaintyLabel,
    required this.uncertaintyDetail,
    required this.dataOwnershipLabel,
    required this.dataOwnershipDetail,
    required this.reviewItems,
  });
}
