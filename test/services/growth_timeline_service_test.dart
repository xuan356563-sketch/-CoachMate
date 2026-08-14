import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/achievement.dart';
import 'package:trainflow_ai/data/models/daily_check_in_record.dart';
import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/models/growth_timeline.dart';
import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/services/growth_timeline_service.dart';

void main() {
  test('统一时间线聚合现有事实并按时间倒序排列', () {
    final List<GrowthTimelineEntry> entries = GrowthTimelineService().build(
      evidenceEvents: <GrowthEvidenceEvent>[
        _event(id: 'training-1', type: GrowthEventType.training, day: 1),
        _event(id: 'health-1', type: GrowthEventType.health, day: 2),
      ],
      checkIns: <DailyCheckInRecord>[
        DailyCheckInRecord(
          id: 'check-in-1',
          localDate: DateTime(2026, 7, 3),
          confirmedAt: DateTime(2026, 7, 3, 8),
          source: DailyCheckInSource.prefilled,
          continuityKind: DailyContinuityKind.plannedRest,
        ),
      ],
      achievements: <AchievementRecord>[
        AchievementRecord(
          id: 'achievement-1',
          definitionId: 'listen_to_body',
          title: '听身体的',
          description: '主动做出安全决定',
          category: AchievementCategory.safety,
          currentValue: 1,
          targetValue: 1,
          unlockedAt: DateTime(2026, 7, 4, 9),
          sourceLabel: '本地状态派生成就',
        ),
      ],
      weeklyReports: <WeeklyReport>[
        WeeklyReport(
          id: 'week-1',
          weekLabel: '7月第1周',
          generatedAt: DateTime(2026, 7, 5, 9),
          completedWorkouts: 3,
          plannedWorkouts: 4,
          completionRate: 0.75,
          loadTrendLabel: '稳定',
          decisionReview: '完成恢复安排',
          recoverySummary: '继续保持',
          highlights: const <String>[],
          nextWeekFocus: const <String>[],
        ),
      ],
      races: <RacePlan>[_race(status: 'active', day: 6)],
    );

    expect(entries, hasLength(6));
    expect(
      entries.map((GrowthTimelineEntry entry) => entry.type),
      <GrowthTimelineEntryType>[
        GrowthTimelineEntryType.race,
        GrowthTimelineEntryType.weeklyReport,
        GrowthTimelineEntryType.achievement,
        GrowthTimelineEntryType.checkIn,
        GrowthTimelineEntryType.health,
        GrowthTimelineEntryType.training,
      ],
    );
    expect(entries[3].title, '按计划恢复');
    expect(entries.last.xp, 10);
  });

  test('默认排除撤销证据和撤销正式赛果', () {
    final List<GrowthTimelineEntry> entries = GrowthTimelineService().build(
      evidenceEvents: <GrowthEvidenceEvent>[
        _event(
            id: 'revoked',
            type: GrowthEventType.training,
            day: 1,
            revoked: true),
      ],
      checkIns: const <DailyCheckInRecord>[],
      achievements: const <AchievementRecord>[],
      weeklyReports: const <WeeklyReport>[],
      races: <RacePlan>[_race(status: 'revoked', day: 2)],
    );

    expect(entries, isEmpty);
  });

  test('开启审计模式时只恢复撤销成长证据不恢复撤销赛果', () {
    final List<GrowthTimelineEntry> entries = GrowthTimelineService().build(
      evidenceEvents: <GrowthEvidenceEvent>[
        _event(
            id: 'revoked',
            type: GrowthEventType.training,
            day: 1,
            revoked: true),
      ],
      checkIns: const <DailyCheckInRecord>[],
      achievements: const <AchievementRecord>[],
      weeklyReports: const <WeeklyReport>[],
      races: <RacePlan>[_race(status: 'revoked', day: 2)],
      includeRevokedEvidence: true,
    );

    expect(entries, hasLength(1));
    expect(entries.single.isRevoked, isTrue);
  });
}

GrowthEvidenceEvent _event({
  required String id,
  required GrowthEventType type,
  required int day,
  bool revoked = false,
}) {
  return GrowthEvidenceEvent.fromJson(<String, dynamic>{
    'eventId': id,
    'athleteProfileId': 'athlete-1',
    'eventType': type.jsonValue,
    'title': type == GrowthEventType.training ? '完成训练' : '记录健康数据',
    'description': '可追溯事实',
    'occurredAt': '2026-07-${day.toString().padLeft(2, '0')}T08:00:00.000Z',
    'occurredOn': '2026-07-${day.toString().padLeft(2, '0')}',
    'sourceTable':
        type == GrowthEventType.training ? 'training_logs' : 'body_metrics',
    'sourceId': 'source-$id',
    'xpComponents': <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'completion',
        'amount': 10,
        'reason': '测试',
      },
    ],
    'impacts': <Map<String, dynamic>>[],
    'confidence': 'high',
    'createdAt': '2026-07-${day.toString().padLeft(2, '0')}T08:00:00.000Z',
    'updatedAt': '2026-07-${day.toString().padLeft(2, '0')}T08:00:00.000Z',
    if (revoked)
      'revokedAt':
          '2026-07-${(day + 1).toString().padLeft(2, '0')}T08:00:00.000Z',
  });
}

RacePlan _race({required String status, required int day}) {
  return RacePlan.fromJson(<String, dynamic>{
    'id': 'race-$status',
    'type': 'road_running',
    'name': '城市路跑',
    'raceDate': '2026-07-${day.toString().padLeft(2, '0')}',
    'officialRaceResult': <String, dynamic>{
      'durationSeconds': 3600,
      'confirmedAt': '2026-07-${day.toString().padLeft(2, '0')}T10:00:00.000Z',
      'trainingLogId': 'log-$status',
      'workoutDayId': 'workout-$status',
      'status': status,
      if (status == 'revoked')
        'revokedAt':
            '2026-07-${(day + 1).toString().padLeft(2, '0')}T10:00:00.000Z',
    },
  });
}
