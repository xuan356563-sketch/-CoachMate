import '../models/evidence_source.dart';
import '../models/meal_guide.dart';

const List<EvidenceSource> mealGuideEvidenceSources = [
  EvidenceSource(
    id: 'evidence-tiny-habits-meal',
    title: 'Tiny Habits',
    author: 'BJ Fogg',
    sourceType: EvidenceSourceType.book,
    chapter: '第 2 章 行为起点要足够小',
    pageRange: 'p. 39-54',
    quote: '习惯更容易从小到几乎不会失败的行为开始。',
    note: '照吃卡只给一条可执行指令，不要求用户记录热量。',
  ),
  EvidenceSource(
    id: 'evidence-protein-plate-rule',
    title: 'TrainFlow 打工人餐盘规则',
    author: 'TrainFlow AI',
    sourceType: EvidenceSourceType.internalRule,
    chapter: '轻量饮食约束',
    pageRange: 'v0.1',
    quote: '每餐先保证蛋白质和蔬菜，再控制主食与高油高糖选择。',
    note: '用于外卖、食堂、自炊三类场景的点餐公式。',
  ),
];

final List<MealGuide> seedMealGuides = [
  MealGuide(
    id: 'meal-guide-takeaway-day1',
    scenario: MealScenario.takeaway,
    title: '外卖照吃卡',
    dayLabel: '第 1/30 天 · 适应期',
    instruction: '今天点外卖只改一件事：先选一份明确蛋白质，再加一份蔬菜。',
    formula: '点餐公式：鸡/牛/鱼/蛋/豆制品 + 两份蔬菜 + 半份主食，酱汁分开放。',
    addOneThing: '加一个无糖饮品或白水，不点含糖饮料。',
    avoidItems: ['炸鸡套餐', '奶茶', '重油拌饭', '只吃主食不吃蛋白质'],
    reason: '降低选择成本，先保证恢复和饱腹，不让饮食模块变成负担。',
    evidenceSources: mealGuideEvidenceSources,
  ),
  MealGuide(
    id: 'meal-guide-canteen-day1',
    scenario: MealScenario.canteen,
    title: '食堂照吃卡',
    dayLabel: '第 1/30 天 · 适应期',
    instruction: '今天在食堂按顺序夹菜：先蛋白质，再蔬菜，最后主食。',
    formula: '餐盘公式：1 掌心蛋白质 + 2 拳蔬菜 + 1 拳主食。',
    addOneThing: '如果下午容易饿，午餐加一份鸡蛋、豆腐或牛奶。',
    avoidItems: ['只拿面/粉/饭', '油炸窗口', '甜饮料', '饭后甜点'],
    reason: '食堂场景不需要精算热量，先把餐盘结构稳定下来。',
    evidenceSources: mealGuideEvidenceSources,
  ),
  MealGuide(
    id: 'meal-guide-home-cooking-day1',
    scenario: MealScenario.homeCooking,
    title: '自炊照吃卡',
    dayLabel: '第 1/30 天 · 适应期',
    instruction: '今天只做 10 分钟版本：一个蛋白质 + 一个蔬菜 + 一份主食。',
    formula: '10 分钟公式：煎蛋/鸡胸/豆腐 + 冷冻蔬菜或生菜 + 米饭/土豆/全麦面包。',
    addOneThing: '提前多洗一份蔬菜，明天可以直接复用。',
    avoidItems: ['边做边加零食', '只吃泡面', '不吃蛋白质', '做太复杂导致放弃'],
    reason: '自炊阶段先追求可重复，不追求完美菜单。',
    evidenceSources: mealGuideEvidenceSources,
  ),
];
