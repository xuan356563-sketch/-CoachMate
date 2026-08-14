import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/workout_day.dart';
import 'package:trainflow_ai/services/growth_engine.dart';

void main() {
  final GrowthEngine engine = GrowthEngine(
    clock: () => DateTime(2026, 7, 14, 12),
  );

  test('按发生日、发生时间和事件 ID 确定性结算每日 XP 上限', () {
    final DateTime occurredOn = DateTime(2026, 7, 13);
    final List<GrowthEvidenceEvent> events = <GrowthEvidenceEvent>[
      _event(
        id: 'training_logs:b',
        occurredAt: DateTime(2026, 7, 13, 9),
        occurredOn: occurredOn,
        components: const <GrowthXpComponent>[
          GrowthXpComponent(
            type: GrowthXpComponentType.completion,
            amount: 30,
            reason: '完成训练',
          ),
          GrowthXpComponent(
            type: GrowthXpComponentType.dataQuality,
            amount: 10,
            reason: '数据完整',
          ),
        ],
      ),
      _event(
        id: 'health_snapshots:a',
        occurredAt: DateTime(2026, 7, 13, 8),
        occurredOn: occurredOn,
        components: const <GrowthXpComponent>[
          GrowthXpComponent(
            type: GrowthXpComponentType.dailyHealth,
            amount: 5,
            reason: '健康记录',
          ),
        ],
      ),
      _event(
        id: 'training_logs:c',
        occurredAt: DateTime(2026, 7, 13, 10),
        occurredOn: occurredOn,
        components: const <GrowthXpComponent>[
          GrowthXpComponent(
            type: GrowthXpComponentType.completion,
            amount: 30,
            reason: '第二次训练',
          ),
        ],
      ),
    ];

    final DailyXpSettlement settlement = engine.settleDailyXp(
      occurredOn: occurredOn,
      events: events,
    );

    expect(settlement.rawTotal, 75);
    expect(settlement.awardedTotal, 50);
    expect(settlement.awardFor('health_snapshots:a'), 5);
    expect(settlement.awardFor('training_logs:b'), 40);
    expect(settlement.awardFor('training_logs:c'), 5);
  });

  test('同日健康和安全分量各只发放一次，撤销事件不参与结算', () {
    final DateTime occurredOn = DateTime(2026, 7, 14);
    final List<GrowthEvidenceEvent> events = <GrowthEvidenceEvent>[
      _event(
        id: 'health_snapshots:first',
        occurredAt: DateTime(2026, 7, 14, 7),
        occurredOn: occurredOn,
        components: const <GrowthXpComponent>[
          GrowthXpComponent(
            type: GrowthXpComponentType.dailyHealth,
            amount: 5,
            reason: '晨间记录',
          ),
        ],
      ),
      _event(
        id: 'health_snapshots:second',
        occurredAt: DateTime(2026, 7, 14, 8),
        occurredOn: occurredOn,
        components: const <GrowthXpComponent>[
          GrowthXpComponent(
            type: GrowthXpComponentType.dailyHealth,
            amount: 5,
            reason: '重复记录',
          ),
        ],
      ),
      _event(
        id: 'training_logs:safe',
        occurredAt: DateTime(2026, 7, 14, 9),
        occurredOn: occurredOn,
        components: const <GrowthXpComponent>[
          GrowthXpComponent(
            type: GrowthXpComponentType.safetyDecision,
            amount: 5,
            reason: '接受降级',
          ),
        ],
      ),
      _event(
        id: 'training_logs:revoked',
        occurredAt: DateTime(2026, 7, 14, 10),
        occurredOn: occurredOn,
        components: const <GrowthXpComponent>[
          GrowthXpComponent(
            type: GrowthXpComponentType.completion,
            amount: 30,
            reason: '已撤销训练',
          ),
        ],
        revokedAt: DateTime(2026, 7, 14, 11),
      ),
    ];

    final DailyXpSettlement settlement = engine.settleDailyXp(
      occurredOn: occurredOn,
      events: events,
    );

    expect(settlement.rawTotal, 15);
    expect(settlement.awardedTotal, 10);
    expect(settlement.awardFor('health_snapshots:first'), 5);
    expect(settlement.awardFor('health_snapshots:second'), 0);
    expect(settlement.awardFor('training_logs:safe'), 5);
    expect(settlement.awardFor('training_logs:revoked'), 0);
  });

  test('等级只升不降，当前 XP 可因事件撤销而回退', () {
    final GrowthLevelProgress progress = engine.buildLevelProgress(
      events: <GrowthEvidenceEvent>[
        _event(
          id: 'training_logs:one',
          occurredAt: DateTime(2026, 7, 10, 8),
          occurredOn: DateTime(2026, 7, 10),
          components: const <GrowthXpComponent>[
            GrowthXpComponent(
              type: GrowthXpComponentType.completion,
              amount: 30,
              reason: '训练',
            ),
          ],
        ),
      ],
      previous: const GrowthLevelState(peakXp: 1500, peakLevel: 4),
    );

    expect(progress.currentXp, 30);
    expect(progress.peakXp, 1500);
    expect(progress.level, 4);
    expect(progress.nextLevelXp, 2000);
    expect(progress.progress, closeTo(0.015, 0.0001));
  });

  test('发生日以事件生成时固化的本地日期为准', () {
    final GrowthOccurrence occurrence = engine.captureOccurrence(
      DateTime.utc(2026, 7, 14, 1),
      localize: (DateTime value) => value.add(const Duration(hours: -7)),
      timeZoneName: 'PDT',
    );

    expect(occurrence.occurredOn, DateTime(2026, 7, 13));
    expect(occurrence.timeZoneOffsetMinutes, -420);
    expect(occurrence.timeZoneName, 'PDT');
  });

  test('过期周报在周一零点后锁定，并沿用原模型版本', () {
    final DateTime weekStart = DateTime(2026, 7, 6);
    final WeeklyGrowthReport existing = WeeklyGrowthReport(
      id: 'weekly-growth:athlete-1:2026-07-06',
      athleteProfileId: 'athlete-1',
      weekKey: '2026-07-06',
      weekStartsOn: DateTime(2026, 7, 6),
      weekEndsOn: DateTime(2026, 7, 12),
      generatedAt: DateTime(2026, 7, 12, 22),
      lockedAt: null,
      regeneratedAt: null,
      consecutiveTrainingDays: 0,
      runningDistanceKm: 0,
      strengthSessionCount: 0,
      completionRate: 0,
      trainingLoad: 0,
      growthIndex: null,
      availableIndexDimensions: 0,
      recoverySummary: '数据不足',
      evidenceEventIds: <String>[],
      modelVersion: 7,
    );
    final TrainingLog log = _trainingLog(DateTime(2026, 7, 8, 8));
    final WeeklyGrowthReport report = engine.buildWeeklyGrowthReport(
      athleteProfileId: 'athlete-1',
      logs: <TrainingLog>[log],
      bodyMetrics: const [],
      events: <GrowthEvidenceEvent>[
        _event(
          id: 'training_logs:weekly',
          occurredAt: log.date,
          occurredOn: DateTime(2026, 7, 8),
          components: const <GrowthXpComponent>[
            GrowthXpComponent(
              type: GrowthXpComponentType.completion,
              amount: 30,
              reason: '完成训练',
            ),
          ],
        ),
      ],
      workoutsById: <String, WorkoutDay>{'workout-1': _workout()},
      plannedWorkoutCount: 3,
      now: DateTime(2026, 7, 14, 12),
      weekStartsOn: weekStart,
      existing: existing,
      manualRegeneration: true,
    );

    expect(report.weekKey, '2026-07-06');
    expect(report.lockedAt, DateTime(2026, 7, 13));
    expect(report.regeneratedAt, DateTime(2026, 7, 14, 12));
    expect(report.modelVersion, 7);
    expect(report.availableIndexDimensions, greaterThanOrEqualTo(2));
    expect(report.growthIndex, isNotNull);
  });

  test('旧 growthIndex 可读取为训练执行指数，新字段优先且继续兼容旧字段', () {
    final Map<String, dynamic> legacyJson = <String, dynamic>{
      'id': 'weekly-growth:athlete-1:2026-07-13',
      'athleteProfileId': 'athlete-1',
      'weekKey': '2026-07-13',
      'weekStartsOn': '2026-07-13',
      'weekEndsOn': '2026-07-19',
      'generatedAt': '2026-07-20T08:00:00.000Z',
      'completionRate': 0.75,
      'trainingLoad': 320,
      'growthIndex': 72,
    };

    final WeeklyGrowthReport legacy = WeeklyGrowthReport.fromJson(legacyJson);
    final WeeklyGrowthReport current = WeeklyGrowthReport.fromJson(
      <String, dynamic>{
        ...legacyJson,
        'trainingExecutionIndex': 81,
      },
    );

    expect(legacy.trainingExecutionIndex, 72);
    expect(legacy.trainingExecutionIndexLabel, '72');
    expect(current.trainingExecutionIndex, 81);
    expect(current.toJson()['trainingExecutionIndex'], 81);
    expect(current.toJson()['growthIndex'], 81);
  });
}

WorkoutDay _workout() {
  return const WorkoutDay(
    id: 'workout-1',
    planId: 'plan-1',
    weekIndex: 1,
    dayIndex: 1,
    title: '轻松跑',
    trainingType: TrainingType.easyRun,
    decisionType: TrainingDecisionType.normal,
    estimatedMinutes: 45,
    intensity: 'RPE 6',
    foamRollingSteps: <String>[],
    dynamicStretchSteps: <String>[],
    activationSteps: <String>[],
    warmupSteps: <String>[],
    mainSets: <String>[],
    accessoryWork: <String>[],
    cooldownSteps: <String>[],
    coachNotes: '',
    evidenceSources: [],
  );
}

TrainingLog _trainingLog(DateTime date) {
  return TrainingLog(
    id: 'log-weekly',
    workoutDayId: 'workout-1',
    date: date,
    completed: true,
    rpe: 6,
    fatigueLevel: 6,
    sleepQuality: 7,
    painNote: null,
    userNote: null,
    createdAt: date,
    kind: TrainingLogKind.sessionReview,
    actualDurationMinutes: 45,
    distanceKm: 6,
    completionPercentage: 100,
  );
}

GrowthEvidenceEvent _event({
  required String id,
  required DateTime occurredAt,
  required DateTime occurredOn,
  required List<GrowthXpComponent> components,
  DateTime? revokedAt,
}) {
  return GrowthEvidenceEvent(
    eventId: id,
    athleteProfileId: 'athlete-1',
    eventType: GrowthEventType.training,
    title: '测试事件',
    description: '测试用成长证据',
    occurredAt: occurredAt,
    occurredOn: occurredOn,
    timeZoneOffsetMinutes: 480,
    timeZoneName: 'CST',
    sourceTable: id.split(':').first,
    sourceId: id.split(':').last,
    xpComponents: components,
    impacts: const <GrowthImpact>[],
    confidence: GrowthConfidence.high,
    missingData: const <String>[],
    inputSnapshot: const <String, dynamic>{},
    modelVersion: 1,
    createdAt: occurredAt,
    updatedAt: occurredAt,
    revokedAt: revokedAt,
  );
}
