import '../models/race.dart';
import '../seed/seed_races.dart';
import '../../services/local_storage_service.dart';

abstract class RaceRepository {
  List<RacePlan> listRaces();

  RacePlan? findById(String id);

  RacePlan saveRace(RacePlan race);

  void clearImportedRaces();
}

class InMemoryRaceRepository implements RaceRepository {
  final List<RacePlan> _races;

  InMemoryRaceRepository({List<RacePlan>? initialRaces})
      : _races = List<RacePlan>.from(initialRaces ?? seedRaces);

  @override
  List<RacePlan> listRaces() {
    return List<RacePlan>.unmodifiable(_races);
  }

  @override
  RacePlan? findById(String id) {
    for (final RacePlan race in _races) {
      if (race.id == id) {
        return race;
      }
    }
    return null;
  }

  @override
  RacePlan saveRace(RacePlan race) {
    _races.removeWhere((RacePlan item) => item.id == race.id);
    _races.insert(0, race);
    return race;
  }

  @override
  void clearImportedRaces() {
    _races
      ..clear()
      ..addAll(seedRaces);
  }
}

class PersistedRaceRepository implements RaceRepository {
  static const String storageKey = 'trainflow.races.v1';
  static const int _maxSavedRaces = 20;

  final LocalStorageService _storageService;
  final List<RacePlan> _races = [];

  PersistedRaceRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<RacePlan> listRaces() {
    return List<RacePlan>.unmodifiable(_races);
  }

  @override
  RacePlan? findById(String id) {
    for (final RacePlan race in _races) {
      if (race.id == id) {
        return race;
      }
    }
    return null;
  }

  @override
  RacePlan saveRace(RacePlan race) {
    _races.removeWhere((RacePlan item) => item.id == race.id);
    _races.insert(0, race);
    if (_races.length > _maxSavedRaces) {
      _races.removeRange(_maxSavedRaces, _races.length);
    }
    _persist();
    return race;
  }

  @override
  void clearImportedRaces() {
    _races
      ..clear()
      ..addAll(seedRaces);
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      _races.addAll(seedRaces);
      _persist();
      return;
    }
    final List<dynamic> raceItems =
        storedState['races'] as List<dynamic>? ?? const [];
    _races.addAll(
      raceItems
          .whereType<Map<String, dynamic>>()
          .map(RacePlan.fromJson)
          .toList(),
    );
    if (_races.isEmpty) {
      _races.addAll(seedRaces);
    }
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'races': _races.map((RacePlan race) => race.toJson()).toList(),
    });
  }
}
