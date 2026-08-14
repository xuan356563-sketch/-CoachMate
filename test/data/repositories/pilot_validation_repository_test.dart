import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/pilot_validation.dart';
import 'package:trainflow_ai/data/repositories/pilot_validation_repository.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('内测记录只保存匿名编号和结构化履约状态', () {
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedPilotValidationRepository repository =
        PersistedPilotValidationRepository(storage);
    final DateTime startedOn = DateTime(2026, 7, 18);

    PilotParticipantRecord participant = repository.addParticipant(
      scenario: PilotScenario.raceRunning,
      startedOn: startedOn,
    );
    participant = repository.save(
      participant.copyWith(
        commitmentAcceptedAt: DateTime(2026, 7, 18, 20),
        checkInDates: <DateTime>[startedOn],
        feedbackDates: <DateTime>[startedOn.add(const Duration(days: 1))],
        depositStatus: PilotDepositStatus.receivedOffline,
        continuationDecision: PilotContinuationDecision.acceptedEarlyBird,
      ),
    );

    final Map<String, dynamic>? document =
        storage.readJson(PersistedPilotValidationRepository.storageKey);
    expect(participant.alias, 'T01');
    expect(document.toString(), isNot(contains('微信')));
    expect(document.toString(), isNot(contains('手机号')));
    expect(document.toString(), isNot(contains('支付凭证')));

    final PilotParticipantRecord restored =
        PersistedPilotValidationRepository(storage).listParticipants().single;
    expect(restored.checkInCount, 1);
    expect(restored.feedbackCount, 1);
    expect(restored.depositStatus, PilotDepositStatus.receivedOffline);
    expect(
      restored.continuationDecision,
      PilotContinuationDecision.acceptedEarlyBird,
    );
  });

  test('匿名编号按T01到T05递增且同日履约去重', () {
    final PersistedPilotValidationRepository repository =
        PersistedPilotValidationRepository(InMemoryLocalStorageService());
    final DateTime today = DateTime(2026, 7, 18);

    for (int index = 0; index < 5; index += 1) {
      repository.addParticipant(
        scenario: PilotScenario.values[index % PilotScenario.values.length],
        startedOn: today,
      );
    }

    expect(
      repository
          .listParticipants()
          .map((PilotParticipantRecord item) => item.alias),
      <String>['T01', 'T02', 'T03', 'T04', 'T05'],
    );
    expect(
      () => repository.addParticipant(
        scenario: PilotScenario.sedentaryRecovery,
        startedOn: today,
      ),
      throwsStateError,
    );

    PilotParticipantRecord first = repository.listParticipants().first;
    first = repository.markCheckIn(first.id, today);
    first =
        repository.markCheckIn(first.id, today.add(const Duration(hours: 5)));
    expect(first.checkInCount, 1);
  });

  test('未知枚举值按保守状态读取，不阻塞内测页', () {
    final PilotParticipantRecord restored = PilotParticipantRecord.fromJson(
      <String, dynamic>{
        'id': 'pilot-1',
        'alias': 'T01',
        'scenario': 'future_scenario',
        'startedOn': '2026-07-18',
        'depositStatus': 'future_deposit_status',
        'continuationDecision': 'future_decision',
      },
    );

    expect(restored.scenario, PilotScenario.raceRunning);
    expect(restored.depositStatus, PilotDepositStatus.notApplicable);
    expect(restored.continuationDecision, PilotContinuationDecision.pending);
  });
}
