import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/guided_workout/data/guided_workout_catalog_loader.dart';
import 'package:trainflow_ai/features/guided_workout/domain/guided_workout_course.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('项目内置三级跳绳课与一个功能性循环可以加载', () async {
    final GuidedWorkoutCatalog catalog =
        await GuidedWorkoutCatalogLoader().load();

    expect(catalog.courses, hasLength(4));
    expect(
      catalog.courses
          .where(
            (GuidedWorkoutCourse item) =>
                item.kind == GuidedWorkoutCourseKind.timedCourse,
          )
          .map((GuidedWorkoutCourse item) => item.totalDurationSeconds),
      <int>[1200, 2280, 2700],
    );
    expect(
      catalog.courses
          .singleWhere(
            (GuidedWorkoutCourse item) =>
                item.kind == GuidedWorkoutCourseKind.functionalCircuit,
          )
          .id,
      'knee-ankle-stability-v1',
    );
  });

  test('三级跳绳课程总时长分别为 20、38、45 分钟', () {
    final GuidedWorkoutCatalog catalog = GuidedWorkoutCatalog.fromJson(
      jsonDecode(_validCatalogJson) as Map<String, dynamic>,
    );

    expect(
      catalog.courses
          .map((GuidedWorkoutCourse item) => item.totalDurationSeconds),
      <int>[1200, 2280, 2700],
    );
    expect(catalog.courses.first.containsExercise('双摇挑战'), isFalse);
    expect(catalog.courses[1].containsExercise('双摇挑战'), isTrue);
    expect(catalog.courses[2].containsExercise('双摇挑战'), isTrue);
  });

  test('单门课程总时长不一致时隔离该课程并记录具体中文错误', () {
    final Map<String, dynamic> json =
        jsonDecode(_validCatalogJson) as Map<String, dynamic>;
    final Map<String, dynamic> first =
        (json['courses'] as List<dynamic>).first as Map<String, dynamic>;
    first['expectedDurationSeconds'] = 1199;

    final GuidedWorkoutCatalog catalog = GuidedWorkoutCatalog.fromJson(json);

    expect(catalog.courses, hasLength(2));
    expect(catalog.errors, hasLength(1));
    expect(
      catalog.errors.single,
      contains('声明时长 1199 秒与计算时长 1200 秒不一致'),
    );
  });

  test('全部课程无效时返回具体中文错误', () {
    final Map<String, dynamic> json =
        jsonDecode(_validCatalogJson) as Map<String, dynamic>;
    for (final dynamic rawCourse in json['courses'] as List<dynamic>) {
      final Map<String, dynamic> course = rawCourse as Map<String, dynamic>;
      final Map<String, dynamic> phase =
          (course['phases'] as List<dynamic>).first as Map<String, dynamic>;
      final Map<String, dynamic> exercise =
          (phase['exercises'] as List<dynamic>).first as Map<String, dynamic>;
      exercise['durationSeconds'] = 0;
    }

    expect(
      () => GuidedWorkoutCatalog.fromJson(json),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          allOf(
            contains('没有可用的跳绳课程'),
            contains('动作时长必须大于 0 秒'),
          ),
        ),
      ),
    );
  });
}

const String _validCatalogJson = '''
{
  "courses": [
    {
      "id": "jump-rope-beginner-20",
      "title": "20 分钟入门跳绳",
      "level": "beginner",
      "expectedDurationSeconds": 1200,
      "voice": {
        "countdownLast": 5,
        "preAnnounceOnRest": true,
        "rate": 1.0,
        "enabled": true
      },
      "phases": [
        {
          "id": "warmup",
          "name": "热身",
          "exercises": [
            {"id":"warm","name":"无绳空跳","durationSeconds":180,"restSeconds":0,"repeat":1,"announce":"开始热身","cues":["轻柔落地"]}
          ]
        },
        {
          "id": "adapt",
          "name": "适应跳",
          "exercises": [
            {"id":"adapt","name":"基础跳","durationSeconds":60,"restSeconds":30,"repeat":2,"announce":"基础跳","cues":["找节奏"]}
          ]
        },
        {
          "id": "main-a",
          "name": "主训 A · 间歇",
          "exercises": [
            {"id":"main-a","name":"左右脚交替跳","durationSeconds":45,"restSeconds":15,"repeat":5,"announce":"交替跳","cues":["前脚掌落地"]}
          ]
        },
        {
          "id": "main-b",
          "name": "主训 B · 变式",
          "exercises": [
            {"id":"main-b","name":"开合跳","durationSeconds":30,"restSeconds":30,"repeat":3,"announce":"开合跳","cues":["保持稳定"]}
          ]
        },
        {
          "id": "cooldown",
          "name": "降温",
          "exercises": [
            {"id":"cooldown","name":"原地踏步","durationSeconds":120,"restSeconds":0,"repeat":1,"announce":"开始降温","cues":["放慢呼吸"]}
          ]
        },
        {
          "id": "stretch",
          "name": "拉伸",
          "exercises": [
            {"id":"stretch","name":"小腿与前臂拉伸","durationSeconds":240,"restSeconds":0,"repeat":1,"announce":"开始拉伸","cues":["保持自然呼吸"]}
          ]
        }
      ]
    },
    {
      "id": "jump-rope-standard-38",
      "title": "38 分钟标准跳绳",
      "level": "standard",
      "expectedDurationSeconds": 2280,
      "voice": {"countdownLast":5,"preAnnounceOnRest":true,"rate":1.0,"enabled":true},
      "phases": [
        {"id":"warmup","name":"热身","exercises":[{"id":"w","name":"无绳空跳","durationSeconds":300,"restSeconds":0,"repeat":1,"announce":"热身","cues":[]}]},
        {"id":"adapt","name":"适应跳","exercises":[{"id":"a1","name":"基础跳","durationSeconds":60,"restSeconds":30,"repeat":2,"announce":"基础跳","cues":[]},{"id":"a2","name":"基础跳","durationSeconds":60,"restSeconds":0,"repeat":1,"announce":"基础跳","cues":[]}]},
        {"id":"main-a","name":"主训 A · 间歇","exercises":[{"id":"ma","name":"左右脚交替跳","durationSeconds":45,"restSeconds":15,"repeat":10,"announce":"交替跳","cues":[]}]},
        {"id":"main-b","name":"主训 B · 变式","exercises":[{"id":"mb","name":"双摇挑战","durationSeconds":30,"restSeconds":30,"repeat":9,"announce":"双摇挑战，无法完成时改为快速基础跳","cues":["可改为快速基础跳"]}]},
        {"id":"cooldown","name":"降温","exercises":[{"id":"c","name":"慢速跳","durationSeconds":240,"restSeconds":0,"repeat":1,"announce":"降温","cues":[]}]},
        {"id":"stretch","name":"拉伸","exercises":[{"id":"s","name":"小腿与前臂拉伸","durationSeconds":360,"restSeconds":0,"repeat":1,"announce":"拉伸","cues":[]}]}
      ]
    },
    {
      "id": "jump-rope-advanced-45",
      "title": "45 分钟进阶跳绳",
      "level": "advanced",
      "expectedDurationSeconds": 2700,
      "voice": {"countdownLast":5,"preAnnounceOnRest":true,"rate":1.0,"enabled":true},
      "phases": [
        {"id":"warmup","name":"热身","exercises":[{"id":"w","name":"无绳空跳","durationSeconds":300,"restSeconds":0,"repeat":1,"announce":"热身","cues":[]}]},
        {"id":"adapt","name":"适应跳","exercises":[{"id":"a1","name":"基础跳","durationSeconds":60,"restSeconds":30,"repeat":2,"announce":"基础跳","cues":[]},{"id":"a2","name":"基础跳","durationSeconds":60,"restSeconds":0,"repeat":1,"announce":"基础跳","cues":[]}]},
        {"id":"main-a","name":"主训 A · 间歇","exercises":[{"id":"ma","name":"左右脚交替跳","durationSeconds":45,"restSeconds":15,"repeat":12,"announce":"交替跳","cues":[]}]},
        {"id":"main-b","name":"主训 B · 变式","exercises":[{"id":"mb","name":"双摇挑战","durationSeconds":30,"restSeconds":30,"repeat":12,"announce":"双摇挑战，无法完成时改为快速基础跳","cues":["可改为快速基础跳"]}]},
        {"id":"cooldown","name":"降温","exercises":[{"id":"c","name":"慢速跳","durationSeconds":300,"restSeconds":0,"repeat":1,"announce":"降温","cues":[]}]},
        {"id":"stretch","name":"拉伸","exercises":[{"id":"s","name":"小腿与前臂拉伸","durationSeconds":420,"restSeconds":0,"repeat":1,"announce":"拉伸","cues":[]}]}
      ]
    }
  ]
}
''';
