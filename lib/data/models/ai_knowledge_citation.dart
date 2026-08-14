enum AiKnowledgeCitationType { principle, trainingTemplate }

extension AiKnowledgeCitationTypeJson on AiKnowledgeCitationType {
  String get jsonValue => switch (this) {
        AiKnowledgeCitationType.principle => 'principle',
        AiKnowledgeCitationType.trainingTemplate => 'training_template',
      };
}

/// AI 处方所使用的审核知识条目，与本地动作证据来源相互独立。
class AiKnowledgeCitation {
  final String id;
  final AiKnowledgeCitationType type;
  final String title;
  final String sourceLabel;
  final String sourceSection;
  final String contentVersion;

  const AiKnowledgeCitation({
    required this.id,
    required this.type,
    required this.title,
    required this.sourceLabel,
    required this.sourceSection,
    required this.contentVersion,
  });

  factory AiKnowledgeCitation.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String? ?? '';
    final String title = json['title'] as String? ?? '';
    final String sourceLabel = json['source_label'] as String? ?? '';
    final String sourceSection = json['source_section'] as String? ?? '';
    final String contentVersion = json['content_version'] as String? ?? '';
    final AiKnowledgeCitationType type = switch (json['type']) {
      'principle' => AiKnowledgeCitationType.principle,
      'training_template' => AiKnowledgeCitationType.trainingTemplate,
      _ => throw const FormatException('训练知识引用类型不受支持'),
    };
    if (id.isEmpty ||
        title.isEmpty ||
        sourceLabel.isEmpty ||
        sourceSection.isEmpty ||
        contentVersion.isEmpty) {
      throw const FormatException('训练知识引用内容不完整');
    }
    return AiKnowledgeCitation(
      id: id,
      type: type,
      title: title,
      sourceLabel: sourceLabel,
      sourceSection: sourceSection,
      contentVersion: contentVersion,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.jsonValue,
        'title': title,
        'source_label': sourceLabel,
        'source_section': sourceSection,
        'content_version': contentVersion,
      };
}
