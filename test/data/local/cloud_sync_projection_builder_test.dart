import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/local/cloud_sync_projection_builder.dart';
import 'package:trainflow_ai/data/models/cloud_sync.dart';

void main() {
  test('档案与可训练时间只投影目标、运动、经验、时间和器械', () {
    final Map<String, Map<String, dynamic>> documents =
        <String, Map<String, dynamic>>{
      'trainflow.user_profile.v1': <String, dynamic>{
        'profile': <String, dynamic>{
          'id': 'local-profile',
          'name': '不得上传',
          'age': 32,
          'gender': 'male',
          'heightCm': 172,
          'weightKg': 68,
          'injuryHistory': <String>['不得上传'],
          'trainingGoal': '提升综合体能',
          'mainSports': <String>['running', 'strength'],
          'trainingExperienceLevel': 'intermediate',
          'equipmentAccessType': 'gym',
        },
      },
      'trainflow.training_availability.v1': <String, dynamic>{
        'slots': <Map<String, dynamic>>[
          <String, dynamic>{'date': '2026-07-28T00:00:00.000'},
          <String, dynamic>{'date': '2026-07-30T00:00:00.000'},
        ],
      },
    };

    final List<CloudSyncMutation> mutations = CloudSyncProjectionBuilder.build(
      changedKey: 'trainflow.user_profile.v1',
      previousDocuments: const <String, Map<String, dynamic>>{},
      currentDocuments: documents,
    );

    expect(mutations, hasLength(1));
    expect(
      mutations.single.entityType,
      CloudSyncEntityType.trainingPreferences,
    );
    expect(
      mutations.single.payload,
      <String, Object?>{
        'goal': '提升综合体能',
        'sport_types': <String>['running', 'strength'],
        'experience_level': 'intermediate',
        'weekly_availability': <int>[2, 4],
        'equipment': <String>['gym'],
      },
    );
    expect(
      mutations.single.payload.keys,
      isNot(
        containsAll(<String>[
          'name',
          'age',
          'gender',
          'heightCm',
          'weightKg',
          'injuryHistory',
        ]),
      ),
    );
  });

  test('训练日志只为新增或改变的会话生成脱敏完成摘要', () {
    final Map<String, dynamic> unchangedLog = <String, dynamic>{
      'id': 'log-old',
      'workoutDayId': 'day-old',
      'date': '2026-07-27T08:00:00.000Z',
      'createdAt': '2026-07-27T09:00:00.000Z',
      'actualDurationMinutes': 60,
      'completionPercentage': 100,
      'completed': true,
      'rpe': 8,
      'painNote': '不得上传',
    };
    final Map<String, dynamic> newLog = <String, dynamic>{
      'id': 'log-new',
      'workoutDayId': 'day-new',
      'planItemId': 'plan-item-new',
      'date': '2026-07-28T08:00:00.000Z',
      'createdAt': '2026-07-28T09:00:00.000Z',
      'actualDurationMinutes': 45,
      'completionPercentage': 80,
      'completed': true,
      'rpe': 9,
      'painNote': '不得上传',
      'userNote': '不得上传',
      'averageHeartRate': 166,
      'exerciseRecords': <Map<String, dynamic>>[
        <String, dynamic>{'weightKg': 90},
      ],
    };
    final Map<String, Map<String, dynamic>> previous =
        <String, Map<String, dynamic>>{
      'trainflow.generated_training_plan.v1': _planDocument(),
      'trainflow.training_logs.v1': <String, dynamic>{
        'logs': <Map<String, dynamic>>[unchangedLog],
      },
    };
    final Map<String, Map<String, dynamic>> current =
        <String, Map<String, dynamic>>{
      ...previous,
      'trainflow.training_logs.v1': <String, dynamic>{
        'logs': <Map<String, dynamic>>[newLog, unchangedLog],
      },
    };

    final List<CloudSyncMutation> mutations = CloudSyncProjectionBuilder.build(
      changedKey: 'trainflow.training_logs.v1',
      previousDocuments: previous,
      currentDocuments: current,
    );

    expect(mutations, hasLength(1));
    final CloudSyncMutation mutation = mutations.single;
    expect(
      mutation.entityType,
      CloudSyncEntityType.completionSummaries,
    );
    expect(mutation.payload['duration_seconds'], 2700);
    expect(mutation.payload['completion_percentage'], 80);
    expect(mutation.payload['revoked'], isFalse);
    expect(
      mutation.payload.keys.toSet(),
      <String>{
        'plan_version_id',
        'scheduled_workout_id',
        'started_at',
        'ended_at',
        'duration_seconds',
        'completion_percentage',
        'revoked',
      },
    );
  });

  test('计划、排期和设置分别生成固定类型的白名单投影', () {
    final Map<String, Map<String, dynamic>> documents =
        <String, Map<String, dynamic>>{
      'trainflow.generated_training_plan.v1': _planDocument(),
      'trainflow.training_schedule.v1': <String, dynamic>{
        'workouts': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'schedule-1',
            'workoutDayId': 'day-new',
            'scheduledDate': '2026-07-30T00:00:00.000',
            'allocatedMinutes': 50,
            'discipline': 'running',
          },
        ],
      },
      'trainflow.reminder_settings.v1': <String, dynamic>{
        'settings': <String, dynamic>{'enabled': true},
      },
    };

    final List<CloudSyncMutation> plan = CloudSyncProjectionBuilder.build(
      changedKey: 'trainflow.generated_training_plan.v1',
      previousDocuments: const <String, Map<String, dynamic>>{},
      currentDocuments: documents,
    );
    final List<CloudSyncMutation> schedule = CloudSyncProjectionBuilder.build(
      changedKey: 'trainflow.training_schedule.v1',
      previousDocuments: const <String, Map<String, dynamic>>{},
      currentDocuments: documents,
    );
    final List<CloudSyncMutation> settings = CloudSyncProjectionBuilder.build(
      changedKey: 'trainflow.reminder_settings.v1',
      previousDocuments: const <String, Map<String, dynamic>>{},
      currentDocuments: documents,
    );

    expect(plan.single.entityType, CloudSyncEntityType.planVersions);
    expect(schedule.single.entityType, CloudSyncEntityType.scheduledWorkouts);
    expect(settings.single.entityType, CloudSyncEntityType.appSettings);
    expect(
      settings.single.payload,
      <String, Object?>{
        'locale': 'zh-CN',
        'week_starts_on': 1,
        'notifications_enabled': true,
      },
    );
  });
}

Map<String, dynamic> _planDocument() {
  return <String, dynamic>{
    'plan': <String, dynamic>{
      'id': 'local-plan',
      'title': '四周综合计划',
      'sportType': 'running',
      'createdAt': '2026-07-28T00:00:00.000Z',
      'durationWeeks': 4,
      'workoutDays': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'day-new', 'title': '节奏跑'},
      ],
    },
  };
}
