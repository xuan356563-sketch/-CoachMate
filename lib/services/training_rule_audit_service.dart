import '../data/models/exercise.dart';
import '../data/models/training_plan.dart';
import '../data/models/training_rule_audit.dart';
import '../data/models/workout_day.dart';

class TrainingRuleAuditService {
  TrainingRuleAuditReport buildReport(
    TrainingPlan plan, {
    required List<Exercise> exercises,
    int? availableMinutes,
  }) {
    final List<TrainingRuleAuditItem> items = [
      _auditPlanCitations(plan),
      _auditWorkoutCitations(plan),
      _auditFiveStepFlow(plan),
      _auditActionMediaLinks(plan, exercises),
      _auditTimeBudget(plan, availableMinutes: availableMinutes),
      _auditRunningModules(plan),
      _auditSafetyLanguage(plan),
    ];

    return TrainingRuleAuditReport(
      planId: plan.id,
      items: items,
      checkedWorkoutCount: plan.workoutDays.length,
      citationCount: _citationCount(plan),
      runningModuleCount: _runningModuleCount(plan),
      maxEstimatedMinutes: _maxEstimatedMinutes(plan),
    );
  }

  TrainingRuleAuditItem _auditPlanCitations(TrainingPlan plan) {
    if (plan.evidenceSources.isEmpty) {
      return const TrainingRuleAuditItem(
        title: '引用绑定',
        description: '计划没有绑定 citations，真实落库时应拒绝保存。',
        severity: TrainingRuleAuditSeverity.fail,
      );
    }
    return TrainingRuleAuditItem(
      title: '引用绑定',
      description: '计划已绑定 ${plan.evidenceSources.length} 条来源，满足“有据可循”最小门槛。',
      severity: TrainingRuleAuditSeverity.pass,
    );
  }

  TrainingRuleAuditItem _auditWorkoutCitations(TrainingPlan plan) {
    final int missingCount = plan.workoutDays
        .where((WorkoutDay day) => day.evidenceSources.isEmpty)
        .length;
    if (missingCount > 0) {
      return TrainingRuleAuditItem(
        title: '训练日依据',
        description: '$missingCount 个训练日缺少依据来源，AI 生成计划不应直接展示。',
        severity: TrainingRuleAuditSeverity.fail,
      );
    }
    return TrainingRuleAuditItem(
      title: '训练日依据',
      description: '${plan.workoutDays.length} 个训练日均有书籍、论文或内部规则依据。',
      severity: TrainingRuleAuditSeverity.pass,
    );
  }

  TrainingRuleAuditItem _auditFiveStepFlow(TrainingPlan plan) {
    final List<WorkoutDay> activeDays = plan.workoutDays
        .where((WorkoutDay day) => day.trainingType != TrainingType.rest)
        .toList();
    final int missingCount = activeDays.where((WorkoutDay day) {
      return day.foamRollingSteps.isEmpty ||
          day.dynamicStretchSteps.isEmpty ||
          day.activationSteps.isEmpty ||
          day.mainSets.isEmpty ||
          day.cooldownSteps.isEmpty;
    }).length;

    if (missingCount > 0) {
      return TrainingRuleAuditItem(
        title: '今日训练五步',
        description: '$missingCount 个非休息训练日缺少泡沫轴、动态拉伸、激活、主训练或放松反馈。',
        severity: TrainingRuleAuditSeverity.fail,
      );
    }
    return TrainingRuleAuditItem(
      title: '今日训练五步',
      description: '${activeDays.length} 个非休息训练日均包含五步流程。',
      severity: TrainingRuleAuditSeverity.pass,
    );
  }

  TrainingRuleAuditItem _auditActionMediaLinks(
    TrainingPlan plan,
    List<Exercise> exercises,
  ) {
    final Map<String, Exercise> exercisesById = {
      for (final Exercise exercise in exercises) exercise.id: exercise,
    };
    final List<WorkoutDay> activeDays = plan.workoutDays
        .where((WorkoutDay day) => day.trainingType != TrainingType.rest)
        .toList();
    const List<WorkoutExerciseModule> flowModules = [
      WorkoutExerciseModule.foamRolling,
      WorkoutExerciseModule.dynamicStretch,
      WorkoutExerciseModule.activation,
      WorkoutExerciseModule.warmup,
      WorkoutExerciseModule.cooldown,
    ];
    final List<String> issues = [];

    for (final WorkoutDay day in activeDays) {
      final List<WorkoutExerciseLink> mainLinks = day.workoutExercises
          .where(
            (WorkoutExerciseLink link) =>
                link.module == WorkoutExerciseModule.mainTraining,
          )
          .toList();
      final List<WorkoutExerciseLink> accessoryLinks = day.workoutExercises
          .where(
            (WorkoutExerciseLink link) =>
                link.module == WorkoutExerciseModule.accessory,
          )
          .toList();
      if (mainLinks.length < day.mainSets.length) {
        issues.add('${day.title}缺少正式训练动作关联');
      }
      if (accessoryLinks.length < day.accessoryWork.length) {
        issues.add('${day.title}缺少辅助训练动作关联');
      }
      for (final WorkoutExerciseModule module in flowModules) {
        final bool hasModule = day.workoutExercises.any(
          (WorkoutExerciseLink link) => link.module == module,
        );
        if (!hasModule) {
          issues.add('${day.title}缺少${module.label}动作媒体关联');
        }
      }

      for (final WorkoutExerciseLink link in day.workoutExercises) {
        final Exercise? exercise = exercisesById[link.exerciseId];
        if (exercise == null) {
          issues.add('${day.title}关联了不存在的动作 ${link.exerciseId}');
        } else if (exercise.mediaUrl == null || exercise.mediaUrl!.isEmpty) {
          issues.add('${day.title}的${exercise.name}缺少动作媒体');
        } else if (exercise.evidenceSources.isEmpty) {
          issues.add('${day.title}的${exercise.name}缺少依据来源');
        }
      }
    }

    if (issues.isNotEmpty) {
      return TrainingRuleAuditItem(
        title: '动作媒体关联',
        description: '${issues.join('；')}。真实落库前需要补齐动作库关联、媒体和依据。',
        severity: TrainingRuleAuditSeverity.fail,
      );
    }
    return TrainingRuleAuditItem(
      title: '动作媒体关联',
      description:
          '${activeDays.length} 个非休息训练日的五步流程、正式/辅助动作均已关联到带媒体和依据的动作库条目。',
      severity: TrainingRuleAuditSeverity.pass,
    );
  }

  TrainingRuleAuditItem _auditTimeBudget(
    TrainingPlan plan, {
    int? availableMinutes,
  }) {
    final int maxMinutes = _maxEstimatedMinutes(plan);
    final List<WorkoutDay> activeDays = plan.workoutDays
        .where((WorkoutDay day) => day.trainingType != TrainingType.rest)
        .toList();

    if (availableMinutes != null && availableMinutes > 0) {
      final List<WorkoutDay> overBudgetDays = activeDays
          .where(
            (WorkoutDay day) => day.estimatedMinutes > availableMinutes,
          )
          .toList();
      if (overBudgetDays.isNotEmpty) {
        final String dayLabels = overBudgetDays
            .map((WorkoutDay day) => '${day.title}（${day.estimatedMinutes} 分钟）')
            .join('、');
        return TrainingRuleAuditItem(
          title: '时间预算',
          description:
              '$dayLabels超过当前可训练时间 $availableMinutes 分钟；五步流程总时长已计入预算，需先缩短或调整后再执行。',
          severity: TrainingRuleAuditSeverity.fail,
        );
      }
    }

    final bool hasLongWorkout =
        plan.workoutDays.any((WorkoutDay day) => day.estimatedMinutes > 75);
    if (hasLongWorkout) {
      return TrainingRuleAuditItem(
        title: '时间预算',
        description: '存在超过 75 分钟的训练日，打工人场景下需要再次确认前置流程已计入。',
        severity: TrainingRuleAuditSeverity.warning,
      );
    }
    return TrainingRuleAuditItem(
      title: '时间预算',
      description: '最长训练日 $maxMinutes 分钟，当前计划未超过打工人 MVP 时间预算线。',
      severity: TrainingRuleAuditSeverity.pass,
    );
  }

  TrainingRuleAuditItem _auditRunningModules(TrainingPlan plan) {
    final List<WorkoutDay> runningDays = plan.workoutDays
        .where(
          (WorkoutDay day) =>
              day.trainingType == TrainingType.easyRun ||
              day.trainingType == TrainingType.tempoRun ||
              day.trainingType == TrainingType.intervalRun ||
              day.trainingType == TrainingType.longRun,
        )
        .toList();

    if (runningDays.isEmpty) {
      return const TrainingRuleAuditItem(
        title: '跑步硬性模块',
        description: '当前不是跑步周期，提膝/小腿硬性模块不触发。',
        severity: TrainingRuleAuditSeverity.pass,
      );
    }

    final List<WorkoutExerciseLink> runningExerciseLinks = [
      for (final WorkoutDay day in runningDays) ...day.workoutExercises,
    ];
    final bool usesStructuredModules = runningExerciseLinks.isNotEmpty;
    final bool hasHipModule = usesStructuredModules
        ? runningExerciseLinks.any(
            (WorkoutExerciseLink link) =>
                link.module == WorkoutExerciseModule.hipDrive,
          )
        : _containsAny(plan, const ['提膝', '高抬腿', 'A Skip']);
    final bool hasCalfModule = usesStructuredModules
        ? runningExerciseLinks.any(
            (WorkoutExerciseLink link) =>
                link.module == WorkoutExerciseModule.calf,
          )
        : _containsAny(plan, const ['提踵', '小腿', '踝弹跳']);
    if (hasHipModule && hasCalfModule) {
      return TrainingRuleAuditItem(
        title: '跑步硬性模块',
        description: usesStructuredModules
            ? '跑步周期已通过结构化关联包含提髋与小腿模块，共识别 ${_runningModuleCount(plan)} 个关联。'
            : '跑步周期已包含提膝/高抬腿和小腿/提踵模块，共识别 ${_runningModuleCount(plan)} 个相关片段。',
        severity: TrainingRuleAuditSeverity.pass,
      );
    }
    return TrainingRuleAuditItem(
      title: '跑步硬性模块',
      description: '跑步周期缺少提膝/高抬腿或小腿/提踵模块，真实落库前需要补齐或写明康复豁免。',
      severity: TrainingRuleAuditSeverity.fail,
    );
  }

  TrainingRuleAuditItem _auditSafetyLanguage(TrainingPlan plan) {
    final bool hasRestDay = plan.workoutDays.any(
      (WorkoutDay day) => day.decisionType == TrainingDecisionType.rest,
    );
    final bool hasSafetyCopy = plan.workoutDays.any(
      (WorkoutDay day) =>
          day.coachNotes.contains('不要补课') ||
          day.coachNotes.contains('停止') ||
          day.coachNotes.contains('就医'),
    );
    if (hasRestDay && !hasSafetyCopy) {
      return const TrainingRuleAuditItem(
        title: '安全红线表达',
        description: '计划包含休息/风险决策，但缺少明确安全解释。',
        severity: TrainingRuleAuditSeverity.warning,
      );
    }
    return const TrainingRuleAuditItem(
      title: '安全红线表达',
      description: '计划已包含休息或保守训练提示，符合不伪装最终权威的表达边界。',
      severity: TrainingRuleAuditSeverity.pass,
    );
  }

  int _citationCount(TrainingPlan plan) {
    final Set<String> ids = {
      for (final source in plan.evidenceSources) source.id,
      for (final WorkoutDay day in plan.workoutDays)
        for (final source in day.evidenceSources) source.id,
    };
    return ids.length;
  }

  int _maxEstimatedMinutes(TrainingPlan plan) {
    int maxMinutes = 0;
    for (final WorkoutDay day in plan.workoutDays) {
      if (day.estimatedMinutes > maxMinutes) {
        maxMinutes = day.estimatedMinutes;
      }
    }
    return maxMinutes;
  }

  int _runningModuleCount(TrainingPlan plan) {
    final List<WorkoutExerciseLink> structuredModules = [
      for (final WorkoutDay day in plan.workoutDays)
        if (_isRunningDay(day))
          for (final WorkoutExerciseLink link in day.workoutExercises)
            if (link.module == WorkoutExerciseModule.hipDrive ||
                link.module == WorkoutExerciseModule.calf)
              link,
    ];
    if (structuredModules.isNotEmpty) {
      return structuredModules.length;
    }

    final List<String> allItems = _allWorkoutText(plan);
    return allItems
        .where(
          (String item) =>
              item.contains('提膝') ||
              item.contains('高抬腿') ||
              item.contains('A Skip') ||
              item.contains('提踵') ||
              item.contains('小腿') ||
              item.contains('踝弹跳'),
        )
        .length;
  }

  bool _isRunningDay(WorkoutDay day) {
    return day.trainingType == TrainingType.easyRun ||
        day.trainingType == TrainingType.tempoRun ||
        day.trainingType == TrainingType.intervalRun ||
        day.trainingType == TrainingType.longRun;
  }

  bool _containsAny(TrainingPlan plan, List<String> keywords) {
    return _allWorkoutText(plan).any(
      (String item) => keywords.any(item.contains),
    );
  }

  List<String> _allWorkoutText(TrainingPlan plan) {
    return [
      for (final WorkoutDay day in plan.workoutDays) ...[
        day.title,
        day.coachNotes,
        ...day.foamRollingSteps,
        ...day.dynamicStretchSteps,
        ...day.activationSteps,
        ...day.warmupSteps,
        ...day.mainSets,
        ...day.accessoryWork,
        ...day.cooldownSteps,
      ],
    ];
  }
}
