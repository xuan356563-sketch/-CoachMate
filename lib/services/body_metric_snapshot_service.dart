import '../data/models/body_metric.dart';
import '../data/models/body_metric_snapshot.dart';

class BodyMetricSnapshotRecognitionService {
  BodyMetricSnapshotRecognitionResult recognize(
    String rawText, {
    BodyMetric? fallback,
  }) {
    final String text = rawText.trim();
    if (text.isEmpty) {
      throw const FormatException('识别失败：请粘贴体脂秤、手表或跑步 App 截图中的文字。');
    }

    final double? weight = _doubleValue(text, const ['体重', 'weight']);
    final double? bodyFat = _doubleValue(text, const ['体脂率', '体脂', 'body fat']);
    final int? restingHr = _intValue(
      text,
      const ['静息心率', '静息心', 'resting heart rate', 'resting hr'],
    );
    final int? hrv = _intValue(text, const ['hrv', 'HRV']);
    final double? sleep = _doubleValue(text, const ['睡眠时长', '睡眠', 'sleep']);
    final int? fatigue = _intValue(text, const ['疲劳', 'fatigue']);
    final int? soreness = _intValue(text, const ['酸痛', 'soreness']);
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

    final DateTime now = DateTime.now();
    final BodyMetric metric = BodyMetric(
      id: 'body-snapshot-${now.millisecondsSinceEpoch}',
      measuredAt: DateTime(
        measuredAt.year,
        measuredAt.month,
        measuredAt.day,
        now.hour,
        now.minute,
      ),
      weightKg: weight ?? fallback?.weightKg ?? 73.8,
      bodyFatPercentage: bodyFat ?? fallback?.bodyFatPercentage ?? 18.6,
      restingHeartRate: restingHr ?? fallback?.restingHeartRate ?? 58,
      hrvMs: hrv ?? fallback?.hrvMs ?? 52,
      sleepHours: sleep ?? fallback?.sleepHours ?? 7.0,
      fatigueLevel:
          (fatigue ?? fallback?.fatigueLevel ?? 4).clamp(1, 10).toInt(),
      sorenessLevel:
          (soreness ?? fallback?.sorenessLevel ?? 3).clamp(1, 10).toInt(),
      moodLabel: (fatigue ?? fallback?.fatigueLevel ?? 4) >= 7 ? '偏疲劳' : '截图识别',
      source: BodyMetricSource.screenshot,
      note: '截图识别 Mock：用户确认入库',
    );

    return BodyMetricSnapshotRecognitionResult(
      metric: metric,
      matchedFieldCount: matchedFieldCount,
      sourceLabel: _sourceLabel(text),
    );
  }

  double? _doubleValue(String text, List<String> keys) {
    for (final String key in keys) {
      final RegExp pattern = RegExp(
        '${RegExp.escape(key)}\\s*(?:[:：=]|为)?\\s*([0-9]+(?:\\.[0-9]+)?)',
        caseSensitive: false,
      );
      final RegExpMatch? match = pattern.firstMatch(text);
      if (match != null) {
        return double.tryParse(match.group(1) ?? '');
      }
    }
    return null;
  }

  int? _intValue(String text, List<String> keys) {
    final double? value = _doubleValue(text, keys);
    return value?.round();
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
