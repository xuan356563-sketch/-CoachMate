import '../models/pilot_validation.dart';
import '../../services/local_storage_service.dart';

class PersistedPilotValidationRepository {
  PersistedPilotValidationRepository(this._storage) {
    _hydrate();
  }

  static const String storageKey = 'trainflow.pilot_validation.v1';

  final LocalStorageService _storage;
  final List<PilotParticipantRecord> _participants = <PilotParticipantRecord>[];

  List<PilotParticipantRecord> listParticipants() {
    final List<PilotParticipantRecord> result =
        List<PilotParticipantRecord>.from(_participants)
          ..sort(
              (PilotParticipantRecord first, PilotParticipantRecord second) =>
                  first.alias.compareTo(second.alias));
    return List<PilotParticipantRecord>.unmodifiable(result);
  }

  PilotParticipantRecord addParticipant({
    required PilotScenario scenario,
    required DateTime startedOn,
  }) {
    if (_participants.length >= 5) {
      throw StateError('首批内测最多记录 5 位匿名测试者');
    }
    final String alias =
        'T${(_participants.length + 1).toString().padLeft(2, '0')}';
    final PilotParticipantRecord participant = PilotParticipantRecord(
      id: 'pilot-${alias.toLowerCase()}',
      alias: alias,
      scenario: scenario,
      startedOn: _dateOnly(startedOn),
      commitmentAcceptedAt: null,
      checkInDates: const <DateTime>[],
      feedbackDates: const <DateTime>[],
      depositStatus: PilotDepositStatus.notApplicable,
      continuationDecision: PilotContinuationDecision.pending,
    );
    _participants.add(participant);
    _persist();
    return participant;
  }

  PilotParticipantRecord save(PilotParticipantRecord participant) {
    final int index = _participants.indexWhere(
      (PilotParticipantRecord item) => item.id == participant.id,
    );
    if (index < 0) throw StateError('找不到匿名测试者记录');
    _participants[index] = _normalize(participant);
    _persist();
    return _participants[index];
  }

  PilotParticipantRecord markCheckIn(String participantId, DateTime date) {
    final PilotParticipantRecord participant = _find(participantId);
    return save(
      participant.copyWith(
        checkInDates: _appendDate(participant.checkInDates, date),
      ),
    );
  }

  PilotParticipantRecord markFeedback(String participantId, DateTime date) {
    final PilotParticipantRecord participant = _find(participantId);
    return save(
      participant.copyWith(
        feedbackDates: _appendDate(participant.feedbackDates, date),
      ),
    );
  }

  void clear() {
    _participants.clear();
    _storage.remove(storageKey);
  }

  PilotParticipantRecord _find(String participantId) {
    return _participants.firstWhere(
      (PilotParticipantRecord item) => item.id == participantId,
      orElse: () => throw StateError('找不到匿名测试者记录'),
    );
  }

  void _hydrate() {
    final Map<String, dynamic>? document = _storage.readJson(storageKey);
    final List<dynamic> items =
        document?['participants'] as List<dynamic>? ?? const <dynamic>[];
    _participants.addAll(
      items
          .whereType<Map<String, dynamic>>()
          .map(PilotParticipantRecord.fromJson),
    );
  }

  void _persist() {
    _storage.saveJson(storageKey, <String, dynamic>{
      'schemaVersion': 1,
      'participants': _participants
          .map((PilotParticipantRecord item) => item.toJson())
          .toList(growable: false),
    });
  }
}

PilotParticipantRecord _normalize(PilotParticipantRecord participant) {
  return participant.copyWith(
    checkInDates: _uniqueDates(participant.checkInDates),
    feedbackDates: _uniqueDates(participant.feedbackDates),
  );
}

List<DateTime> _appendDate(List<DateTime> values, DateTime value) {
  return _uniqueDates(<DateTime>[...values, _dateOnly(value)]);
}

List<DateTime> _uniqueDates(List<DateTime> values) {
  final Map<String, DateTime> unique = <String, DateTime>{};
  for (final DateTime value in values) {
    final DateTime date = _dateOnly(value);
    unique['${date.year}-${date.month}-${date.day}'] = date;
  }
  final List<DateTime> result = unique.values.toList()
    ..sort((DateTime first, DateTime second) => first.compareTo(second));
  return List<DateTime>.unmodifiable(result);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
