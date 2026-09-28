import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/seed/seed_sport_resources.dart';
import 'package:trainflow_ai/features/resource_library/resource_catalog.dart';
import 'package:trainflow_ai/features/resource_library/assessment_record.dart';
import 'package:trainflow_ai/features/resource_library/resource_plan_preview.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/features/resource_library_plugin.dart';

void main() {
  test('八份资源按运动成对登记，指纹稳定且只开放已审核内容', () {
    final catalog = ResourceCatalog();
    expect(catalog.list(), hasLength(8));
    expect(catalog.list().whereType<AssessmentGuide>(), hasLength(4));
    expect(catalog.list().whereType<TrainingPlanResource>(), hasLength(4));
    expect(catalog.list().first.ref, ResourceCatalog().list().first.ref);
    final pending = {
      ...seedSportResources.first,
      'reviewStatus': 'pending_review'
    };
    expect(ResourceCatalog(source: [pending]).list(), isEmpty);
    expect(
        () =>
            ResourceCatalog(source: [pending]).require(pending['id'] as String),
        throwsStateError);
  });
  test('重复标识和错配策略拒绝装配', () {
    expect(
        () => ResourceCatalog(
            source: [seedSportResources.first, seedSportResources.first]),
        throwsFormatException);
    expect(
        () => ResourceCatalog(source: [
              {...seedSportResources.first, 'ownerPluginId': 'sport.strength'}
            ]),
        throwsFormatException);
  });
  test('字段或说明变化影响资源指纹', () {
    final changed = {...seedSportResources.first, 'scope': '新的适用说明'};
    expect(ResourceCatalog(source: [changed]).list().first.ref,
        isNot(ResourceCatalog().list().first.ref));
  });
  test('真实技能装配且停用后旧对象不可继续调用，运动无强依赖', () async {
    final registry = PluginRegistry(plugins: builtInDistribution());
    expect((await registry.initialize()).isSuccess, isTrue);
    final catalog = registry
        .readCapability<ResourceCatalog>(ResourceLibraryPlugin.catalog)!;
    expect(
        registry.readCapability<AssessmentService>(
            ResourceLibraryPlugin.assessment),
        isNotNull);
    expect(
        registry
            .readCapability<ResourcePlanPreview>(ResourceLibraryPlugin.preview),
        isNotNull);
    for (final id in [
      'sport.marathon',
      'sport.trail_running',
      'sport.strength',
      'sport.hyrox'
    ]) {
      final descriptor = registry.descriptors[id]!;
      expect(
          descriptor.dependencies, isNot(contains(ResourceLibraryPlugin.id)));
      expect(
          descriptor.workflows
              .any((w) => w.ownerPluginId == ResourceLibraryPlugin.id),
          isTrue);
    }
    await registry.shutdown();
    expect(catalog.list, throwsA(isA<PluginException>()));
    registry.dispose();
  });
}
