import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_metric.dart';
import 'package:trainflow_ai/data/models/body_data_quality.dart';
import 'package:trainflow_ai/services/body_data_quality_service.dart';

void main() {
  final now = DateTime(2026, 9, 17, 12);
  final service = BodyDataQualityService();
  BodyDataQualityReport report(List<BodyMetric> records) =>
      service.buildReport(records, now: now);
  BodyMetric metric(int days,
          {bool verified = true, bool missing = false, double weight = 70}) =>
      BodyMetric.fromJson({
        'id': 'synthetic-$days',
        'measuredAt': now.subtract(Duration(days: days)).toIso8601String(),
        'source': 'manual',
        'sourceVerified': verified,
        'sleepHours': 7.0,
        'fatigueLevel': 3,
        if (!missing) 'weightKg': weight,
        if (!missing) 'restingHeartRate': 60,
      });
  String issues(List<BodyMetric> records) => report(records)
      .issues
      .map((e) => '${e.title}：${e.description}')
      .join('；');

  test('没有记录不可标为可用', () {
    expect(report([]).statusLabel, '无法评估');
  });
  test('一条记录明确一日覆盖，不声称连续七日或已排除异常', () {
    final result = report([metric(0)]);
    expect(result.coverageLabel, contains('1/7'));
    expect(result.statusLabel, '记录不足');
    expect(issues([metric(0)]), isNot(contains('记录连续')));
    expect(issues([metric(0)]), isNot(contains('未发现明显')));
  });
  test('同日重复不增加覆盖，七个不同自然日才显示连续', () {
    final repeated = List.generate(7, (_) => metric(0));
    expect(report(repeated).coveredDays, 1);
    expect(report(repeated).coverageLabel, contains('1/7'));
    final complete = List.generate(7, (i) => metric(i));
    expect(report(complete).coveredDays, 7);
    expect(report(complete).coverageLabel, contains('7/7'));
    expect(issues(complete), contains('连续'));
  });
  test('陈旧、未来和不可信记录不充当本窗口覆盖', () {
    final records = [
      metric(0),
      metric(1, verified: false),
      metric(-1),
      ...List.generate(7, (i) => metric(i + 8))
    ];
    final result = report(records);
    expect(result.recordCount, records.length);
    expect(result.coveredDays, 1);
    expect(result.coverageLabel, contains('1/7'));
    expect(issues(records), contains('不纳入'));
  });
  test('缺失字段不按零参与异常检测，逐项说明不能比较', () {
    final records = [metric(0, missing: true), metric(1)];
    expect(issues(records), isNot(contains('变化 70.0 kg')));
    expect(issues(records), contains('体重'));
    expect(issues(records), contains('无法比较'));
  });
  test('窗口包含第七日零点，排除前一秒、今日未来和完全缺失字段', () {
    BodyMetric at(DateTime date) => BodyMetric.fromJson({
          ...metric(0).toJson(),
          'measuredAt': date.toIso8601String(),
        });
    final result = report([
      at(DateTime(2026, 9, 11)),
      at(DateTime(2026, 9, 10, 23, 59, 59)),
      at(now.add(const Duration(minutes: 1))),
      BodyMetric.fromJson({
        'id': 'missing',
        'source': 'manual',
        'measuredAt': now.toIso8601String()
      }),
    ]);
    expect(result.coveredDays, 1);
    expect(
        result.issues.first.description, contains('2026-09-11 至 2026-09-17'));
  });

  test('跨日缺口不能称连续，已提供的异常仍用原阈值提示', () {
    final records = [metric(0, weight: 73), metric(2), metric(6)];
    expect(report(records).coverageLabel, contains('3/7'));
    expect(issues(records), contains('超过 2 kg'));
    expect(issues(records), isNot(contains('记录连续')));
  });
}
