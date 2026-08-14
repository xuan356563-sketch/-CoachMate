import 'package:trainflow_ai/services/plan_context_digest_service.dart';

const int coachContractVersion = 1;
const String coachRuleSetVersion = 'coach-rules-1.0.0';
const String coachContractHash =
    '8970f0e215ddc5b54709eb5febeef2ca506b823e4095f54be9b9d31956e078e0';

/// Coach 跨端结构统一使用规范 JSON 的 SHA-256 摘要。
class CoachDigest {
  const CoachDigest._();

  static const PlanContextDigestService _service = PlanContextDigestService();

  static String sha256(Object? value) => _service.buildCanonicalDigest(value);

  static final String emptySet = sha256(const <Object?>[]);
}

class CoachContractException implements Exception {
  const CoachContractException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CoachContractException($code): $message';
}

class CoachSourceRef {
  const CoachSourceRef({
    required this.sourceKind,
    required this.sourceLocalId,
    required this.sourceDigest,
    required this.observedAt,
    this.summaryKey,
  });

  final String sourceKind;
  final String sourceLocalId;
  final String sourceDigest;
  final DateTime observedAt;
  final String? summaryKey;

  List<String> validate() {
    final List<String> issues = <String>[];
    if (sourceKind.trim().isEmpty) issues.add('source_kind_required');
    if (sourceLocalId.trim().isEmpty) issues.add('source_local_id_required');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceDigest)) {
      issues.add('source_digest_invalid');
    }
    return issues;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'source_kind': sourceKind,
        'source_local_id': sourceLocalId,
        'source_digest': sourceDigest,
        'observed_at': observedAt.toUtc().toIso8601String(),
        'summary_key': summaryKey,
      };

  factory CoachSourceRef.fromJson(Map<String, Object?> json) => CoachSourceRef(
        sourceKind: json['source_kind']! as String,
        sourceLocalId: json['source_local_id']! as String,
        sourceDigest: json['source_digest']! as String,
        observedAt: DateTime.parse(json['observed_at']! as String),
        summaryKey: json['summary_key'] as String?,
      );
}
