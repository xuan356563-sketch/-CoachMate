import '../data/models/body_metric.dart';
import '../data/models/body_metric_import.dart';

class BodyMetricImportService {
  BodyMetricImportResult parseCsv(String rawText) {
    final List<String> lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) {
      throw const FormatException('导入失败：CSV 至少需要表头和一行数据。');
    }

    final List<String> headers = _splitCsvLine(lines.first)
        .map((String value) => value.trim().toLowerCase())
        .toList();
    final List<BodyMetric> metrics = [];
    int skippedRows = 0;

    for (int index = 1; index < lines.length; index += 1) {
      final List<String> cells = _splitCsvLine(lines[index]);
      try {
        final Map<String, String> row = _rowMap(headers, cells);
        final DateTime measuredAt = _requiredDate(row, const [
          'measured_at',
          'date',
          '日期',
        ]);
        final double weight = _requiredDouble(row, const [
          'weight_kg',
          'weight',
          '体重',
        ]);
        final int restingHr = _requiredInt(row, const [
          'resting_heart_rate',
          'resting_hr',
          '静息心率',
        ]);
        final int hrv = _requiredInt(row, const ['hrv_ms', 'hrv']);
        final double sleep = _optionalDouble(
          row,
          const ['sleep_hours', 'sleep', '睡眠'],
          fallback: 7.0,
        );
        final int fatigue = _optionalInt(
          row,
          const ['fatigue_level', 'fatigue', '疲劳'],
          fallback: 4,
        );
        final int soreness = _optionalInt(
          row,
          const ['soreness_level', 'soreness', '酸痛'],
          fallback: 3,
        );
        final double bodyFat = _optionalDouble(
          row,
          const ['body_fat_percentage', 'body_fat', '体脂率'],
          fallback: 18.6,
        );

        metrics.add(
          BodyMetric(
            id: 'body-csv-${measuredAt.millisecondsSinceEpoch}',
            measuredAt: measuredAt,
            weightKg: weight,
            bodyFatPercentage: bodyFat,
            restingHeartRate: restingHr,
            hrvMs: hrv,
            sleepHours: sleep,
            fatigueLevel: fatigue.clamp(1, 10).toInt(),
            sorenessLevel: soreness.clamp(1, 10).toInt(),
            moodLabel: fatigue >= 7 ? '偏疲劳' : 'CSV 导入',
            source: BodyMetricSource.importFile,
            note: '身体数据 CSV 导入',
          ),
        );
      } catch (_) {
        skippedRows += 1;
      }
    }

    if (metrics.isEmpty) {
      throw const FormatException('导入失败：没有解析到有效身体数据。');
    }

    metrics.sort(
      (BodyMetric a, BodyMetric b) => b.measuredAt.compareTo(a.measuredAt),
    );
    return BodyMetricImportResult(
      metrics: metrics,
      skippedRows: skippedRows,
      sourceLabel: 'CSV 文件',
    );
  }

  Map<String, String> _rowMap(List<String> headers, List<String> cells) {
    return {
      for (int index = 0; index < headers.length; index += 1)
        headers[index]: index < cells.length ? cells[index].trim() : '',
    };
  }

  DateTime _requiredDate(Map<String, String> row, List<String> keys) {
    final String value = _valueFor(row, keys);
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FormatException('日期格式错误。');
    }
    return parsed;
  }

  double _requiredDouble(Map<String, String> row, List<String> keys) {
    final double? value = double.tryParse(_valueFor(row, keys));
    if (value == null) {
      throw const FormatException('数值格式错误。');
    }
    return value;
  }

  int _requiredInt(Map<String, String> row, List<String> keys) {
    final int? value = int.tryParse(_valueFor(row, keys));
    if (value == null) {
      throw const FormatException('整数格式错误。');
    }
    return value;
  }

  double _optionalDouble(
    Map<String, String> row,
    List<String> keys, {
    required double fallback,
  }) {
    final String value = _valueFor(row, keys, mustExist: false);
    return double.tryParse(value) ?? fallback;
  }

  int _optionalInt(
    Map<String, String> row,
    List<String> keys, {
    required int fallback,
  }) {
    final String value = _valueFor(row, keys, mustExist: false);
    return int.tryParse(value) ?? fallback;
  }

  String _valueFor(
    Map<String, String> row,
    List<String> keys, {
    bool mustExist = true,
  }) {
    for (final String key in keys) {
      final String value = row[key] ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    if (mustExist) {
      throw const FormatException('缺少必要字段。');
    }
    return '';
  }

  List<String> _splitCsvLine(String line) {
    final List<String> values = [];
    final StringBuffer buffer = StringBuffer();
    bool inQuotes = false;

    for (int index = 0; index < line.length; index += 1) {
      final String char = line[index];
      if (char == '"') {
        if (inQuotes && index + 1 < line.length && line[index + 1] == '"') {
          buffer.write('"');
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }
}
