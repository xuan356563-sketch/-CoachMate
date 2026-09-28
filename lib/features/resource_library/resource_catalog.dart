import '../../data/models/resource_ref.dart';
import '../../data/models/user_profile.dart';
import '../../data/seed/seed_sport_resources.dart';
import '../../plugins/sports/sport_capability_directory.dart';
import '../../services/plan_context_digest_service.dart';

class AssessmentField {
  const AssessmentField(this.id, this.label, this.unit, this.numeric);
  final String id, label, unit;
  final bool numeric;
  factory AssessmentField.fromJson(Map<String, dynamic> j) => AssessmentField(
      j['id'] as String,
      j['label'] as String,
      j['unit'] as String,
      j['numeric'] as bool);
  Map<String, dynamic> toJson() =>
      {'id': id, 'label': label, 'unit': unit, 'numeric': numeric};
}

class SportResource {
  SportResource(this.ref, this.sport, this.ownerPluginId, this.title,
      this.scope, this.source, this.reviewStatus, this.instructions);
  final ResourceRef ref;
  final MainSport sport;
  final String ownerPluginId, title, scope, source, reviewStatus;
  final List<String> instructions;
  bool get executable => reviewStatus == 'approved';
}

class AssessmentGuide extends SportResource {
  AssessmentGuide(
      super.ref,
      super.sport,
      super.ownerPluginId,
      super.title,
      super.scope,
      super.source,
      super.reviewStatus,
      super.instructions,
      this.fields);
  final List<AssessmentField> fields;
}

class TrainingPlanResource extends SportResource {
  TrainingPlanResource(super.ref, super.sport, super.ownerPluginId, super.title,
      super.scope, super.source, super.reviewStatus, super.instructions);
}

class ResourceCatalog {
  ResourceCatalog(
      {List<Map<String, dynamic>> source = seedSportResources,
      void Function()? checkActive})
      : _checkActive = checkActive {
    final ids = <String>{};
    final directory = SportCapabilityDirectory.builtIn();
    _items = List.unmodifiable(source.map((j) {
      final id = j['id'] as String;
      if (!ids.add(id)) throw const FormatException('资源标识重复');
      final sport = MainSport.values.singleWhere(
          (s) => s.jsonValue == j['sport'],
          orElse: () => throw const FormatException('资源运动代码不存在'));
      final owner = j['ownerPluginId'] as String;
      if (directory.require(sport).definition.pluginRef.id != owner) {
        throw const FormatException('资源引用了不存在或不匹配的运动策略');
      }
      final ref = ResourceRef(
          id: id,
          version: j['version'] as String,
          fingerprint:
              const PlanContextDigestService().buildCanonicalDigest(j));
      final title = j['title'] as String,
          scope = j['scope'] as String,
          origin = j['source'] as String,
          status = j['reviewStatus'] as String;
      if ([title, scope, origin].any((v) => v.trim().isEmpty) ||
          !['approved', 'pending_review', 'blocked', 'archived']
              .contains(status)) {
        throw const FormatException('资源说明或审核状态无效');
      }
      final instructions = List<String>.unmodifiable(j['instructions'] as List);
      if (j['kind'] == 'plan') {
        return TrainingPlanResource(
            ref, sport, owner, title, scope, origin, status, instructions);
      }
      if (j['kind'] != 'assessment') throw const FormatException('资源类型不受支持');
      final fields = (j['fields'] as List)
          .map((f) =>
              AssessmentField.fromJson(Map<String, dynamic>.from(f as Map)))
          .toList();
      if (fields.isEmpty ||
          fields.map((f) => f.id).toSet().length != fields.length ||
          fields.any((f) => f.id.isEmpty || f.label.isEmpty)) {
        throw const FormatException('评估字段为空或重复');
      }
      return AssessmentGuide(ref, sport, owner, title, scope, origin, status,
          instructions, List.unmodifiable(fields));
    }));
  }
  late final List<SportResource> _items;
  final void Function()? _checkActive;
  List<SportResource> list({MainSport? sport}) {
    _checkActive?.call();
    return List.unmodifiable(_items
        .where((r) => r.executable && (sport == null || r.sport == sport)));
  }

  SportResource require(String id) {
    _checkActive?.call();
    return _items.firstWhere((r) => r.ref.id == id && r.executable,
        orElse: () => throw StateError('资源不存在、未审核或已停用'));
  }
}
