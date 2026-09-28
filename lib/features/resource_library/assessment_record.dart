import '../../data/models/user_profile.dart';
import '../../data/models/resource_ref.dart';
import 'resource_catalog.dart';

class AssessmentRecord {
  AssessmentRecord(
      {required this.id,
      required this.resourceRef,
      required this.title,
      required this.sportCode,
      required this.assessedAt,
      required this.fields,
      required this.values});
  final String id, title, sportCode;
  final ResourceRef resourceRef;
  final DateTime assessedAt;
  final List<AssessmentField> fields;
  final Map<String, String> values;
  Map<String, dynamic> toJson() => {
        'id': id,
        'resourceRef': resourceRef.toJson(),
        'title': title,
        'sportCode': sportCode,
        'assessedAt': assessedAt.toIso8601String(),
        'fields': fields.map((f) => f.toJson()).toList(),
        'values': values,
        'source': 'manual'
      };
  factory AssessmentRecord.fromJson(Map<String, dynamic> j) {
    if (j['source'] != 'manual' ||
        (j['id'] as String).isEmpty ||
        (j['title'] as String).isEmpty) {
      throw const FormatException('评估记录格式无效');
    }
    final fields = (j['fields'] as List)
        .map((f) =>
            AssessmentField.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();
    final values = Map<String, String>.from(j['values'] as Map);
    AssessmentService.validate(fields, values);
    return AssessmentRecord(
        id: j['id'] as String,
        resourceRef: ResourceRef.fromJson(
            Map<String, dynamic>.from(j['resourceRef'] as Map)),
        title: j['title'] as String,
        sportCode: j['sportCode'] as String,
        assessedAt: DateTime.parse(j['assessedAt'] as String),
        fields: List.unmodifiable(fields),
        values: Map.unmodifiable(values));
  }
}

class AssessmentService {
  AssessmentService({void Function()? checkActive})
      : _checkActive = checkActive;
  final void Function()? _checkActive;
  static void validate(
      List<AssessmentField> fields, Map<String, String> values) {
    if (fields.isEmpty ||
        fields.map((f) => f.id).toSet().length != fields.length ||
        values.keys.any((id) => !fields.any((f) => f.id == id))) {
      throw const FormatException('评估字段无效');
    }
    for (final field in fields) {
      final value = values[field.id]?.trim() ?? '';
      if (value.length > 2000) throw const FormatException('单项记录不能超过 2000 字');
      if (field.numeric && value.isNotEmpty) {
        final number = double.tryParse(value);
        if (number == null || !number.isFinite || number < 0) {
          throw FormatException('${field.label}请输入不小于零的有效数字');
        }
      }
    }
    if (values.values.every((v) => v.trim().isEmpty)) {
      throw const FormatException('请至少填写一项已知信息');
    }
  }

  AssessmentRecord record(
      {required AssessmentGuide guide,
      required String id,
      required DateTime assessedAt,
      required Map<String, String> values}) {
    _checkActive?.call();
    if (!guide.executable) throw StateError('评估指引尚未审核');
    validate(guide.fields, values);
    return AssessmentRecord(
        id: id,
        resourceRef: guide.ref,
        title: guide.title,
        sportCode: guide.sport.jsonValue,
        assessedAt: assessedAt,
        fields: List.unmodifiable(guide.fields),
        values: Map.unmodifiable({
          for (final e in values.entries)
            if (e.value.trim().isNotEmpty) e.key: e.value.trim()
        }));
  }
}
