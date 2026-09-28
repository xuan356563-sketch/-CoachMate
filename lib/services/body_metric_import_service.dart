import '../data/models/body_metric.dart';
import '../data/models/body_metric_import.dart';
import 'body_metric_input_validation.dart';

class BodyMetricImportService {
  BodyMetricImportResult parseCsv(
    String rawText, {
    BodyMetric? historicalFallback,
  }) {
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
    final List<BodyMetric> metrics = <BodyMetric>[];
    final Map<String, List<String>> inheritedFieldLabelsByMetricId =
        <String, List<String>>{};
    final List<String> rowErrors = <String>[];
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
        final double? weight = _nullableDouble(
          row,
          const ['weight_kg', 'weight', '体重'],
          fieldLabel: '体重',
        );
        final double? bodyFat = _nullableDouble(
          row,
          const ['body_fat_percentage', 'body_fat', '体脂率'],
          fieldLabel: '体脂率',
        );
        final int? restingHr = _nullableInt(
          row,
          const ['resting_heart_rate', 'resting_hr', '静息心率'],
          fieldLabel: '静息心率',
        );
        final int? hrv = _nullableInt(
          row,
          const ['hrv_ms', 'hrv'],
          fieldLabel: 'HRV',
        );
        final double? sleep = _nullableDouble(
          row,
          const ['sleep_hours', 'sleep', '睡眠'],
          fieldLabel: '睡眠',
        );
        final int? fatigue = _nullableInt(
          row,
          const ['fatigue_level', 'fatigue', '疲劳'],
          fieldLabel: '疲劳',
        );
        final int? soreness = _nullableInt(
          row,
          const ['soreness_level', 'soreness', '酸痛'],
          fieldLabel: '酸痛',
        );

        validateBodyMetricInput({
          '体重': weight, '体脂率': bodyFat, '静息心率': restingHr,
          'HRV': hrv, '睡眠': sleep, '疲劳': fatigue, '酸痛': soreness,
        });
        final int matchedFieldCount = <num?>[
          weight,
          bodyFat,
          restingHr,
          hrv,
          sleep,
          fatigue,
          soreness,
        ].whereType<num>().length;
        if (matchedFieldCount == 0) {
          throw const FormatException('没有找到可用的身体指标，不能仅复制历史值。');
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
        if (historicalFallback == null && inheritedFieldLabels.isNotEmpty) {
          throw FormatException(
            '缺少必填身体指标：${inheritedFieldLabels.join('、')}。'
            '系统不会使用示例值补齐。',
          );
        }

        final String metricId = 'body-csv-${measuredAt.millisecondsSinceEpoch}';
        final int resolvedFatigue =
            fatigue ?? historicalFallback!.fatigueLevel;
        final BodyMetric metric = BodyMetric(
      recordedFields: {
        if (weight != null) 'weightKg', if (bodyFat != null) 'bodyFatPercentage',
        if (restingHr != null) 'restingHeartRate', if (hrv != null) 'hrvMs',
        if (sleep != null) 'sleepHours', if (fatigue != null) 'fatigueLevel',
        if (soreness != null) 'sorenessLevel',
      },
          id: metricId,
          measuredAt: measuredAt,
          weightKg: weight ?? historicalFallback!.weightKg,
          bodyFatPercentage: bodyFat ?? historicalFallback!.bodyFatPercentage,
          restingHeartRate: restingHr ?? historicalFallback!.restingHeartRate,
          hrvMs: hrv ?? historicalFallback!.hrvMs,
          sleepHours: sleep ?? historicalFallback!.sleepHours,
          fatigueLevel: resolvedFatigue,
          sorenessLevel: soreness ?? historicalFallback!.sorenessLevel,
          moodLabel: resolvedFatigue >= 7 ? '偏疲劳' : 'CSV 导入',
          source: BodyMetricSource.importFile,
          note: inheritedFieldLabels.isEmpty
              ? '身体数据 CSV 导入：全部字段来自本行'
              : '身体数据 CSV 导入：${inheritedFieldLabels.join('、')}沿用已保存历史值',
        );
        metrics.add(metric);
        if (inheritedFieldLabels.isNotEmpty) {
          inheritedFieldLabelsByMetricId[metricId] = inheritedFieldLabels;
        }
      } on FormatException catch (error) {
        skippedRows += 1;
        rowErrors.add('第 ${index + 1} 行：${error.message}');
      } catch (_) {
        skippedRows += 1;
        rowErrors.add('第 ${index + 1} 行：字段格式无法识别。');
      }
    }

    if (metrics.isEmpty) {
      if (rowErrors.isNotEmpty) {
        throw FormatException('导入失败：${rowErrors.first}');
      }
      throw const FormatException('导入失败：没有解析到有效身体数据。');
    }

    metrics.sort(
      (BodyMetric a, BodyMetric b) => b.measuredAt.compareTo(a.measuredAt),
    );
    return BodyMetricImportResult(
      metrics: metrics,
      skippedRows: skippedRows,
      sourceLabel: 'CSV 文件',
      inheritedFieldLabelsByMetricId: inheritedFieldLabelsByMetricId,
      rowErrors: rowErrors,
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

  double? _nullableDouble(
    Map<String, String> row,
    List<String> keys, {
    required String fieldLabel,
  }) {
    final String rawValue = _valueFor(row, keys, mustExist: false);
    if (rawValue.isEmpty) {
      return null;
    }
    final double? value = double.tryParse(rawValue);
    if (value == null) {
      throw FormatException('$fieldLabel 格式错误。');
    }
    return value;
  }

  int? _nullableInt(
    Map<String, String> row,
    List<String> keys, {
    required String fieldLabel,
  }) {
    final String rawValue = _valueFor(row, keys, mustExist: false);
    if (rawValue.isEmpty) {
      return null;
    }
    final int? value = int.tryParse(rawValue);
    if (value == null) {
      throw FormatException('$fieldLabel 格式错误。');
    }
    return value;
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
