import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/repositories/body_metric_repository.dart';
import 'package:trainflow_ai/features/data_center/application/body_metric_controller.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/body_metric_import_service.dart';
import 'package:trainflow_ai/services/body_metric_snapshot_service.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

const _header = 'date,weight,body_fat,resting_hr,hrv,sleep,fatigue,soreness';
const _labels = ['体重', '体脂率', '静息心率', 'HRV', '睡眠', '疲劳', '酸痛'];
const _values = ['70', '18', '60', '50', '7', '0', '0'];
String _csv(List<String> values) => '$_header\n2026-09-19,${values.join(',')}';
String _snapshot(List<String> values) => [
      for (var i = 0; i < values.length; i++) '${_labels[i]} ${values[i]}'
    ].join('\n');
final _fallback = BodyMetric.fromJson({
  'id': 'synthetic-history',
  'measuredAt': '2026-09-18T08:00:00',
  'source': 'manual',
  'weightKg': 70,
  'bodyFatPercentage': 18,
  'restingHeartRate': 60,
  'hrvMs': 50,
  'sleepHours': 7,
  'fatigueLevel': 0,
  'sorenessLevel': 0,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final csv in [false, true]) {
    final name = csv ? 'CSV' : '截图';
    BodyMetric parse(List<String> values) => csv
        ? BodyMetricImportService()
            .parseCsv(_csv(values), historicalFallback: _fallback)
            .metrics
            .single
        : BodyMetricSnapshotRecognitionService()
            .recognize(_snapshot(values), fallback: _fallback)
            .metric;
    test('$name 疲劳与酸痛零值原样保留且属于本次观测', () {
      final metric = parse(_values);
      expect(metric.fatigueLevel, 0);
      expect(metric.sorenessLevel, 0);
      expect(metric.hasValue('fatigueLevel'), isTrue);
      expect(metric.hasValue('sorenessLevel'), isTrue);
    });
    test('$name 缺失字段继承零值但不当作本次观测', () {
      final metric = csv
          ? BodyMetricImportService()
              .parseCsv('date,weight\n2026-09-19,71',
                  historicalFallback: _fallback)
              .metrics
              .single
          : BodyMetricSnapshotRecognitionService()
              .recognize('体重 71', fallback: _fallback)
              .metric;
      expect(metric.fatigueLevel, 0);
      expect(metric.sorenessLevel, 0);
      expect(metric.hasValue('fatigueLevel'), isFalse);
      expect(metric.hasValue('sorenessLevel'), isFalse);
    });
    for (final item in <(int, String)>[
      (5, '-1'),
      (5, '11'),
      (5, '2.5'),
      (6, '-1'),
      (6, '11'),
      (6, '3.5'),
      (0, 'NaN'),
      (0, 'Infinity'),
      (0, '1e309'),
      (0, '-70'),
      (1, '0'),
      (2, '0'),
      (3, '-1'),
      (4, '-2'),
      (4, '0'),
      (5, '未知'),
    ]) {
      test('$name ${_labels[item.$1]}=${item.$2} 拒绝且不使用历史替代', () {
        final values = [..._values]..[item.$1] = item.$2;
        expect(
            () => parse(values),
            throwsA(isA<FormatException>().having(
                (e) => e.message, '中文字段原因', contains(_labels[item.$1]))));
      });
    }
    test('$name 上界十保留，不产生新分级', () {
      final values = [..._values]
        ..[5] = '10'
        ..[6] = '10';
      final metric = parse(values);
      expect(metric.fatigueLevel, 10);
      expect(metric.sorenessLevel, 10);
    });
  }

  test('截图单位与科学计数值完整读取，不能截取数字前缀', () {
    final metric = BodyMetricSnapshotRecognitionService()
        .recognize(
            '体重 7e1kg\n体脂率 18%\n静息心率 60bpm\nHRV 50ms\n睡眠 7h\n疲劳 0/10\n酸痛 0/10')
        .metric;
    expect(metric.weightKg, 70);
    expect(metric.fatigueLevel, 0);
    expect(metric.sorenessLevel, 0);
    expect(
        () => BodyMetricSnapshotRecognitionService()
            .recognize('体重 70abc', fallback: _fallback),
        throwsFormatException);
  });

  test('CSV 混合行只返回有效原值并解释每条跳过原因', () {
    final result = BodyMetricImportService().parseCsv('$_header\n'
        '2026-09-19,70,18,60,50,7,0,0\n'
        '2026-09-18,70,18,60,50,7,11,0\n'
        '2026-09-17,NaN,18,60,50,7,0,0');
    expect(result.metrics, hasLength(1));
    expect(result.metrics.single.fatigueLevel, 0);
    expect(result.skippedRows, 2);
    expect(result.rowErrors, hasLength(2));
    expect(result.summary, contains('第 3 行：疲劳'));
    expect(result.summary, contains('第 4 行：体重'));
  });

  test('截图整数字段直接解析，不经过浮点转换丢失原始整数', () {
    final result = BodyMetricSnapshotRecognitionService()
        .recognize('HRV 9007199254740993', fallback: _fallback);
    expect(result.metric.hrvMs, 9007199254740993);
    expect(
        () => BodyMetricSnapshotRecognitionService()
            .recognize('HRV 9223372036854775808', fallback: _fallback),
        throwsFormatException);
  });

  for (final text in [
    '静息心率 60.5',
    'HRV 50.5',
    'HRV 1e100',
    '睡眠 7kg',
    '体重 -70kg',
    '体重 70.2.3',
    '疲劳 −1',
    '疲劳 11/10',
  ]) {
    test('截图显式错误 $text 不四舍五入或退回历史', () {
      expect(
          () => BodyMetricSnapshotRecognitionService()
              .recognize('体脂率 18\n$text', fallback: _fallback),
          throwsFormatException);
    });
  }

  test('无效截图清除旧待确认结果，不能继续保存旧预览', () async {
    final storage = InMemoryLocalStorageService();
    final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final controller = container.read(bodyMetricControllerProvider.notifier);
    controller.recognizeSnapshotText(_snapshot(_values));
    expect(
        container.read(bodyMetricControllerProvider).pendingMetric, isNotNull);
    controller.recognizeSnapshotText('体重 70\n疲劳 11');
    expect(container.read(bodyMetricControllerProvider).pendingMetric, isNull);
    expect(container.read(bodyMetricControllerProvider).snapshotStatusMessage,
        contains('疲劳'));
    await controller.confirmPendingMetric();
    expect(storage.readJson('trainflow.body_metrics.v1'), isNull);
  });

  for (final csv in [false, true]) {
    test('${csv ? 'CSV' : '截图'} 无效输入不写入，零值保存重读且不改计划或签到', () async {
      final storage = InMemoryLocalStorageService();
      final container = ProviderContainer(
          overrides: [localStorageServiceProvider.overrideWithValue(storage)]);
      addTearDown(container.dispose);
      final controller = container.read(bodyMetricControllerProvider.notifier);
      final plan = container.read(trainingMvpProvider).activePlan.toJson();
      final invalid = [..._values]..[5] = '11';
      if (csv) {
        await controller.importCsv(_csv(invalid));
      } else {
        controller.recognizeSnapshotText(_snapshot(invalid));
        expect(
            container.read(bodyMetricControllerProvider).pendingMetric, isNull);
        await controller.confirmPendingMetric();
      }
      expect(storage.readJson('trainflow.body_metrics.v1'), isNull);
      if (csv) {
        await controller.importCsv(_csv(_values));
      } else {
        controller.recognizeSnapshotText(_snapshot(_values));
        expect(storage.readJson('trainflow.body_metrics.v1'), isNull);
        expect(
            container
                .read(bodyMetricControllerProvider)
                .pendingMetric!
                .fatigueLevel,
            0);
        await controller.confirmPendingMetric();
      }
      final saved = PersistedBodyMetricRepository(storage).listMetrics().single;
      expect(saved.fatigueLevel, 0);
      expect(saved.sorenessLevel, 0);
      expect(saved.hasValue('fatigueLevel'), isTrue);
      expect(storage.readJson('trainflow.daily_check_ins.v1'), isNull);
      expect(container.read(trainingMvpProvider).activePlan.toJson(), plan);
    });
  }
}
