import 'dart:math';

import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

enum CompanionCopyVariantKind { standard, dismissAck, injuryFixed }

class CompanionCopyVariant {
  const CompanionCopyVariant({
    required this.id,
    required this.intent,
    required this.template,
    this.kind = CompanionCopyVariantKind.standard,
    this.isFallback = false,
  });

  final String id;
  final CompanionIntent intent;
  final String template;
  final CompanionCopyVariantKind kind;
  final bool isFallback;

  Set<String> get requiredVariables => RegExp(r'\{([a-zA-Z][a-zA-Z0-9]*)\}')
      .allMatches(template)
      .map((RegExpMatch match) => match.group(1)!)
      .toSet();

  bool canRender(Map<String, String> variables) =>
      requiredVariables.every((String key) =>
          variables[key] != null && variables[key]!.trim().isNotEmpty);

  String render(Map<String, String> variables) {
    if (!canRender(variables)) {
      throw ArgumentError(
          '搭子文案缺少必要变量：${requiredVariables.where((String key) => variables[key] == null).join('、')}');
    }
    return variables.entries.fold<String>(
      template,
      (String text, MapEntry<String, String> entry) =>
          text.replaceAll('{${entry.key}}', entry.value),
    );
  }
}

class CompanionCopyHistory {
  const CompanionCopyHistory({
    required this.variantId,
    required this.createdAt,
  });

  final String variantId;
  final DateTime createdAt;
}

const List<CompanionCopyVariant> companionCopyVariants = <CompanionCopyVariant>[
  CompanionCopyVariant(
      id: 'mb-01',
      intent: CompanionIntent.morningBrief,
      template: '睡了 {sleepDuration}，不错。今天{workoutName}，{durationMin} 分钟。'),
  CompanionCopyVariant(
      id: 'mb-02',
      intent: CompanionIntent.morningBrief,
      template: '状态看着可以。今天按计划来？'),
  CompanionCopyVariant(
      id: 'mb-03',
      intent: CompanionIntent.morningBrief,
      template: '恢复得不错。今天那个{workoutName}，什么时候？'),
  CompanionCopyVariant(
      id: 'mb-04',
      intent: CompanionIntent.morningBrief,
      template: '今天{workoutName}。准备好了叫我。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'mb-05',
      intent: CompanionIntent.morningBrief,
      template: '昨晚睡得挺踏实。今天正常练。'),
  CompanionCopyVariant(
      id: 'mb-06',
      intent: CompanionIntent.morningBrief,
      template: '昨晚只睡了 {sleepDuration}，HRV 也掉了。{workoutName}挪明天？'),
  CompanionCopyVariant(
      id: 'mb-07',
      intent: CompanionIntent.morningBrief,
      template: '睡得少。今天要不换个轻的？'),
  CompanionCopyVariant(
      id: 'mb-08',
      intent: CompanionIntent.morningBrief,
      template: '今天状态一般。有个 {durationMin} 分钟的轻量版，要不要？'),
  CompanionCopyVariant(
      id: 'mb-09',
      intent: CompanionIntent.morningBrief,
      template: '身体信号不太好看。今天别硬来。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'mb-10',
      intent: CompanionIntent.morningBrief,
      template: '这几天睡眠都不够。今天降一档？'),
  CompanionCopyVariant(
      id: 'mb-11',
      intent: CompanionIntent.morningBrief,
      template: '今天计划里是休息。走走就行。'),
  CompanionCopyVariant(
      id: 'mb-12',
      intent: CompanionIntent.morningBrief,
      template: '今天不练。休息也是训练的一部分。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'mb-13', intent: CompanionIntent.morningBrief, template: '休息日。别多想。'),
  CompanionCopyVariant(
      id: 'mb-14',
      intent: CompanionIntent.morningBrief,
      template: '今天没安排。要不要给你排一个？',
      isFallback: true),
  CompanionCopyVariant(
      id: 'mb-15',
      intent: CompanionIntent.morningBrief,
      template: '今天空着。想动的话我这有东西。'),
  CompanionCopyVariant(
      id: 'mb-16',
      intent: CompanionIntent.morningBrief,
      template: '早。我每天早上会看一眼你的数据，然后告诉你今天适合练什么。'),
  CompanionCopyVariant(
      id: 'mb-17',
      intent: CompanionIntent.morningBrief,
      template: '今天第 {togetherDays} 天。先把节奏找出来，不着急。'),
  CompanionCopyVariant(
      id: 'pw-01',
      intent: CompanionIntent.preWorkout,
      template: '半小时后那个{workoutName}。'),
  CompanionCopyVariant(
      id: 'pw-02',
      intent: CompanionIntent.preWorkout,
      template: '到点了。{durationMin} 分钟。'),
  CompanionCopyVariant(
      id: 'pw-03',
      intent: CompanionIntent.preWorkout,
      template: '{workoutName}，准备好了叫我。'),
  CompanionCopyVariant(
      id: 'pw-04',
      intent: CompanionIntent.preWorkout,
      template: '该动了。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'pw-05',
      intent: CompanionIntent.preWorkout,
      template: '时间到。今天{workoutName}。'),
  CompanionCopyVariant(
      id: 'pw-06',
      intent: CompanionIntent.preWorkout,
      template: '{durationMin} 分钟，练完就完事了。'),
  CompanionCopyVariant(
      id: 'pw-07', intent: CompanionIntent.preWorkout, template: '我这边准备好了。'),
  CompanionCopyVariant(
      id: 'pw-08',
      intent: CompanionIntent.preWorkout,
      template: '距比赛 {daysToRace} 天。今天这个是关键课。'),
  CompanionCopyVariant(
      id: 'pw-09',
      intent: CompanionIntent.preWorkout,
      template: '今天{workoutName}，比赛用得上。'),
  CompanionCopyVariant(
      id: 'po-01',
      intent: CompanionIntent.postWorkout,
      template: '练完了。第 {togetherDays} 天。'),
  CompanionCopyVariant(
      id: 'po-02',
      intent: CompanionIntent.postWorkout,
      template: '完成。{durationMin} 分钟。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'po-03',
      intent: CompanionIntent.postWorkout,
      template: '记下了。今天这个完成度不错。'),
  CompanionCopyVariant(
      id: 'po-04', intent: CompanionIntent.postWorkout, template: '结束。休息一下。'),
  CompanionCopyVariant(
      id: 'po-05',
      intent: CompanionIntent.postWorkout,
      template: '练完了。能量 +100。'),
  CompanionCopyVariant(
      id: 'po-06',
      intent: CompanionIntent.postWorkout,
      template: '比计划多了 {extraMin} 分钟。悠着点。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'po-07',
      intent: CompanionIntent.postWorkout,
      template: '今天量有点大。明天轻一点。'),
  CompanionCopyVariant(
      id: 'po-08',
      intent: CompanionIntent.postWorkout,
      template: 'RPE {rpe}，偏高了。记下了，明天调。'),
  CompanionCopyVariant(
      id: 'po-09',
      intent: CompanionIntent.postWorkout,
      template: '练了。今天这样就行。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'po-10',
      intent: CompanionIntent.postWorkout,
      template: '完成了轻量版。也是一次。'),
  CompanionCopyVariant(
      id: 'po-11',
      intent: CompanionIntent.postWorkout,
      template: '降了一档，做完了。这比硬撑强。'),
  CompanionCopyVariant(
      id: 'ack-01',
      intent: CompanionIntent.missedWorkout,
      template: '好。我也歇着。明天见。',
      kind: CompanionCopyVariantKind.dismissAck,
      isFallback: true),
  CompanionCopyVariant(
      id: 'ack-02',
      intent: CompanionIntent.missedWorkout,
      template: '记下了。明天见。',
      kind: CompanionCopyVariantKind.dismissAck),
  CompanionCopyVariant(
      id: 'ack-03',
      intent: CompanionIntent.missedWorkout,
      template: '行。今天到这。',
      kind: CompanionCopyVariantKind.dismissAck),
  CompanionCopyVariant(
      id: 'ack-04',
      intent: CompanionIntent.missedWorkout,
      template: '好。你说了算。',
      kind: CompanionCopyVariantKind.dismissAck),
  CompanionCopyVariant(
      id: 'ack-05',
      intent: CompanionIntent.missedWorkout,
      template: '嗯。明天。',
      kind: CompanionCopyVariantKind.dismissAck),
  CompanionCopyVariant(
      id: 'mw-01',
      intent: CompanionIntent.missedWorkout,
      template: '今天没动。明天见。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'mw-02',
      intent: CompanionIntent.missedWorkout,
      template: '计划里的{workoutName}还没开始。挪明天？'),
  CompanionCopyVariant(
      id: 'mw-03',
      intent: CompanionIntent.missedWorkout,
      template: '还有个 5 分钟版，做不做都行。'),
  CompanionCopyVariant(
      id: 'mw-04', intent: CompanionIntent.missedWorkout, template: '今天先算了吧。'),
  CompanionCopyVariant(
      id: 'mw-05',
      intent: CompanionIntent.missedWorkout,
      template: '看了下你今天步数，够忙的。休一天。'),
  CompanionCopyVariant(
      id: 'mw-06',
      intent: CompanionIntent.missedWorkout,
      template: '不练也是一种决定。记下了。'),
  CompanionCopyVariant(
      id: 'mw-07',
      intent: CompanionIntent.missedWorkout,
      template: '这周第二次了。是计划太重，还是最近太忙？'),
  CompanionCopyVariant(
      id: 'mw-08',
      intent: CompanionIntent.missedWorkout,
      template: '要不我们把频次降到每周两次？先跑起来再说。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'mw-09',
      intent: CompanionIntent.missedWorkout,
      template: '没关系。要不要我把这周剩下的重排一下？'),
  CompanionCopyVariant(
      id: 'da-01',
      intent: CompanionIntent.dataAnomaly,
      template: '静息心率比平时高了 {delta}。最近睡得怎么样？',
      isFallback: true),
  CompanionCopyVariant(
      id: 'da-02',
      intent: CompanionIntent.dataAnomaly,
      template: 'HRV 掉得有点多。最近是不是累着了？'),
  CompanionCopyVariant(
      id: 'da-03',
      intent: CompanionIntent.dataAnomaly,
      template: '连着三天没睡够 6 小时。今天早点？'),
  CompanionCopyVariant(
      id: 'da-04',
      intent: CompanionIntent.dataAnomaly,
      template: '身体信号有点反常。要不要记一下今天的状态？'),
  CompanionCopyVariant(
      id: 'da-05',
      intent: CompanionIntent.dataAnomaly,
      template: '今天走了不到 3000 步，第三天了。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'da-06', intent: CompanionIntent.dataAnomaly, template: '这几天动得少。忙吗？'),
  CompanionCopyVariant(
      id: 'ms-01',
      intent: CompanionIntent.milestone,
      template: '第 {togetherDays} 天。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'ms-02',
      intent: CompanionIntent.milestone,
      template: '我们一起 {togetherDays} 天了。'),
  CompanionCopyVariant(
      id: 'ms-03',
      intent: CompanionIntent.milestone,
      template: '连续 {streakDays} 天。'),
  CompanionCopyVariant(
      id: 'ms-04', intent: CompanionIntent.milestone, template: '进化了。看看？'),
  CompanionCopyVariant(
      id: 'ms-05',
      intent: CompanionIntent.milestone,
      template: '你的{exerciseName}上到 {weight} 了。三个月前是 {oldWeight}。'),
  CompanionCopyVariant(
      id: 'ms-06',
      intent: CompanionIntent.milestone,
      template: '{togetherDays} 天。中间停过，但没断。'),
  CompanionCopyVariant(
      id: 'ms-07',
      intent: CompanionIntent.milestone,
      template: '第一次跟着练完整一次。记下了。'),
  CompanionCopyVariant(
      id: 'ms-08',
      intent: CompanionIntent.milestone,
      template: '今天你选了降级。这个也值得记一下。'),
  CompanionCopyVariant(
      id: 'rb-01',
      intent: CompanionIntent.recordBreak,
      template: '今天 {steps} 步，破了你自己的记录。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'rb-02',
      intent: CompanionIntent.recordBreak,
      template: '这周跑量比上周多了 {deltaKm} 公里。'),
  CompanionCopyVariant(
      id: 'rb-03',
      intent: CompanionIntent.recordBreak,
      template: '{exerciseName} {weight}，新高。'),
  CompanionCopyVariant(
      id: 'rb-04',
      intent: CompanionIntent.recordBreak,
      template: '配速比上次快了 {deltaPace}。'),
  CompanionCopyVariant(
      id: 'wr-01',
      intent: CompanionIntent.weeklyReview,
      template: '这周我给你算了笔账。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'wr-02',
      intent: CompanionIntent.weeklyReview,
      template: '{doneCount} 次训练，{plannedCount} 次计划。这周还行。'),
  CompanionCopyVariant(
      id: 'wr-03',
      intent: CompanionIntent.weeklyReview,
      template: '周报出来了。要看吗？'),
  CompanionCopyVariant(
      id: 'wr-04',
      intent: CompanionIntent.weeklyReview,
      template: '这周结束了。下周想调点什么？'),
  CompanionCopyVariant(
      id: 'qd-01',
      intent: CompanionIntent.quietDay,
      template: '我在。你回来的时候我们从这继续。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'qd-02', intent: CompanionIntent.quietDay, template: '这几天没数据。不着急。'),
  CompanionCopyVariant(
      id: 'qd-03', intent: CompanionIntent.quietDay, template: '在呢。'),
  CompanionCopyVariant(
      id: 'qd-04', intent: CompanionIntent.quietDay, template: '歇着呢。你也是吧。'),
  CompanionCopyVariant(
      id: 'pa-01',
      intent: CompanionIntent.planAdjust,
      template: '这周漏了两次。要不要我把剩下的重排一下？',
      isFallback: true),
  CompanionCopyVariant(
      id: 'pa-02',
      intent: CompanionIntent.planAdjust,
      template: '最近负荷有点高，下周想给你减个量。看看？'),
  CompanionCopyVariant(
      id: 'pa-03',
      intent: CompanionIntent.planAdjust,
      template: '这个计划可能定得太满了。调一调？'),
  CompanionCopyVariant(
      id: 'pa-04',
      intent: CompanionIntent.planAdjust,
      template: '出差的话我把这周改成无器械版？'),
  CompanionCopyVariant(
      id: 'rt-01',
      intent: CompanionIntent.returning,
      template: '你回来啦。今天从这继续。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'rt-02', intent: CompanionIntent.returning, template: '在呢。今天想动动吗？'),
  CompanionCopyVariant(
      id: 'rt-03',
      intent: CompanionIntent.returning,
      template: '回来了。要不要先来个轻的？'),
  CompanionCopyVariant(
      id: 'rt-04', intent: CompanionIntent.returning, template: '今天开始就行。'),
  CompanionCopyVariant(
      id: 'rt-05', intent: CompanionIntent.returning, template: '看到你了。'),
  CompanionCopyVariant(
      id: 'rt-06', intent: CompanionIntent.returning, template: '重新开始不用从头开始。'),
  CompanionCopyVariant(
      id: 'ic-01',
      intent: CompanionIntent.injuryCare,
      template: '你记了{bodyPart} {painLevel} 分的疼。今天的{workoutName}我先撤掉了，换成恢复课。',
      kind: CompanionCopyVariantKind.injuryFixed),
  CompanionCopyVariant(
      id: 'ic-02',
      intent: CompanionIntent.injuryCare,
      template: '{bodyPart}还在疼。这几天先不练那个动作，我找了几个替代的。',
      kind: CompanionCopyVariantKind.injuryFixed),
  CompanionCopyVariant(
      id: 'ic-03',
      intent: CompanionIntent.injuryCare,
      template: '{bodyPart}疼到 {painLevel} 分。这种情况建议找专业的看一下。训练先停，我这边只能做到这。',
      kind: CompanionCopyVariantKind.injuryFixed),
  CompanionCopyVariant(
      id: 'ic-04',
      intent: CompanionIntent.injuryCare,
      template: '这个疼已经两周多了。我不建议继续训练，先去看看。',
      kind: CompanionCopyVariantKind.injuryFixed),
  CompanionCopyVariant(
      id: 'ca-01',
      intent: CompanionIntent.checkinAck,
      template: '收到。',
      isFallback: true),
  CompanionCopyVariant(
      id: 'ca-02', intent: CompanionIntent.checkinAck, template: '记下了。今天看着还行。'),
  CompanionCopyVariant(
      id: 'ca-03',
      intent: CompanionIntent.checkinAck,
      template: '记下了。状态一般的话，今天那个降一档？'),
];

CompanionCopyVariant? pickCompanionCopyVariant({
  required CompanionIntent intent,
  required Map<String, String> variables,
  required Set<String> usedVariantIds,
  required DateTime now,
  required Iterable<CompanionCopyHistory> history,
  Random? random,
  CompanionCopyVariantKind kind = CompanionCopyVariantKind.standard,
}) {
  final List<CompanionCopyVariant> pool = companionCopyVariants
      .where((CompanionCopyVariant item) =>
          item.intent == intent && item.kind == kind)
      .where((CompanionCopyVariant item) => item.canRender(variables))
      .toList(growable: false);
  final List<CompanionCopyVariant> fresh = pool
      .where((CompanionCopyVariant item) => !usedVariantIds.contains(item.id))
      .where((CompanionCopyVariant item) =>
          !_wasUsedWithin(history, item.id, now, const Duration(days: 30)))
      .toList(growable: false);
  final List<CompanionCopyVariant> candidates = fresh.isNotEmpty
      ? fresh
      : pool
          .where((CompanionCopyVariant item) => item.isFallback)
          .where((CompanionCopyVariant item) =>
              !_wasUsedWithin(history, item.id, now, const Duration(days: 14)))
          .toList(growable: false);
  if (candidates.isEmpty) return null;
  final Random chooser = random ?? Random();
  return candidates[chooser.nextInt(candidates.length)];
}

CompanionCopyVariant resolveInjuryCopyVariant({
  required int painScore,
  required bool hasLastedMoreThanTwoWeeks,
  bool isOngoing = false,
}) {
  final String id = hasLastedMoreThanTwoWeeks
      ? 'ic-04'
      : painScore >= 7
          ? 'ic-03'
          : isOngoing
              ? 'ic-02'
              : 'ic-01';
  return companionCopyVariants
      .singleWhere((CompanionCopyVariant item) => item.id == id);
}

List<String> lintCompanionCopyLibrary(Iterable<CompanionCopyVariant> variants) {
  const List<String> forbidden = <String>[
    '加油',
    '太棒了',
    '真棒',
    '厉害了',
    '元气',
    '满满',
    '冲鸭',
    '么么',
    '宝子',
    '亲',
    '应该',
    '必须',
    '一定要',
    '务必',
    '坚持',
    '毅力',
    '自律',
    '别偷懒',
    '不要放弃',
    '断签',
    '连击中断',
    '打卡失败',
    '荒废',
    '掉队',
    '落下了',
    '身材',
    '体型',
    '更好看',
    '理想体重',
    '目标身材',
    '我等你',
    '我很想你',
    '我有点难过',
    '我快没能量了',
    '别丢下我',
    '你忍心吗',
    '你可能生病了',
    '建议休息',
  ];
  final List<String> violations = <String>[];
  int laCount = 0;
  for (final CompanionCopyVariant item in variants) {
    final String text = item.template;
    for (final String word in forbidden) {
      if (text.contains(word)) violations.add('${item.id} 包含禁用词「$word」');
    }
    if (text.contains('!') || text.contains('！')) {
      violations.add('${item.id} 包含感叹号');
    }
    if (text.contains('～') || text.contains('…')) {
      violations.add('${item.id} 包含禁用标点');
    }
    if (text.contains('啦')) {
      laCount += 1;
      if (item.intent != CompanionIntent.returning) {
        violations.add('${item.id} 的「啦」不在回归场景');
      }
    }
  }
  if (laCount > 1) violations.add('全库「啦」超过唯一允许的回归豁免');
  return violations;
}

bool _wasUsedWithin(
  Iterable<CompanionCopyHistory> history,
  String variantId,
  DateTime now,
  Duration duration,
) {
  return history.any((CompanionCopyHistory entry) {
    final Duration age = now.difference(entry.createdAt);
    return entry.variantId == variantId && !age.isNegative && age < duration;
  });
}
