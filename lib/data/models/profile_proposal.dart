import 'ai_artifact.dart';

class ProfileProposalRequest {
  final String requestId;
  final Map<String, dynamic> knownFields;
  final List<String> unresolvedFieldCodes;
  final List<String> ambiguityFragments;

  const ProfileProposalRequest({
    required this.requestId,
    required this.knownFields,
    required this.unresolvedFieldCodes,
    required this.ambiguityFragments,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contract_version': 1,
        'request_id': requestId,
        'known_fields': knownFields,
        'unresolved_field_codes': unresolvedFieldCodes,
        'ambiguity_fragments': ambiguityFragments,
      };
}

class ProposedProfileField {
  final String fieldCode;
  final Object value;
  final double confidence;

  const ProposedProfileField({
    required this.fieldCode,
    required this.value,
    required this.confidence,
  });

  factory ProposedProfileField.fromJson(Map<String, dynamic> json) {
    final Object? rawValue = json['value'];
    if (rawValue is! String && rawValue is! int && rawValue is! List) {
      throw const FormatException('画像提议字段值无效');
    }
    return ProposedProfileField(
      fieldCode: json['field_code'] as String? ?? '',
      value: rawValue!,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ProfileProposal {
  final String artifactId;
  final bool isPending;
  final List<ProposedProfileField> proposedFields;
  final List<String> missingFieldCodes;
  final List<String> followUpCodes;
  final String generationMode;

  const ProfileProposal({
    required this.artifactId,
    required this.isPending,
    required this.proposedFields,
    required this.missingFieldCodes,
    required this.followUpCodes,
    required this.generationMode,
  });

  factory ProfileProposal.fromArtifact(AiArtifact artifact) {
    if (artifact.artifactType != 'profile_proposal_v1' ||
        artifact.schemaVersion != 1 ||
        !artifact.isPending) {
      throw const FormatException('画像提议产物状态无效');
    }
    final Object? rawFields = artifact.payload['proposed_fields'];
    final Object? rawMissing = artifact.payload['missing_field_codes'];
    final Object? rawFollowUps = artifact.payload['follow_up_codes'];
    final Object? rawMeta = artifact.payload['generation_meta'];
    if (rawFields is! List ||
        rawMissing is! List ||
        rawFollowUps is! List ||
        rawMeta is! Map) {
      throw const FormatException('画像提议产物结构无效');
    }
    final List<ProposedProfileField> fields = rawFields
        .whereType<Map>()
        .map(
          (Map<dynamic, dynamic> value) => ProposedProfileField.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList(growable: false);
    if (fields.any(
      (ProposedProfileField field) =>
          !_allowedProfileFields.contains(field.fieldCode) ||
          field.confidence < 0 ||
          field.confidence > 1,
    )) {
      throw const FormatException('画像提议包含未授权字段');
    }
    return ProfileProposal(
      artifactId: artifact.id,
      isPending: artifact.isPending,
      proposedFields: fields,
      missingFieldCodes: rawMissing.whereType<String>().toList(growable: false),
      followUpCodes:
          rawFollowUps.whereType<String>().take(5).toList(growable: false),
      generationMode:
          Map<String, dynamic>.from(rawMeta)['generation_mode'] as String? ??
              'local_safe_fallback',
    );
  }
}

const Set<String> _allowedProfileFields = <String>{
  'goal',
  'primary_sport',
  'experience_level',
  'weekly_training_days',
  'available_minutes',
  'equipment_access',
};
