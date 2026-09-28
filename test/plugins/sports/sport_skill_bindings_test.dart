import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/sports/built_in_sport_plugins.dart';
import 'package:trainflow_ai/plugins/application/sport_skill_binding.dart';
import 'package:trainflow_ai/features/ai_center/data/training_prescription_api_models.dart';

void main() {
  test('七项能力声明真实本地技能，六项云端绑定匹配审核主清单', () async {
    final manifest = jsonDecode(
        File('backend/app/ai_skills/training-plan-builder/trainmate.skill.json')
            .readAsStringSync()) as Map<String, dynamic>;
    final cloud = TrainingPrescriptionSkillCapability.fromJson({
      'id': manifest['id'],
      'version': manifest['version'],
      'display_name': manifest['display_name'],
      'sports': manifest['sports'],
      'source_sha256': manifest['source_sha256'],
      'runtime_sha256': manifest['runtime_sha256'],
      'fragment_sha256': manifest['fragment_sha256'],
    });
    final capabilities = TrainingPrescriptionCapabilities(
        enabled: true, contractVersion: 1, skills: [cloud]);
    final registry = PluginRegistry(plugins: builtInDistribution());
    expect((await registry.initialize()).isSuccess, isTrue);
    addTearDown(() async {
      await registry.shutdown();
      registry.dispose();
    });
    for (final plugin in builtInSportPlugins()) {
      final descriptor = registry.descriptors[plugin.descriptor.id]!;
      final local = descriptor.skills
          .where((s) => s.execution == SkillExecution.local)
          .single;
      expect(local.ownerPluginId, descriptor.id);
      expect(local.version, descriptor.version);
      expect(registry.readCapability<Object>(local.capabilityId!), isNotNull);
      if (descriptor.id == 'support.rehab') {
        expect(descriptor.skills, hasLength(1));
        expect(cloudSportSkillBlocker(descriptor, capabilities),
            contains('未声明云端'));
      } else {
        final skill = descriptor.skills
            .where((s) => s.execution == SkillExecution.cloud)
            .single;
        expect(skill.id, cloud.id);
        expect(skill.sportCode, plugin.strategy.definition.sport.jsonValue);
        expect(plugin.strategy.definition.cloudSupported, isTrue);
        expect(cloudSportSkillBlocker(descriptor, capabilities), isNull);
        expect(
            (manifest['sport_fragments'] as Map).containsKey(skill.sportCode),
            skill.fragmentKey != null);
      }
    }
  });

  test('云端缺失、运动错配、专项缺失和不兼容版本明确阻断', () {
    final descriptor = builtInSportPlugins().first.descriptor;
    TrainingPrescriptionCapabilities caps(
            {String id = 'training-plan-builder',
            String version = '1.3.0',
            List<String> sports = const ['marathon'],
            Map<String, String>? fragments}) =>
        TrainingPrescriptionCapabilities(
            enabled: true,
            contractVersion: 1,
            skills: [
              TrainingPrescriptionSkillCapability(
                  id: id,
                  version: version,
                  displayName: '测试技能',
                  sports: sports,
                  sourceSha256: 'a' * 64,
                  runtimeSha256: 'b' * 64,
                  fragmentSha256: fragments ?? {'marathon': 'c' * 64})
            ]);
    expect(
        cloudSportSkillBlocker(
            descriptor, const TrainingPrescriptionCapabilities.unavailable()),
        contains('服务当前不可用'));
    expect(
        cloudSportSkillBlocker(descriptor, caps(id: 'other')), contains('未提供'));
    expect(cloudSportSkillBlocker(descriptor, caps(version: '2.0.0')),
        contains('版本不兼容'));
    expect(cloudSportSkillBlocker(descriptor, caps(version: '1.4.0')), isNull);
    expect(
        cloudSportSkillBlocker(descriptor, caps(version: '1.4.0+build-test')),
        isNull);
    expect(cloudSportSkillBlocker(descriptor, caps(version: '1.4.0-beta')),
        contains('版本不兼容'));
    expect(cloudSportSkillBlocker(descriptor, caps(sports: ['strength'])),
        contains('没有覆盖'));
    expect(cloudSportSkillBlocker(descriptor, caps(fragments: {})),
        contains('缺少'));
  });

  test('归属冲突、重复技能和未声明的本地能力不能进入装配', () {
    final local = builtInSportPlugins().first.descriptor.skills.first;
    PluginDescriptor descriptor(String id, List<PluginSkillBinding> skills,
            List<String> capabilities) =>
        PluginDescriptor(
            id: id,
            type: PluginType.sport,
            version: '1.0.0',
            name: '测试',
            description: '测试',
            capabilities: capabilities,
            skills: skills);
    expect(() => descriptor('sport.other', [local], [local.capabilityId!]),
        throwsFormatException);
    expect(
        () => descriptor(
            local.ownerPluginId, [local, local], [local.capabilityId!]),
        throwsFormatException);
    expect(() => descriptor(local.ownerPluginId, [local], []),
        throwsFormatException);
  });

  test('声明本地技能却未注册真实实现时初始化失败且不公开能力', () async {
    final descriptor = builtInSportPlugins().first.descriptor;
    final registry = PluginRegistry(plugins: [_EmptyPlugin(descriptor)]);
    expect((await registry.initialize()).isSuccess, isFalse);
    expect(registry.failures[descriptor.id].toString(), contains('未注册实现'));
    expect(
        registry.readCapability<Object>(descriptor.skills.first.capabilityId!),
        isNull);
    await registry.shutdown();
    registry.dispose();
  });
}

class _EmptyPlugin extends TrainMatePlugin {
  _EmptyPlugin(this.descriptor);
  @override
  final PluginDescriptor descriptor;
  @override
  Future<void> initialize(PluginContext context) async {}
}
