enum EvidenceSourceType {
  book,
  paper,
  coachExperience,
  athleteCase,
  internalRule,
}

extension EvidenceSourceTypeJson on EvidenceSourceType {
  String get jsonValue {
    switch (this) {
      case EvidenceSourceType.book:
        return 'book';
      case EvidenceSourceType.paper:
        return 'paper';
      case EvidenceSourceType.coachExperience:
        return 'coach_experience';
      case EvidenceSourceType.athleteCase:
        return 'athlete_case';
      case EvidenceSourceType.internalRule:
        return 'internal_rule';
    }
  }

  String get label {
    switch (this) {
      case EvidenceSourceType.book:
        return '书籍';
      case EvidenceSourceType.paper:
        return '论文';
      case EvidenceSourceType.coachExperience:
        return '教练经验';
      case EvidenceSourceType.athleteCase:
        return '运动员案例';
      case EvidenceSourceType.internalRule:
        return '内部规则';
    }
  }
}

EvidenceSourceType evidenceSourceTypeFromJson(String? value) {
  switch (value) {
    case 'book':
      return EvidenceSourceType.book;
    case 'paper':
      return EvidenceSourceType.paper;
    case 'coach_experience':
      return EvidenceSourceType.coachExperience;
    case 'athlete_case':
      return EvidenceSourceType.athleteCase;
    case 'internal_rule':
      return EvidenceSourceType.internalRule;
    default:
      return EvidenceSourceType.internalRule;
  }
}

class EvidenceSource {
  final String id;
  final String title;
  final String author;
  final EvidenceSourceType sourceType;
  final String? chapter;
  final String? pageRange;
  final String? doi;
  final String quote;
  final String note;

  const EvidenceSource({
    required this.id,
    required this.title,
    required this.author,
    required this.sourceType,
    this.chapter,
    this.pageRange,
    this.doi,
    required this.quote,
    required this.note,
  });

  String get citationLabel {
    final List<String> parts = [
      title,
      if (chapter != null && chapter!.isNotEmpty) chapter!,
      if (pageRange != null && pageRange!.isNotEmpty) pageRange!,
      if (doi != null && doi!.isNotEmpty) 'DOI $doi',
    ];
    return parts.join(' · ');
  }

  factory EvidenceSource.fromJson(Map<String, dynamic> json) {
    return EvidenceSource(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      sourceType: evidenceSourceTypeFromJson(json['sourceType'] as String?),
      chapter: json['chapter'] as String?,
      pageRange: json['pageRange'] as String?,
      doi: json['doi'] as String?,
      quote: json['quote'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'sourceType': sourceType.jsonValue,
      'chapter': chapter,
      'pageRange': pageRange,
      'doi': doi,
      'quote': quote,
      'note': note,
    };
  }
}
