import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_metric_import.dart';
import 'package:trainflow_ai/services/body_metric_import_service.dart';

void main() {
  final BodyMetric historicalFallback = BodyMetric(
    id: 'body-metric-history',
    measuredAt: DateTime(2026, 7, 9, 7, 20),
    weightKg: 73.8,
    bodyFatPercentage: 18.6,
    restingHeartRate: 58,
    hrvMs: 52,
    sleepHours: 7.1,
    fatigueLevel: 4,
    sorenessLevel: 3,
    moodLabel: '稳定',
    source: BodyMetricSource.manual,
    note: '已确认历史记录',
  );
  final BodyMetricImportService service = BodyMetricImportService();

  test('无历史记录时 CSV 缺少必填身体指标会拒绝且不使用示例值', () {
    expect(
      () => service.parseCsv('''
date,weight_kg,resting_heart_rate,hrv_ms
2026-07-10,73.4,56,54
'''),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          '错误信息',
          '导入失败：第 2 行：缺少必填身体指标：体脂率、睡眠、疲劳、酸痛。系统不会使用示例值补齐。',
        ),
      ),
    );
  });

  test('完整 CSV 全部使用本行值且不标记沿用历史值', () {
    final BodyMetricImportResult result = service.parseCsv('''
date,weight_kg,body_fat_percentage,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level,soreness_level
2026-07-10,73.4,18.2,56,54,7.2,4,2
''');

    expect(result.metrics, hasLength(1));
    expect(result.inheritedFieldLabelsByMetricId, isEmpty);
    expect(result.metrics.single.weightKg, 73.4);
    expect(result.metrics.single.bodyFatPercentage, 18.2);
    expect(result.metrics.single.sleepHours, 7.2);
    expect(result.metrics.single.sorenessLevel, 2);
    expect(result.metrics.single.note, '身体数据 CSV 导入：全部字段来自本行');
    expect(result.summary, isNot(contains('沿用')));
  });

  test('提供历史记录时 CSV 仅缺失字段沿用并在结果与备注中标识', () {
    final BodyMetricImportResult result = service.parseCsv(
      '''
date,weight_kg,resting_heart_rate,hrv_ms
2026-07-10,73.4,56,54
''',
      historicalFallback: historicalFallback,
    );

    final BodyMetric metric = result.metrics.single;
    expect(metric.weightKg, 73.4);
    expect(metric.restingHeartRate, 56);
    expect(metric.hrvMs, 54);
    expect(metric.bodyFatPercentage, historicalFallback.bodyFatPercentage);
    expect(metric.sleepHours, historicalFallback.sleepHours);
    expect(metric.fatigueLevel, historicalFallback.fatigueLevel);
    expect(metric.sorenessLevel, historicalFallback.sorenessLevel);
    expect(
      result.inheritedFieldLabelsByMetricId[metric.id],
      <String>['体脂率', '睡眠', '疲劳', '酸痛'],
    );
    expect(
      metric.note,
      '身体数据 CSV 导入：体脂率、睡眠、疲劳、酸痛沿用已保存历史值',
    );
    expect(
      result.summary,
      contains('其中 1 条沿用已保存历史值 4 项：体脂率、睡眠、疲劳、酸痛'),
    );
  });

  test('字段存在但格式错误时不得用历史记录替代', () {
    expect(
      () => service.parseCsv(
        '''
date,weight_kg,body_fat_percentage,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level,soreness_level
2026-07-10,73.4,不是数值,56,54,7.2,4,2
''',
        historicalFallback: historicalFallback,
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          '错误信息',
          '导入失败：第 2 行：体脂率 格式错误。',
        ),
      ),
    );
  });

  test('即使提供历史记录也不能仅凭日期复制整条旧记录', () {
    expect(
      () => service.parseCsv(
        '''
date,weight_kg,body_fat_percentage,resting_heart_rate,hrv_ms,sleep_hours,fatigue_level,soreness_level
2026-07-10,,,,,,,
''',
        historicalFallback: historicalFallback,
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          '错误信息',
          '导入失败：第 2 行：没有找到可用的身体指标，不能仅复制历史值。',
        ),
      ),
    );
  });
}
