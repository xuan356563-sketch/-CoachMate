import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/content_catalog_export.dart';

void main() {
  test('Flutter 内容导出覆盖全部可复用业务内容和演示数据分类', () {
    final Map<String, dynamic> source = buildFlutterContentSource(
      projectRoot: Directory.current,
    );

    expect(source['exercises'], hasLength(239));
    expect(source['guided_courses'], hasLength(4));
    expect(source['training_plans'], hasLength(1));
    final resources = source['sport_resources'] as List;
    expect(resources, hasLength(8));
    expect(resources.where((r) => r['kind'] == 'assessment'), hasLength(4));
    expect(resources.where((r) => r['kind'] == 'plan'), hasLength(4));
    expect(source['starter_program_days'], hasLength(90));
    expect(source['motion_checks'], hasLength(8));
    expect(source['meal_guides'], hasLength(3));
    expect(source['achievements'], hasLength(7));
    expect(source['knowledge_books'], hasLength(4));
    expect(source['knowledge_quotes'], hasLength(5));
    expect(source['knowledge_citation_links'], hasLength(5));

    final Map<String, dynamic> fixtures =
        source['demo_fixtures'] as Map<String, dynamic>;
    expect(fixtures['races'], hasLength(2));
    expect(fixtures['body_metrics'], hasLength(7));
  });

  test('动作媒体统计保持当前运行时覆盖口径', () {
    final Map<String, dynamic> source = buildFlutterContentSource(
      projectRoot: Directory.current,
    );
    final Map<String, dynamic> statistics =
        source['statistics'] as Map<String, dynamic>;

    expect(statistics['exercise_count'], 239);
    expect(statistics['exercise_with_media_count'], 185);
    expect(statistics['exercise_media_file_count'], 368);
    expect(statistics['exercise_paired_media_count'], 183);
    expect(statistics['exercise_single_media_count'], 2);
    expect(statistics['exercise_placeholder_count'], 54);
    expect(statistics['ai_demo_slug_count'], 163);
    expect(statistics['active_ai_media_exercise_count'], 158);
    expect(statistics['active_exercise_demo_set'], 'female');
  });
}
