import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/race.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/repositories/race_repository.dart';
import 'package:trainflow_ai/data/seed/seed_races.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/race_prep/application/race_image_recognition_controller.dart';
import 'package:trainflow_ai/features/race_prep/race_prep_page.dart';
import 'package:trainflow_ai/features/training_log/application/training_log_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

class _IdleRaceImageRecognitionController
    extends RaceImageRecognitionController {
  @override
  Future<RaceImageRecognitionState> build() async {
    return const RaceImageRecognitionState();
  }
}

void main() {
  group('赛事日程归类', () {
    test('只将主动确认正式成绩的赛事归为完赛，并按自然日计算倒计时', () {
      final RacePlan pending = seedRaces.first;
      final RacePlan completed = pending.confirmOfficialRaceResult(
        durationSeconds: 14400,
        confirmedAt: DateTime(2026, 11, 29, 14),
        trainingLogId: 'race-log-1',
        workoutDayId: 'race-workout-1',
      );

      expect(raceScheduleTabFor(pending), RaceScheduleTab.preparing);
      expect(raceScheduleTabFor(completed), RaceScheduleTab.completed);
      expect(raceDaysUntil(pending, DateTime(2026, 11, 28, 23, 59)), 1);
      expect(raceDaysUntil(pending, DateTime(2026, 11, 29, 6)), 0);
      expect(raceDaysUntil(pending, DateTime(2026, 11, 30, 6)), -1);
    });
  });

  group('正式比赛成绩模型', () {
    test('旧 actualResult 文本不会自动成为正式比赛 PB', () {
      final Map<String, dynamic> legacyJson = seedRaces.first.toJson()
        ..remove('officialRaceResult')
        ..['actualResult'] = '3:59:59';

      final RacePlan restored = RacePlan.fromJson(legacyJson);

      expect(restored.actualResult, '3:59:59');
      expect(restored.officialRaceResult, isNull);
      expect(restored.hasActiveOfficialRaceResult, isFalse);
    });

    test('成绩格式校验、结构化保存和撤销状态可以往返 JSON', () {
      expect(OfficialRaceResult.parseDurationSeconds('4:30:05'), 16205);
      expect(OfficialRaceResult.parseDurationSeconds('45:30'), 2730);
      expect(OfficialRaceResult.tryParseDurationSeconds('4:88:00'), isNull);
      expect(OfficialRaceResult.tryParseDurationSeconds('四小时'), isNull);

      final RacePlan confirmed = seedRaces.first.confirmOfficialRaceResult(
        durationSeconds: 16205,
        confirmedAt: DateTime(2026, 11, 29, 14, 30),
        trainingLogId: 'race-log-1',
        workoutDayId: 'race-workout-1',
      );
      final RacePlan restored = RacePlan.fromJson(confirmed.toJson());

      expect(restored.hasActiveOfficialRaceResult, isTrue);
      expect(restored.officialRaceResult?.durationLabel, '04:30:05');
      expect(restored.officialRaceResult?.trainingLogId, 'race-log-1');
      expect(restored.officialRaceResult?.workoutDayId, 'race-workout-1');

      final RacePlan revoked = restored.revokeOfficialRaceResult(
        DateTime(2026, 11, 30, 8),
      );
      final RacePlan revokedRestored = RacePlan.fromJson(revoked.toJson());
      expect(revokedRestored.hasActiveOfficialRaceResult, isFalse);
      expect(
        revokedRestored.officialRaceResult?.status,
        OfficialRaceResultStatus.revoked,
      );
      expect(revokedRestored.officialRaceResult?.revokedAt, isNotNull);
    });
  });

  test('控制器只接受完整训练事实，并持久化确认与撤销审计', () async {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    final TrainingLogController logController =
        container.read(trainingLogControllerProvider.notifier);
    await logController.save(_trainingLog(id: 'empty-log', actualMinutes: 0));
    await logController.save(
      _trainingLog(
        id: 'other-day-log',
        actualMinutes: 251,
        date: DateTime(2026, 11, 28, 8),
      ),
    );
    await logController.save(_trainingLog(id: 'race-log', actualMinutes: 251));

    final RacePlan race = container.read(trainingMvpProvider).races.first;
    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);

    expect(
      controller.confirmOfficialRaceResult(
        raceId: race.id,
        trainingLogId: 'empty-log',
        durationText: '4:11:03',
      ),
      contains('正式训练记录'),
    );
    expect(
      container.read(trainingMvpProvider).findRace(race.id)?.officialRaceResult,
      isNull,
    );
    expect(
      controller.confirmOfficialRaceResult(
        raceId: race.id,
        trainingLogId: 'other-day-log',
        durationText: '4:11:03',
      ),
      contains('比赛日期不一致'),
    );

    final String? error = controller.confirmOfficialRaceResult(
      raceId: race.id,
      trainingLogId: 'race-log',
      durationText: '4:11:03',
      confirmedAt: DateTime(2026, 11, 29, 15),
    );

    expect(error, isNull);
    final RacePlan confirmed =
        container.read(trainingMvpProvider).findRace(race.id)!;
    expect(confirmed.officialRaceResult?.durationSeconds, 15063);
    expect(confirmed.officialRaceResult?.trainingLogId, 'race-log');
    expect(confirmed.officialRaceResult?.workoutDayId, 'race-workout');
    expect(
      PersistedRaceRepository(storage)
          .findById(race.id)
          ?.hasActiveOfficialRaceResult,
      isTrue,
    );

    expect(
      controller.revokeOfficialRaceResult(
        raceId: race.id,
        revokedAt: DateTime(2026, 11, 30, 9),
      ),
      isNull,
    );
    final OfficialRaceResult? revoked =
        PersistedRaceRepository(storage).findById(race.id)?.officialRaceResult;
    expect(revoked?.status, OfficialRaceResultStatus.revoked);
    expect(revoked?.revokedAt, DateTime(2026, 11, 30, 9));
  });

  testWidgets('比赛备战页要求主动选择训练记录，并可确认和撤销正式 PB', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = _container(storage);
    addTearDown(container.dispose);
    await container
        .read(trainingLogControllerProvider.notifier)
        .save(_trainingLog(id: 'race-log', actualMinutes: 251));
    final String raceId = container.read(trainingMvpProvider).races.first.id;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RacePrepPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey<String>('race-schedule-$raceId')));
    await tester.pumpAndSettle();

    final Finder openButton =
        find.byKey(ValueKey<String>('official-race-confirm-$raceId'));
    await _bringIntoViewport(tester, openButton);
    await tester.tap(openButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('主动选择一条已完成的训练记录'), findsOneWidget);
    final Finder saveButton =
        find.byKey(const ValueKey<String>('official-race-save-button'));
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('official-race-log-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('official-race-log-race-log')).last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('official-race-duration-input')),
      '4:11:03',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('正式比赛 PB'), findsOneWidget);
    expect(find.text('04:11:03'), findsOneWidget);
    expect(
      container
          .read(trainingMvpProvider)
          .findRace(raceId)
          ?.officialRaceResult
          ?.trainingLogId,
      'race-log',
    );

    final Finder revokeButton =
        find.byKey(ValueKey<String>('official-race-revoke-$raceId'));
    await _bringIntoViewport(tester, revokeButton);
    await tester.tap(revokeButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('official-race-revoke-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('不再作为 PB 展示'), findsOneWidget);
    expect(
      container
          .read(trainingMvpProvider)
          .findRace(raceId)
          ?.hasActiveOfficialRaceResult,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _container(InMemoryLocalStorageService storage) {
  return ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      raceImageRecognitionControllerProvider.overrideWith(
        _IdleRaceImageRecognitionController.new,
      ),
    ],
  );
}

TrainingLog _trainingLog({
  required String id,
  required int actualMinutes,
  DateTime? date,
}) {
  return TrainingLog(
    id: id,
    workoutDayId: 'race-workout',
    date: date ?? DateTime(2026, 11, 29, 8),
    completed: true,
    rpe: 8,
    fatigueLevel: 8,
    sleepQuality: 7,
    painNote: null,
    userNote: '正式比赛训练事实',
    createdAt: DateTime(2026, 11, 29, 15),
    kind: TrainingLogKind.sessionReview,
    actualDurationMinutes: actualMinutes,
    distanceKm: actualMinutes > 0 ? 42.195 : 0,
    completionPercentage: 100,
  );
}

Future<void> _bringIntoViewport(WidgetTester tester, Finder target) async {
  final Finder scrollable = find.byType(Scrollable).first;
  for (int attempt = 0; attempt < 10; attempt++) {
    if (target.evaluate().isEmpty) {
      await tester.drag(scrollable, const Offset(0, -380));
      await tester.pumpAndSettle();
      continue;
    }
    final Rect rect = tester.getRect(target);
    if (rect.top >= 0 && rect.bottom <= 840) {
      return;
    }
    await tester.drag(
      scrollable,
      Offset(0, rect.bottom > 840 ? -380 : 380),
    );
    await tester.pumpAndSettle();
  }
}
