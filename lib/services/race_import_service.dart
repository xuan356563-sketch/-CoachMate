import '../data/models/race.dart';
import '../data/seed/seed_races.dart';

class RaceImportService {
  RacePlan parse(String rawText) {
    final Map<String, String> fields = _parseFields(rawText);
    final String name = _required(fields, const ['赛事', '名称', 'name']);
    final DateTime raceDate = _requiredDate(
      fields,
      const ['日期', '比赛日期', 'date', 'race_date'],
    );
    final RaceType type = _raceTypeFromLabel(
      _value(fields, const ['类型', 'type']) ?? '路跑',
    );
    final String targetResult =
        _value(fields, const ['目标', 'target']) ?? '先稳定完赛';
    final String courseInfo =
        _value(fields, const ['赛道', 'course']) ?? '本地导入赛事，赛道信息待补充。';
    final DateTime now = DateTime.now();
    final String idSuffix = now.microsecondsSinceEpoch.toString();

    return RacePlan(
      id: 'imported-race-$idSuffix',
      type: type,
      name: name,
      raceDate: raceDate,
      targetResult: targetResult,
      actualResult: null,
      predictedResult: _predictedResultFor(type),
      currentPhase: '导入后待自动排期',
      courseInfo: courseInfo,
      phases: _defaultPhasesFor(type),
      taperPlan: _defaultTaperPlan,
      gearAdvice: _defaultGearAdviceFor(type),
      strategySections: _defaultStrategySectionsFor(type),
      postRaceRecovery: _defaultPostRaceRecovery,
      evidenceSources: raceEvidenceSources,
    );
  }

  Map<String, String> _parseFields(String rawText) {
    final Map<String, String> fields = {};
    for (final String rawLine in rawText.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final int colonIndex = line.indexOf(RegExp('[:：=]'));
      if (colonIndex <= 0) {
        continue;
      }
      final String key = line.substring(0, colonIndex).trim().toLowerCase();
      final String value = line.substring(colonIndex + 1).trim();
      if (value.isNotEmpty) {
        fields[key] = value;
      }
    }
    return fields;
  }

  String _required(Map<String, String> fields, List<String> keys) {
    final String? value = _value(fields, keys);
    if (value == null || value.isEmpty) {
      throw FormatException('导入失败：缺少${keys.first}字段。');
    }
    return value;
  }

  DateTime _requiredDate(Map<String, String> fields, List<String> keys) {
    final String value = _required(fields, keys);
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('导入失败：${keys.first}需要使用 2026-10-18 这类日期格式。');
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String? _value(Map<String, String> fields, List<String> keys) {
    for (final String key in keys) {
      final String? value = fields[key.toLowerCase()];
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  RaceType _raceTypeFromLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case '马拉松':
      case 'marathon':
        return RaceType.marathon;
      case '越野':
      case '越野跑':
      case 'trail':
      case 'trail_running':
        return RaceType.trailRunning;
      case 'hyrox':
        return RaceType.hyrox;
      case '路跑':
      case 'road':
      case 'road_running':
      default:
        return RaceType.roadRunning;
    }
  }

  String _predictedResultFor(RaceType type) {
    switch (type) {
      case RaceType.marathon:
        return '本地导入赛事：先按当前训练记录估算完赛风险，后续接真实成绩模型。';
      case RaceType.trailRunning:
        return '本地导入赛事：优先关注爬升、下坡技术和补给耐受。';
      case RaceType.hyrox:
        return '本地导入赛事：优先关注跑后力量动作衔接。';
      case RaceType.roadRunning:
        return '本地导入赛事：先按稳定完赛和配速控制生成策略。';
    }
  }

  List<RaceTrainingPhase> _defaultPhasesFor(RaceType type) {
    final String specificFocus;
    final List<String> specificWorkouts;
    switch (type) {
      case RaceType.hyrox:
        specificFocus = '练习跑步与功能站转换，控制动作质量下降。';
        specificWorkouts = ['跑 + 功能站组合', '墙球或雪橇技术', '站点转换计时'];
        break;
      case RaceType.trailRunning:
        specificFocus = '增加爬升、下坡和补给演练。';
        specificWorkouts = ['爬坡间歇', '下坡技术', '长距离补给演练'];
        break;
      case RaceType.marathon:
      case RaceType.roadRunning:
        specificFocus = '贴近目标配速，练后半程稳定性。';
        specificWorkouts = ['目标配速分段跑', '长距离有氧', '短节奏唤醒'];
        break;
    }
    return [
      RaceTrainingPhase(
        phaseType: RacePhaseType.base,
        weekRange: '第 1-3 周',
        focus: '建立有氧基础和动作耐受，先保证可持续训练。',
        keyWorkouts: const ['Zone 2 有氧', '基础力量', '活动度维护'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.build,
        weekRange: '第 4-6 周',
        focus: '逐步提高专项容量，但每周只增加一个变量。',
        keyWorkouts: const ['渐进长课', '节奏或阈值片段', '恢复课'],
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.specific,
        weekRange: '第 7-9 周',
        focus: specificFocus,
        keyWorkouts: specificWorkouts,
      ),
      RaceTrainingPhase(
        phaseType: RacePhaseType.taper,
        weekRange: '赛前 1-2 周',
        focus: '降低总量，保留短促唤醒强度。',
        keyWorkouts: const ['短节奏唤醒', '轻松跑', '装备检查'],
      ),
    ];
  }

  List<String> _defaultGearAdviceFor(RaceType type) {
    switch (type) {
      case RaceType.hyrox:
        return const ['抓地稳定训练鞋', '号码带', '轻量短裤', '补给盐丸'];
      case RaceType.trailRunning:
        return const ['越野鞋', '软水壶或水袋', '防磨膏', '能量胶', '强制装备清单'];
      case RaceType.marathon:
      case RaceType.roadRunning:
        return const ['已磨合比赛鞋', '号码布扣', '能量胶', '防磨膏', '一次性雨衣'];
    }
  }

  List<RaceStrategySection> _defaultStrategySectionsFor(RaceType type) {
    switch (type) {
      case RaceType.hyrox:
        return const [
          RaceStrategySection(
            title: '跑段策略',
            items: ['前半程保留余量', '动作站后前 200 米先找回呼吸'],
          ),
          RaceStrategySection(
            title: '站点策略',
            items: ['动作稳定优先', '每组预留 1-2 次余量'],
          ),
        ];
      case RaceType.trailRunning:
        return const [
          RaceStrategySection(
            title: '爬升策略',
            items: ['长坡可快走', '避免前半程心率失控'],
          ),
          RaceStrategySection(
            title: '补给策略',
            items: ['按时间进食，不等饿了再补', '每个补给点确认水量'],
          ),
        ];
      case RaceType.marathon:
      case RaceType.roadRunning:
        return const [
          RaceStrategySection(
            title: '配速策略',
            items: ['前 20% 慢于目标配速', '后半程按体感守住步频'],
          ),
          RaceStrategySection(
            title: '补给策略',
            items: ['每 35-40 分钟补给一次', '比赛日不尝试新补给'],
          ),
        ];
    }
  }

  static const List<String> _defaultTaperPlan = [
    '赛前 7-10 天降低总量',
    '赛前 3-4 天只保留轻松唤醒',
    '比赛前一天只做动态拉伸和装备检查',
  ];

  static const List<String> _defaultPostRaceRecovery = [
    '赛后 24 小时内只做步行和补水',
    '48 小时后记录疼痛与疲劳',
    '一周内不安排高强度课',
  ];
}
