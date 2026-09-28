/// 内置功能的登记元数据，由现有 Flutter 路由与页面装配读取。
sealed class FeatureContribution {
  const FeatureContribution({required this.id, required this.label});
  final String id;
  final String label;
}

final class RouteContribution extends FeatureContribution {
  const RouteContribution(
      {required super.id, required super.label, required this.path});
  final String path;
}

final class NavigationContribution extends FeatureContribution {
  const NavigationContribution(
      {required super.id,
      required super.label,
      required this.routeId,
      this.order = 0});
  final String routeId;
  final int order;
}

final class CardContribution extends FeatureContribution {
  const CardContribution(
      {required super.id,
      required super.label,
      required this.slot,
      this.order = 0});
  final String slot;
  final int order;
}

final class FormContribution extends FeatureContribution {
  const FormContribution(
      {required super.id, required super.label, required this.formId});
  final String formId;
}

final class ReportContribution extends FeatureContribution {
  const ReportContribution(
      {required super.id,
      required super.label,
      required this.reportId,
      this.order = 0});
  final String reportId;
  final int order;
}
