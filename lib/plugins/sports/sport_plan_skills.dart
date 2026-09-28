import '../core/plugin_skill_binding.dart';

/// 共享声明模板复用文字，各运动插件仍显式选择归属和专项片段。
PluginSkillBinding localSportPlanSkill(
        String owner, String version, String name) =>
    PluginSkillBinding(
      ownerPluginId: owner,
      id: '$owner.plan',
      name: '$name本地计划',
      version: version,
      execution: SkillExecution.local,
      capabilityId: '$owner.strategy',
      purpose: '使用既有$name策略提供候选课程；时间安排和安全审核由公共链路完成。',
      inputs: '训练画像、主次运动、赛事、可用时间、器械和计划偏好。',
      outputs: '候选课程及插件来源；不会直接激活有效计划。',
      fallback: '本地实现不可用时停止新建计划，已有记录继续从历史入口读取。',
    );

PluginSkillBinding cloudSportPlanSkill(String owner, String sport, String name,
        {String? fragmentKey}) =>
    PluginSkillBinding(
      ownerPluginId: owner,
      id: 'training-plan-builder',
      name: '$name云端计划',
      version: '1.x',
      execution: SkillExecution.cloud,
      sportCode: sport,
      fragmentKey: fragmentKey,
      purpose: fragmentKey == null
          ? '使用已审核的通用周期化规则，结合本地$name模板。'
          : '使用通用周期化规则和已审核的$name专项片段。',
      inputs: '既有授权下的白名单训练上下文；当前按主运动选择片段。',
      outputs: '待确认的结构化课程蓝图；动作、负荷和安全判断由本地链路完成。',
      fallback: '云端不可用或技能不匹配时停止云端新生成，可使用本地规则计划；不自动改写有效计划。',
    );
