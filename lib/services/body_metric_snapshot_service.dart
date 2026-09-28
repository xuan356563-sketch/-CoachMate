import '../data/models/body_metric.dart';
import '../data/models/body_metric_snapshot.dart';
import 'body_metric_input_validation.dart';

class BodyMetricSnapshotRecognitionService {
  BodyMetricSnapshotRecognitionResult recognize(
    String rawText, {
    BodyMetric? fallback,
  }) {
    final String text = rawText.trim();
    if (text.isEmpty) {
      throw const FormatException('识别失败：请粘贴体脂秤、手表或跑步 App 截图中的文字。');
    }

    final double? weight = _doubleValue(text, const ['体重', 'weight'], units: r'kg|公斤|千克');
    final double? bodyFat = _doubleValue(text, const ['体脂率', '体脂', 'body fat'], units: r'%|％');
    final int? restingHr = _intValue(
      text,
      const ['静息心率', '静息心', 'resting heart rate', 'resting hr'],
      units: r'bpm|次/分|次/分钟',
    );
    final int? hrv = _intValue(text, const ['HRV', 'hrv'], units: r'ms|毫秒');
    final double? sleep = _doubleValue(text, const ['睡眠', '睡眠时长', 'sleep'], units: r'h|小时');
    final int? fatigue = _intValue(text, const ['疲劳', 'fatigue'], units: r'/10');
    final int? soreness = _intValue(text, const ['酸痛', 'soreness'], units: r'/10');
    validateBodyMetricInput({
      '体重': weight, '体脂率': bodyFat, '静息心率': restingHr,
      'HRV': hrv, '睡眠': sleep, '疲劳': fatigue, '酸痛': soreness,
    });
    final DateTime measuredAt = _dateValue(text) ?? DateTime.now();
    final int matchedFieldCount = [
      weight,
      bodyFat,
      restingHr,
      hrv,
      sleep,
      fatigue,
      soreness,
    ].whereType<num>().length;

    if (matchedFieldCount == 0) {
      throw const FormatException('识别失败：没有找到可用的身体指标。');
    }

    final List<String> inheritedFieldLabels = <String>[
      if (weight == null) '体重',
      if (bodyFat == null) '体脂率',
      if (restingHr == null) '静息心率',
      if (hrv == null) 'HRV',
      if (sleep == null) '睡眠',
      if (fatigue == null) '疲劳',
      if (soreness == null) '酸痛',
    ];
    if (fallback == null && inheritedFieldLabels.isNotEmpty) {
      throw FormatException(
        '识别失败：缺少必填身体指标：${inheritedFieldLabels.join('、')}。'
        '请补全后重试；系统不会使用示例值补齐。',
      );
    }

    final DateTime now = DateTime.now();
    final BodyMetric metric = BodyMetric(
      recordedFields: {
        if (weight != null) 'weightKg', if (bodyFat != null) 'bodyFatPercentage',
        if (restingHr != null) 'restingHeartRate', if (hrv != null) 'hrvMs',
        if (sleep != null) 'sleepHours', if (fatigue != null) 'fatigueLevel',
        if (soreness != null) 'sorenessLevel',
      },
      id: 'body-snapshot-${now.millisecondsSinceEpoch}',
      measuredAt: DateTime(
        measuredAt.year,
        measuredAt.month,
        measuredAt.day,
        now.hour,
        now.minute,
      ),
      weightKg: weight ?? fallback!.weightKg,
      bodyFatPercentage: bodyFat ?? fallback!.bodyFatPercentage,
      restingHeartRate: restingHr ?? fallback!.restingHeartRate,
      hrvMs: hrv ?? fallback!.hrvMs,
      sleepHours: sleep ?? fallback!.sleepHours,
      fatigueLevel: fatigue ?? fallback!.fatigueLevel,
      sorenessLevel: soreness ?? fallback!.sorenessLevel,
      moodLabel: (fatigue ?? fallback!.fatigueLevel) >= 7 ? '偏疲劳' : '截图识别',
      source: BodyMetricSource.screenshot,
      note: inheritedFieldLabels.isEmpty
          ? '截图文字识别：全部字段来自本次识别；用户确认入库'
          : '截图文字识别：${inheritedFieldLabels.join('、')}沿用上次记录；用户确认入库',
    );

    return BodyMetricSnapshotRecognitionResult(
      metric: metric,
      matchedFieldCount: matchedFieldCount,
      inheritedFieldLabels: inheritedFieldLabels,
      sourceLabel: _sourceLabel(text),
    );
  }

  double? _doubleValue(String text, List<String> keys, {String units = ''}) {
    final token = _numericToken(text, keys, units: units);
    return token == null ? null : double.parse(token);
  }

  String? _numericToken(String text, List<String> keys, {String units = ''}) {
    for (final String key in keys) {
      final RegExp pattern = RegExp(
        '${RegExp.escape(key)}(?=\\s|[:：=为+−.0-9-]|\$)\\s*(?:[:：=]|为)?\\s*([^\\s,，;；]*)',
        caseSensitive: false,
      );
      final RegExpMatch? match = pattern.firstMatch(text);
      if (match != null) {
        // 完整读取数值与已知单位，负数、小数、指数不能被截成正整数。
        final token = match.group(1) ?? '';
        final numeric = RegExp(
          r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|[+-]?(?:NaN|Infinity))'
          '(?:$units)?\$',
          caseSensitive: false,
        ).firstMatch(token);
        final value = double.tryParse(numeric?.group(1) ?? '');
        if (value == null || !value.isFinite) {
          throw FormatException('${keys.first} 格式错误，必须提供完整的有限数值。');
        }
        return numeric!.group(1);
      }
    }
    return null;
  }

  int? _intValue(String text, List<String> keys, {String units = ''}) {
    final token = _numericToken(text, keys, units: units);
    if (token == null) return null;
    // 和 CSV 一致直接解析整数，避免先经过浮点数而丢失精度。
    final integer = int.tryParse(token);
    if (integer == null) {
      throw FormatException('${keys.first} 必须是整数，不会自动四舍五入。');
    }
    return integer;
  }

  DateTime? _dateValue(String text) {
    final RegExp pattern = RegExp(
      r'(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})日?',
    );
    final RegExpMatch? match = pattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    final int? year = int.tryParse(match.group(1) ?? '');
    final int? month = int.tryParse(match.group(2) ?? '');
    final int? day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  String _sourceLabel(String text) {
    final String lowerText = text.toLowerCase();
    if (lowerText.contains('garmin') || text.contains('佳明')) {
      return '手表截图';
    }
    if (text.contains('体脂秤') || text.contains('体脂率')) {
      return '体脂秤截图';
    }
    if (text.contains('Apple') || text.contains('健康')) {
      return '健康 App 截图';
    }
    return '截图文字';
  }
}
