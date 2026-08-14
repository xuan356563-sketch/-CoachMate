import '../models/ai_artifact.dart';
import '../../services/local_storage_service.dart';

abstract class AiArtifactRepository {
  List<AiArtifact> listArtifacts();

  bool hasHealthDataProcessingConsent();

  void replaceArtifacts(List<AiArtifact> artifacts);

  void upsert(AiArtifact artifact);

  void remove(String artifactId);

  void setHealthDataProcessingConsent(bool value);
}

class InMemoryAiArtifactRepository implements AiArtifactRepository {
  List<AiArtifact> _artifacts;
  bool _healthDataProcessingConsent;

  InMemoryAiArtifactRepository({
    List<AiArtifact> initialArtifacts = const <AiArtifact>[],
    bool healthDataProcessingConsent = false,
  })  : _artifacts = List<AiArtifact>.from(initialArtifacts),
        _healthDataProcessingConsent = healthDataProcessingConsent;

  @override
  List<AiArtifact> listArtifacts() => List<AiArtifact>.unmodifiable(_artifacts);

  @override
  bool hasHealthDataProcessingConsent() => _healthDataProcessingConsent;

  @override
  void replaceArtifacts(List<AiArtifact> artifacts) {
    _artifacts = _sort(artifacts);
  }

  @override
  void upsert(AiArtifact artifact) {
    _artifacts = _sort(<AiArtifact>[
      artifact,
      for (final AiArtifact item in _artifacts)
        if (item.id != artifact.id) item,
    ]);
  }

  @override
  void remove(String artifactId) {
    _artifacts = _artifacts
        .where((AiArtifact item) => item.id != artifactId)
        .toList(growable: false);
  }

  @override
  void setHealthDataProcessingConsent(bool value) {
    _healthDataProcessingConsent = value;
  }
}

class PersistedAiArtifactRepository extends InMemoryAiArtifactRepository {
  static const String storageKey = 'trainflow.ai_artifacts.v1';

  final LocalStorageService _storageService;

  PersistedAiArtifactRepository(this._storageService)
      : super(
          initialArtifacts: _readArtifacts(_storageService),
          healthDataProcessingConsent: _readHealthConsent(_storageService),
        );

  @override
  void replaceArtifacts(List<AiArtifact> artifacts) {
    super.replaceArtifacts(artifacts);
    _persist();
  }

  @override
  void upsert(AiArtifact artifact) {
    super.upsert(artifact);
    _persist();
  }

  @override
  void remove(String artifactId) {
    super.remove(artifactId);
    _persist();
  }

  @override
  void setHealthDataProcessingConsent(bool value) {
    super.setHealthDataProcessingConsent(value);
    _persist();
  }

  void _persist() {
    _storageService.saveJson(storageKey, <String, dynamic>{
      'schemaVersion': 1,
      'healthDataProcessingConsent': hasHealthDataProcessingConsent(),
      'artifacts':
          listArtifacts().map((AiArtifact item) => item.toJson()).toList(),
    });
  }

  static List<AiArtifact> _readArtifacts(LocalStorageService storageService) {
    final Map<String, dynamic>? stored = storageService.readJson(storageKey);
    final Object? rawArtifacts = stored?['artifacts'];
    if (rawArtifacts is! List) return const <AiArtifact>[];
    return _sort(
      rawArtifacts
          .whereType<Map>()
          .map(
            (Map<dynamic, dynamic> item) =>
                AiArtifact.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((AiArtifact item) => item.id.isNotEmpty)
          .toList(),
    );
  }

  static bool _readHealthConsent(LocalStorageService storageService) {
    return storageService
            .readJson(storageKey)?['healthDataProcessingConsent'] ==
        true;
  }
}

List<AiArtifact> _sort(List<AiArtifact> artifacts) {
  final List<AiArtifact> sorted = List<AiArtifact>.from(artifacts);
  sorted.sort(
      (AiArtifact a, AiArtifact b) => b.generatedAt.compareTo(a.generatedAt));
  return sorted;
}
