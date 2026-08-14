import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_metric_snapshot.dart';
import 'package:trainflow_ai/services/body_metric_snapshot_service.dart';

void main() {
  final BodyMetric fallbackMetric = BodyMetric(
    id: 'body-metric-fallback',
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
    note: '已确认的历史记录',
  );

  final BodyMetricSnapshotRecognitionService service =
      BodyMetricSnapshotRecognitionService();

  test('没有旧值时缺少必填字段会返回中文验证错误且不补造数值', () {
    expect(
      () => service.recognize('体重 72.9\n静息心率 57'),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          '错误信息',
          '识别失败：缺少必填身体指标：体脂率、HRV、睡眠、疲劳、酸痛。请补全后重试；系统不会使用示例值补齐。',
        ),
      ),
    );
  });

  test('完整截图只使用识别值且不标记沿用旧值', () {
    final BodyMetricSnapshotRecognitionResult result = service.recognize('''
体脂秤截图 2026-07-10
体重 72.9
体脂率 18.1
静息心率 57
HRV 55
睡眠 7.5
疲劳 3
酸痛 2
''');

    expect(result.matchedFieldCount, 7);
    expect(result.inheritedFieldLabels, isEmpty);
    expect(result.metric.weightKg, 72.9);
    expect(result.metric.bodyFatPercentage, 18.1);
    expect(result.metric.restingHeartRate, 57);
    expect(result.metric.hrvMs, 55);
    expect(result.metric.sleepHours, 7.5);
    expect(result.metric.fatigueLevel, 3);
    expect(result.metric.sorenessLevel, 2);
    expect(result.metric.note, '截图文字识别：全部字段来自本次识别；用户确认入库');
    expect(result.summary, isNot(contains('沿用上次')));
  });

  test('提供旧值时仅缺失字段沿用旧记录并在结果中明确列出', () {
    final BodyMetricSnapshotRecognitionResult result = service.recognize(
      'Apple 健康 2026-07-10\n体重 72.9\n静息心率 57\n疲劳 7',
      fallback: fallbackMetric,
    );

    expect(result.matchedFieldCount, 3);
    expect(
      result.inheritedFieldLabels,
      <String>['体脂率', 'HRV', '睡眠', '酸痛'],
    );
    expect(result.metric.weightKg, 72.9);
    expect(result.metric.restingHeartRate, 57);
    expect(result.metric.fatigueLevel, 7);
    expect(result.metric.bodyFatPercentage, fallbackMetric.bodyFatPercentage);
    expect(result.metric.hrvMs, fallbackMetric.hrvMs);
    expect(result.metric.sleepHours, fallbackMetric.sleepHours);
    expect(result.metric.sorenessLevel, fallbackMetric.sorenessLevel);
    expect(
      result.metric.note,
      '截图文字识别：体脂率、HRV、睡眠、酸痛沿用上次记录；用户确认入库',
    );
    expect(result.summary, contains('沿用上次 4 项：体脂率、HRV、睡眠、酸痛'));
  });

  test('即使提供旧值也不能把未识别任何指标的文字复制成新记录', () {
    expect(
      () => service.recognize('这段文字没有身体指标', fallback: fallbackMetric),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          '错误信息',
          '识别失败：没有找到可用的身体指标。',
        ),
      ),
    );
  });
}
