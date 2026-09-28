import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

void main() {
  test('可选来源区分缺失与空列表并保留版本', () {
    expect(PluginRef.parseOptionalList(null), isNull);
    expect(PluginRef.parseOptionalList([]), isEmpty);
    final refs = PluginRef.parseOptionalList([
      {'id': 'sport.running', 'version': '1.2.3'}
    ])!;
    expect(refs.single.toJson(), {'id': 'sport.running', 'version': '1.2.3'});
    expect(() => refs.clear(), throwsUnsupportedError);
  });
  test('来源列表严格拒绝错误结构、字段、重复和无效标识版本', () {
    for (final input in [
      1,
      {},
      [null],
      [
        {'id': 'a'}
      ],
      [
        {'id': 1, 'version': '1.0.0'}
      ],
      [
        {'id': '', 'version': '1.0.0'}
      ],
      [
        {'id': 'a', 'version': ''}
      ],
      [
        {'id': 'a', 'version': '1.0.0', 'extra': true}
      ],
      [
        {'id': 'a', 'version': '1.0.0'},
        {'id': 'a', 'version': '2.0.0'}
      ]
    ]) {
      expect(() => PluginRef.parseOptionalList(input), throwsFormatException);
    }
  });
}
