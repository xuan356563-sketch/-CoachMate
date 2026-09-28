/// 资源权威源：人工维护，目录快照通过既有导出器生成。
const seedSportResources = <Map<String, dynamic>>[
  {
    "id": "assessment.marathon.baseline",
    "version": "1.0.0",
    "kind": "assessment",
    "sport": "marathon",
    "ownerPluginId": "sport.marathon",
    "title": "马拉松训练基础评估",
    "scope": "跑步经历与近期完成情况",
    "source": "TrainMate 训练事实手动记录表",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": [
      "只记录已完成的训练，不需要为填写表单额外测试。",
      "不知道的项目可以留空，所有记录由你确认后保存。",
      "记录不代表能力等级，不自动改变档案或计划。"
    ],
    "fields": [
      {"id": "experience", "label": "训练经历", "unit": "", "numeric": false},
      {"id": "frequency", "label": "近期每周训练次数", "unit": "次/周", "numeric": true},
      {"id": "conditions", "label": "可用器械与场地", "unit": "", "numeric": false},
      {"id": "duration", "label": "最近一次已完成训练时长", "unit": "分钟", "numeric": true},
      {"id": "distance", "label": "最近一次已完成跑步距离", "unit": "公里", "numeric": true},
      {"id": "notes", "label": "备注", "unit": "", "numeric": false}
    ]
  },
  {
    "id": "plan.marathon.baseline",
    "version": "1.0.0",
    "kind": "plan",
    "sport": "marathon",
    "ownerPluginId": "sport.marathon",
    "title": "马拉松基础 4 周计划",
    "scope": "跑步经历与近期完成情况",
    "source": "lib/plugins/sports/marathon_plugin.dart",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": ["使用已确认的主次运动、器械、可用时间和赛事资料。", "由现有策略生成完整候选计划，经安全审核及你确认后启用。"],
    "fields": []
  },
  {
    "id": "assessment.trail_running.baseline",
    "version": "1.0.0",
    "kind": "assessment",
    "sport": "trail_running",
    "ownerPluginId": "sport.trail_running",
    "title": "越野跑训练基础评估",
    "scope": "跑步、越野经历与可用场地；当前计划共享跑步模板，不包含新的越野专项算法。",
    "source": "TrainMate 训练事实手动记录表",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": [
      "只记录已完成的训练，不需要为填写表单额外测试。",
      "不知道的项目可以留空，所有记录由你确认后保存。",
      "记录不代表能力等级，不自动改变档案或计划。"
    ],
    "fields": [
      {"id": "experience", "label": "训练经历", "unit": "", "numeric": false},
      {"id": "frequency", "label": "近期每周训练次数", "unit": "次/周", "numeric": true},
      {"id": "conditions", "label": "可用器械与场地", "unit": "", "numeric": false},
      {"id": "duration", "label": "最近一次已完成训练时长", "unit": "分钟", "numeric": true},
      {"id": "distance", "label": "最近一次已完成跑步距离", "unit": "公里", "numeric": true},
      {"id": "notes", "label": "备注", "unit": "", "numeric": false}
    ]
  },
  {
    "id": "plan.trail_running.baseline",
    "version": "1.0.0",
    "kind": "plan",
    "sport": "trail_running",
    "ownerPluginId": "sport.trail_running",
    "title": "越野跑基础 4 周计划",
    "scope": "跑步、越野经历与可用场地；当前计划共享跑步模板，不包含新的越野专项算法。",
    "source": "lib/plugins/sports/trail_running_plugin.dart",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": ["使用已确认的主次运动、器械、可用时间和赛事资料。", "由现有策略生成完整候选计划，经安全审核及你确认后启用。"],
    "fields": []
  },
  {
    "id": "assessment.strength.baseline",
    "version": "1.0.0",
    "kind": "assessment",
    "sport": "strength",
    "ownerPluginId": "sport.strength",
    "title": "力量训练训练基础评估",
    "scope": "训练经历、可用器械与已完成动作组次",
    "source": "TrainMate 训练事实手动记录表",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": [
      "只记录已完成的训练，不需要为填写表单额外测试。",
      "不知道的项目可以留空，所有记录由你确认后保存。",
      "记录不代表能力等级，不自动改变档案或计划。"
    ],
    "fields": [
      {"id": "experience", "label": "训练经历", "unit": "", "numeric": false},
      {"id": "frequency", "label": "近期每周训练次数", "unit": "次/周", "numeric": true},
      {"id": "conditions", "label": "可用器械与场地", "unit": "", "numeric": false},
      {"id": "duration", "label": "最近一次已完成训练时长", "unit": "分钟", "numeric": true},
      {"id": "exercises", "label": "已完成动作或站点名称", "unit": "", "numeric": false},
      {"id": "sets", "label": "对应动作已完成组数", "unit": "组", "numeric": true},
      {
        "id": "repetitions",
        "label": "每组次数（不一致可写备注）",
        "unit": "次",
        "numeric": true
      },
      {"id": "notes", "label": "备注", "unit": "", "numeric": false}
    ]
  },
  {
    "id": "plan.strength.baseline",
    "version": "1.0.0",
    "kind": "plan",
    "sport": "strength",
    "ownerPluginId": "sport.strength",
    "title": "力量训练基础 4 周计划",
    "scope": "训练经历、可用器械与已完成动作组次",
    "source": "lib/plugins/sports/strength_plugin.dart",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": ["使用已确认的主次运动、器械、可用时间和赛事资料。", "由现有策略生成完整候选计划，经安全审核及你确认后启用。"],
    "fields": []
  },
  {
    "id": "assessment.hyrox.baseline",
    "version": "1.0.0",
    "kind": "assessment",
    "sport": "hyrox",
    "ownerPluginId": "sport.hyrox",
    "title": "HYROX训练基础评估",
    "scope": "跑步、站点训练经历及可用器械",
    "source": "TrainMate 训练事实手动记录表",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": [
      "只记录已完成的训练，不需要为填写表单额外测试。",
      "不知道的项目可以留空，所有记录由你确认后保存。",
      "记录不代表能力等级，不自动改变档案或计划。"
    ],
    "fields": [
      {"id": "experience", "label": "训练经历", "unit": "", "numeric": false},
      {"id": "frequency", "label": "近期每周训练次数", "unit": "次/周", "numeric": true},
      {"id": "conditions", "label": "可用器械与场地", "unit": "", "numeric": false},
      {"id": "duration", "label": "最近一次已完成训练时长", "unit": "分钟", "numeric": true},
      {"id": "distance", "label": "最近一次已完成跑步距离", "unit": "公里", "numeric": true},
      {"id": "exercises", "label": "已完成动作或站点名称", "unit": "", "numeric": false},
      {"id": "sets", "label": "对应动作已完成组数", "unit": "组", "numeric": true},
      {
        "id": "repetitions",
        "label": "每组次数（不一致可写备注）",
        "unit": "次",
        "numeric": true
      },
      {"id": "notes", "label": "备注", "unit": "", "numeric": false}
    ]
  },
  {
    "id": "plan.hyrox.baseline",
    "version": "1.0.0",
    "kind": "plan",
    "sport": "hyrox",
    "ownerPluginId": "sport.hyrox",
    "title": "HYROX基础 4 周计划",
    "scope": "跑步、站点训练经历及可用器械",
    "source": "lib/plugins/sports/hyrox_plugin.dart",
    "reviewStatus": "approved",
    "reviewNote": "首版工程内容审核：仅收集自述事实，不设置能力阈值；计划沿用现有策略。",
    "instructions": ["使用已确认的主次运动、器械、可用时间和赛事资料。", "由现有策略生成完整候选计划，经安全审核及你确认后启用。"],
    "fields": []
  }
];
