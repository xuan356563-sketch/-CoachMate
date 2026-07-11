enum KnowledgeArea {
  running,
  strength,
  recovery,
  nutrition,
  habit,
  motion,
}

extension KnowledgeAreaJson on KnowledgeArea {
  String get jsonValue {
    switch (this) {
      case KnowledgeArea.running:
        return 'running';
      case KnowledgeArea.strength:
        return 'strength';
      case KnowledgeArea.recovery:
        return 'recovery';
      case KnowledgeArea.nutrition:
        return 'nutrition';
      case KnowledgeArea.habit:
        return 'habit';
      case KnowledgeArea.motion:
        return 'motion';
    }
  }

  String get label {
    switch (this) {
      case KnowledgeArea.running:
        return '跑步';
      case KnowledgeArea.strength:
        return '力量';
      case KnowledgeArea.recovery:
        return '恢复';
      case KnowledgeArea.nutrition:
        return '营养';
      case KnowledgeArea.habit:
        return '习惯';
      case KnowledgeArea.motion:
        return '动作纠错';
    }
  }
}

KnowledgeArea knowledgeAreaFromJson(String? value) {
  switch (value) {
    case 'running':
      return KnowledgeArea.running;
    case 'strength':
      return KnowledgeArea.strength;
    case 'recovery':
      return KnowledgeArea.recovery;
    case 'nutrition':
      return KnowledgeArea.nutrition;
    case 'habit':
      return KnowledgeArea.habit;
    case 'motion':
      return KnowledgeArea.motion;
    default:
      return KnowledgeArea.running;
  }
}

enum CitationTargetType {
  plan,
  workout,
  exercise,
  advice,
  mealGuide,
  motionCheck,
}

extension CitationTargetTypeJson on CitationTargetType {
  String get jsonValue {
    switch (this) {
      case CitationTargetType.plan:
        return 'plan';
      case CitationTargetType.workout:
        return 'workout';
      case CitationTargetType.exercise:
        return 'exercise';
      case CitationTargetType.advice:
        return 'advice';
      case CitationTargetType.mealGuide:
        return 'meal_guide';
      case CitationTargetType.motionCheck:
        return 'motion_check';
    }
  }

  String get label {
    switch (this) {
      case CitationTargetType.plan:
        return '训练计划';
      case CitationTargetType.workout:
        return '训练日';
      case CitationTargetType.exercise:
        return '动作';
      case CitationTargetType.advice:
        return 'AI 建议';
      case CitationTargetType.mealGuide:
        return '照吃卡';
      case CitationTargetType.motionCheck:
        return '动作纠错';
    }
  }
}

CitationTargetType citationTargetTypeFromJson(String? value) {
  switch (value) {
    case 'plan':
      return CitationTargetType.plan;
    case 'workout':
      return CitationTargetType.workout;
    case 'exercise':
      return CitationTargetType.exercise;
    case 'advice':
      return CitationTargetType.advice;
    case 'meal_guide':
      return CitationTargetType.mealGuide;
    case 'motion_check':
      return CitationTargetType.motionCheck;
    default:
      return CitationTargetType.plan;
  }
}

class TrainingBook {
  final String id;
  final String title;
  final String author;
  final String edition;
  final List<KnowledgeArea> areas;
  final String summary;

  const TrainingBook({
    required this.id,
    required this.title,
    required this.author,
    required this.edition,
    required this.areas,
    required this.summary,
  });

  factory TrainingBook.fromJson(Map<String, dynamic> json) {
    return TrainingBook(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      edition: json['edition'] as String? ?? '',
      areas: (json['areas'] as List<dynamic>? ?? [])
          .map((dynamic value) => knowledgeAreaFromJson(value as String?))
          .toList(),
      summary: json['summary'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'edition': edition,
      'areas': areas.map((KnowledgeArea area) => area.jsonValue).toList(),
      'summary': summary,
    };
  }
}

class BookQuote {
  final String id;
  final String bookId;
  final String chapter;
  final String pageRange;
  final String quote;
  final String note;
  final List<KnowledgeArea> areas;

  const BookQuote({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.pageRange,
    required this.quote,
    required this.note,
    required this.areas,
  });

  factory BookQuote.fromJson(Map<String, dynamic> json) {
    return BookQuote(
      id: json['id'] as String? ?? '',
      bookId: json['bookId'] as String? ?? '',
      chapter: json['chapter'] as String? ?? '',
      pageRange: json['pageRange'] as String? ?? '',
      quote: json['quote'] as String? ?? '',
      note: json['note'] as String? ?? '',
      areas: (json['areas'] as List<dynamic>? ?? [])
          .map((dynamic value) => knowledgeAreaFromJson(value as String?))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'chapter': chapter,
      'pageRange': pageRange,
      'quote': quote,
      'note': note,
      'areas': areas.map((KnowledgeArea area) => area.jsonValue).toList(),
    };
  }
}

class CitationLink {
  final String id;
  final String quoteId;
  final CitationTargetType targetType;
  final String targetId;
  final String targetTitle;
  final String reason;

  const CitationLink({
    required this.id,
    required this.quoteId,
    required this.targetType,
    required this.targetId,
    required this.targetTitle,
    required this.reason,
  });

  factory CitationLink.fromJson(Map<String, dynamic> json) {
    return CitationLink(
      id: json['id'] as String? ?? '',
      quoteId: json['quoteId'] as String? ?? '',
      targetType: citationTargetTypeFromJson(json['targetType'] as String?),
      targetId: json['targetId'] as String? ?? '',
      targetTitle: json['targetTitle'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'quoteId': quoteId,
      'targetType': targetType.jsonValue,
      'targetId': targetId,
      'targetTitle': targetTitle,
      'reason': reason,
    };
  }
}

class KnowledgeImportResult {
  final TrainingBook book;
  final BookQuote quote;
  final String summary;

  const KnowledgeImportResult({
    required this.book,
    required this.quote,
    required this.summary,
  });
}
