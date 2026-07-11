import '../data/models/knowledge_entry.dart';

class KnowledgeImportService {
  KnowledgeImportResult parse(String rawText) {
    final Map<String, String> fields = _parseFields(rawText);
    final String title = _required(fields, const ['书名', 'title']);
    final String quoteText = _required(fields, const ['引文', 'quote']);
    final String author = _value(fields, const ['作者', 'author']) ?? '手动导入';
    final String edition = _value(fields, const ['版本', 'edition']) ?? '本地导入';
    final String chapter = _value(fields, const ['章节', 'chapter']) ?? '导入片段';
    final String pageRange = _value(fields, const ['页码', 'page']) ?? 'p. ?';
    final String note =
        _value(fields, const ['适用', '原因', 'note']) ?? '待在正式书库中补充适用范围。';
    final List<KnowledgeArea> areas = _parseAreas(
      _value(fields, const ['领域', 'area']) ?? '习惯',
    );
    final DateTime now = DateTime.now();
    final String idSuffix = now.microsecondsSinceEpoch.toString();
    final TrainingBook book = TrainingBook(
      id: 'imported-book-$idSuffix',
      title: title,
      author: author,
      edition: edition,
      areas: areas,
      summary: _value(fields, const ['摘要', 'summary']) ?? '本地导入的训练知识来源。',
    );
    final BookQuote quote = BookQuote(
      id: 'imported-quote-$idSuffix',
      bookId: book.id,
      chapter: chapter,
      pageRange: pageRange,
      quote: quoteText,
      note: note,
      areas: areas,
    );

    return KnowledgeImportResult(
      book: book,
      quote: quote,
      summary: '已导入《$title》：1 本书、1 条引文，可被本地搜索命中。',
    );
  }

  Map<String, String> _parseFields(String rawText) {
    final Map<String, String> fields = {};
    for (final String rawLine in rawText.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final int colonIndex = line.indexOf(RegExp('[:：]'));
      if (colonIndex <= 0) {
        continue;
      }
      final String key = line.substring(0, colonIndex).trim().toLowerCase();
      final String value = line.substring(colonIndex + 1).trim();
      if (value.isNotEmpty) {
        fields[key] = value;
      }
    }
    return fields;
  }

  String _required(Map<String, String> fields, List<String> keys) {
    final String? value = _value(fields, keys);
    if (value == null || value.isEmpty) {
      throw FormatException('导入失败：缺少${keys.first}字段。');
    }
    return value;
  }

  String? _value(Map<String, String> fields, List<String> keys) {
    for (final String key in keys) {
      final String? value = fields[key.toLowerCase()];
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  List<KnowledgeArea> _parseAreas(String rawValue) {
    final List<KnowledgeArea> areas = [];
    for (final String item in rawValue.split(RegExp('[,，/]'))) {
      final KnowledgeArea area = _areaFromLabel(item.trim());
      if (!areas.contains(area)) {
        areas.add(area);
      }
    }
    return areas.isEmpty ? const [KnowledgeArea.habit] : areas;
  }

  KnowledgeArea _areaFromLabel(String value) {
    switch (value.toLowerCase()) {
      case '跑步':
      case 'running':
        return KnowledgeArea.running;
      case '力量':
      case 'strength':
        return KnowledgeArea.strength;
      case '恢复':
      case 'recovery':
        return KnowledgeArea.recovery;
      case '营养':
      case 'nutrition':
        return KnowledgeArea.nutrition;
      case '动作纠错':
      case 'motion':
        return KnowledgeArea.motion;
      case '习惯':
      case 'habit':
      default:
        return KnowledgeArea.habit;
    }
  }
}
