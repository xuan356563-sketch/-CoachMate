import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/constants/app_brand.dart';

void main() {
  test('iOS 主目标保留发布身份并展示练搭 CoachMate', () {
    final String project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final String infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

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
    expect(infoPlist, contains('<string>${AppBrand.displayName}</string>'));
  });
}
