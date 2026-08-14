import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('干净副本测试脚本提供中文帮助且不会直接运行测试', () async {
    final ProcessResult result = await Process.run(
      'bash',
      <String>['scripts/run_flutter_tests_clean_copy.sh', '--help'],
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString(), contains('在临时干净副本中运行 Flutter 测试'));
    expect(result.stdout.toString(), contains('原工作区不会被清理或修改'));
  });
}
