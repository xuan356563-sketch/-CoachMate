import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS 主目标与测试目标统一使用智练 TrainMate 正式标识', () {
    final String project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(
      RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = com\.zhilian\.trainmate;',
      ).allMatches(project).length,
      3,
    );
    expect(
      RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = com\.zhilian\.trainmate\.RunnerTests;',
      ).allMatches(project).length,
      3,
    );
    expect(project, isNot(contains('PRODUCT_BUNDLE_IDENTIFIER = com.example')));
    expect(project, contains('DEVELOPMENT_TEAM = 4XKF438CG2;'));
  });
}
