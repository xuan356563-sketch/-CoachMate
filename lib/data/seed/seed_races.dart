import '../models/evidence_source.dart';
import '../models/race.dart';

const List<EvidenceSource> raceEvidenceSources = [
  EvidenceSource(
    id: 'evidence-race-periodization',
    title: 'Daniels\' Running Formula',
    author: 'Jack Daniels',
    sourceType: EvidenceSourceType.book,
    chapter: '周期化训练安排',
    pageRange: 'p. 112-126',
    quote: '训练应按阶段推进，并在比赛前安排减量以保留状态。',
    note: '用于 base→build→specific→taper 的周期反推。',
  ),
  EvidenceSource(
    id: 'evidence-race-taper',
    title: 'TrainFlow 备赛减量规则',
    author: 'TrainFlow AI',
    sourceType: EvidenceSourceType.internalRule,
    chapter: '比赛周安全策略',
    pageRange: 'v0.1',
    quote: '比赛前 7-10 天降低总量，保留少量唤醒强度。',
    note: '用于赛前减量、装备检查和比赛日策略。',
  ),
];

final List<RacePlan> seedRaces = [
  RacePlan(
    id: 'race-shanghai-marathon-2026',
    type: RaceType.marathon,
    name: '上海马拉松备赛',
    raceDate: DateTime(2026, 11, 29),
    targetResult: '完赛 4:30 内',
    actualResult: null,
    predictedResult: '当前预测 4:38-4:50，需提升长距离稳定性',
    currentPhase: '基础期第 2 周',
    courseInfo: '城市路跑，补给稳定，后半程需要控制配速漂移。',
    phases: [
      RaceTrainingPhase(
        phaseType: RacePhaseType.base,
        weekRange: '第 1-4 周',
        focus: '建立 Zone 2 有氧基础，补齐提胯和小腿耐受。',
        keyWorkouts: ['轻松跑 40-60 分钟', 'A Skip + 提踵', '下肢力量基础课'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.build,
        weekRange: '第 5-8 周',
        focus: '逐步拉长长距离，加入节奏跑但保留恢复日。',
        keyWorkouts: ['长距离 90-120 分钟', '节奏跑 20 分钟', '恢复跑'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.specific,
        weekRange: '第 9-12 周',
        focus: '贴近目标配速，练补给和后半程控制。',
        keyWorkouts: ['目标配速分段跑', '长距离补给演练', '比赛鞋适应'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.taper,
        weekRange: '第 13-14 周',
        focus: '减少总量，保留短促唤醒强度。',
        keyWorkouts: ['短节奏唤醒', '轻松跑', '活动度维护'],
      ),
    ],
    taperPlan: ['赛前 10 天总量下降 30%', '赛前 4 天只保留 20 分钟轻松跑', '比赛前一天只做动态拉伸和装备检查'],
    gearAdvice: ['已磨合的比赛鞋', '腰包或号码布扣', '能量胶 4-5 支', '防磨膏', '一次性雨衣'],
    strategySections: [
      RaceStrategySection(
        title: '配速策略',
        items: ['前 5 公里慢于目标配速 5-10 秒', '半程前不追人', '30 公里后按体感守住步频'],
      ),
      RaceStrategySection(
        title: '补给策略',
        items: ['每 35-40 分钟一支能量胶', '每个水站少量多次', '不要比赛日尝试新补给'],
      ),
    ],
    postRaceRecovery: ['赛后 24 小时内只做步行和补水', '48 小时后记录疼痛与疲劳', '一周内不安排强度课'],
    evidenceSources: raceEvidenceSources,
  ),
  RacePlan(
    id: 'race-hyrox-open-2026',
    type: RaceType.hyrox,
    name: 'HYROX Open 备赛',
    raceDate: DateTime(2026, 10, 18),
    targetResult: '稳定完赛，跑段不崩',
    actualResult: null,
    predictedResult: '当前预测 1:35-1:45，瓶颈在跑后力量动作衔接',
    currentPhase: '专项期第 1 周',
    courseInfo: '8 个跑段 + 8 个功能训练站，重点是跑后动作质量。',
    phases: [
      RaceTrainingPhase(
        phaseType: RacePhaseType.base,
        weekRange: '第 1-3 周',
        focus: '恢复跑量和基础力量，修正动作质量。',
        keyWorkouts: ['Zone 2 跑', '深蹲/髋铰链纠错', '核心抗疲劳'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.build,
        weekRange: '第 4-6 周',
        focus: '建立跑后力量动作耐受。',
        keyWorkouts: ['跑 + 雪橇推组合', '农夫走', '墙球技术'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.specific,
        weekRange: '第 7-9 周',
        focus: '模拟比赛节奏，练动作站转换。',
        keyWorkouts: ['迷你 HYROX 模拟', '跑后弓步蹲', '站点转换计时'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.taper,
        weekRange: '第 10 周',
        focus: '降低总量，保留动作熟悉度。',
        keyWorkouts: ['轻量站点串联', '短跑唤醒', '活动度维护'],
      ),
    ],
    taperPlan: ['赛前一周减少站点总量 40%', '赛前 3 天不做高乳酸训练', '比赛前一天只走流程和装备检查'],
    gearAdvice: ['抓地稳定的训练鞋', '护腕或镁粉替代方案', '轻量短裤', '补给盐丸', '号码带'],
    strategySections: [
      RaceStrategySection(
        title: '跑段策略',
        items: ['前 3 个跑段保持可说短句强度', '动作站后前 200 米先找回呼吸', '最后两段再推进'],
      ),
      RaceStrategySection(
        title: '站点策略',
        items: ['雪橇动作优先稳定路径', '墙球每组预留 1-2 次余量', '波比不抢速度，减少停顿'],
      ),
    ],
    postRaceRecovery: ['赛后当天补水和碳水', '第二天记录肩、膝、跟腱疼痛', '72 小时内只做低强度恢复'],
    evidenceSources: raceEvidenceSources,
  ),
];
