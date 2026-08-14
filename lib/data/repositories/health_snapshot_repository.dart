import '../../features/profile/application/health_data_gateway_contract.dart';
import '../../services/local_storage_service.dart';
import '../models/health_snapshot.dart';

class HealthSnapshotRepository {
  static const String storageKey = 'trainflow.health_sync.v1';
  final LocalStorageService _storage;

  const HealthSnapshotRepository(this._storage);

  List<HealthSnapshot> listSnapshots({required String athleteId}) {
    final Map<String, dynamic>? root = _storage.readJson(storageKey);
    final Map<String, dynamic>? athlete = _athlete(root, athleteId);
    final List<dynamic> raw = athlete?['snapshots'] as List<dynamic>? ??
        (root == null || root['athletes'] == null
            ? (root?['snapshots'] as List<dynamic>? ?? const <dynamic>[])
            : const <dynamic>[]);
    return raw
        .whereType<Map>()
        .map((Map item) => HealthSnapshot.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList()
      ..sort((HealthSnapshot left, HealthSnapshot right) =>
          right.date.compareTo(left.date));
  }

  DateTime? getLastSync({
    required String athleteId,
    required HealthPermissionStage stage,
  }) {
    final Map<String, dynamic>? root = _storage.readJson(storageKey);
    final Map<String, dynamic>? athlete = _athlete(root, athleteId);
    final Map<String, dynamic> byStage = Map<String, dynamic>.from(
      athlete?['lastSyncByStage'] as Map? ?? const <String, dynamic>{},
    );
    final String? legacyLastSync = root != null && root['athletes'] == null
        ? root['lastSync'] as String?
        : null;
    final String? value = byStage[stage.name] as String? ?? legacyLastSync;
    return value == null ? null : DateTime.tryParse(value);
  }

  HealthAuthorizationState getAuthorizationState({
    required String athleteId,
    required HealthPermissionStage stage,
  }) {
    final Map<String, dynamic>? athlete =
        _athlete(_storage.readJson(storageKey), athleteId);
    final Map<String, dynamic> byStage = Map<String, dynamic>.from(
      athlete?['authorizationByStage'] as Map? ?? const <String, dynamic>{},
    );
    return HealthAuthorizationState.values.firstWhere(
      (HealthAuthorizationState value) => value.name == byStage[stage.name],
      orElse: () => HealthAuthorizationState.notRequested,
    );
  }

  void saveAuthorization({
    required String athleteId,
    required HealthPermissionStage stage,
    required HealthAuthorizationState state,
  }) {
    final Map<String, dynamic> root = _mutableRoot(athleteId: athleteId);
    final Map<String, dynamic> athlete = _mutableAthlete(root, athleteId);
    final Map<String, dynamic> byStage = Map<String, dynamic>.from(
      athlete['authorizationByStage'] as Map? ?? const <String, dynamic>{},
    );
    byStage[stage.name] = state.name;
    athlete['authorizationByStage'] = byStage;
    _saveRoot(root);
  }

  void save({
    required String athleteId,
    required HealthPermissionStage stage,
    required List<HealthSnapshot> snapshots,
    required DateTime syncedAt,
  }) {
    final Map<String, dynamic> root = _mutableRoot(athleteId: athleteId);
    final Map<String, dynamic> athlete = _mutableAthlete(root, athleteId);
    final Map<String, dynamic> byStage = Map<String, dynamic>.from(
      athlete['lastSyncByStage'] as Map? ?? const <String, dynamic>{},
    );
    byStage[stage.name] = syncedAt.toUtc().toIso8601String();
    athlete
      ..['lastSyncByStage'] = byStage
      ..['snapshots'] = snapshots
          .map((HealthSnapshot item) => item.toJson())
          .toList(growable: false);
    _saveRoot(root);
  }

  /// 删除对象到达时撤销可能包含该来源的兼容日摘要。
  ///
  /// 旧版本摘要没有 UUID 血缘版本，或曾把来源应用 ID 写入
  /// sourceIds，无法安全证明不包含已删除样本，因此一并移除；
  /// 下次前台回填会从 HealthKit 当前事实重新生成，不保留陈旧值。
  List<HealthSnapshot> removeDeletedSources({
    required String athleteId,
    required Set<String> deletedSourceIds,
  }) {
    if (deletedSourceIds.isEmpty) {
      return listSnapshots(athleteId: athleteId);
    }
    final List<HealthSnapshot> remaining = listSnapshots(athleteId: athleteId)
        .where(
          (HealthSnapshot snapshot) =>
              snapshot.sourceLineageVersion >= 2 &&
              snapshot.sourceIds.isNotEmpty &&
              !snapshot.sourceIds.any(deletedSourceIds.contains),
        )
        .toList(growable: false);
    final Map<String, dynamic> root = _mutableRoot(athleteId: athleteId);
    final Map<String, dynamic> athlete = _mutableAthlete(root, athleteId);
    athlete['snapshots'] = remaining
        .map((HealthSnapshot item) => item.toJson())
        .toList(growable: false);
    _saveRoot(root);
    return remaining;
  }

  void clearAthlete(String athleteId) {
    final Map<String, dynamic> root = _mutableRoot(athleteId: athleteId);
    final Map<String, dynamic> athletes = Map<String, dynamic>.from(
      root['athletes'] as Map? ?? const <String, dynamic>{},
    )..remove(athleteId);
    root['athletes'] = athletes;
    _saveRoot(root);
  }

  Map<String, dynamic> _mutableRoot({required String athleteId}) {
    final Map<String, dynamic> root = Map<String, dynamic>.from(
      _storage.readJson(storageKey) ?? const <String, dynamic>{},
    );
    final Map<String, dynamic> athletes = Map<String, dynamic>.from(
      root['athletes'] as Map? ?? const <String, dynamic>{},
    );
    if (root['athletes'] == null &&
        (root['snapshots'] is List || root['lastSync'] is String)) {
      final Map<String, dynamic> athlete = Map<String, dynamic>.from(
        athletes[athleteId] as Map? ?? const <String, dynamic>{},
      );
      if (root['snapshots'] is List) {
        athlete['snapshots'] = List<dynamic>.from(root['snapshots'] as List);
      }
      if (root['lastSync'] is String) {
        final Map<String, dynamic> byStage = Map<String, dynamic>.from(
          athlete['lastSyncByStage'] as Map? ?? const <String, dynamic>{},
        );
        byStage.putIfAbsent(
          HealthPermissionStage.analysis.name,
          () => root['lastSync'],
        );
        athlete['lastSyncByStage'] = byStage;
      }
      athletes[athleteId] = athlete;
    }
    root
      ..remove('snapshots')
      ..remove('lastSync')
      ..['schemaVersion'] = 2
      ..['athletes'] = athletes;
    return root;
  }

  Map<String, dynamic> _mutableAthlete(
    Map<String, dynamic> root,
    String athleteId,
  ) {
    final Map<String, dynamic> athletes = Map<String, dynamic>.from(
      root['athletes'] as Map? ?? const <String, dynamic>{},
    );
    final Map<String, dynamic> athlete = Map<String, dynamic>.from(
      athletes[athleteId] as Map? ?? const <String, dynamic>{},
    );
    athletes[athleteId] = athlete;
    root['athletes'] = athletes;
    return athlete;
  }

  Map<String, dynamic>? _athlete(
    Map<String, dynamic>? root,
    String athleteId,
  ) {
    final Object? raw = (root?['athletes'] as Map?)?[athleteId];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  void _saveRoot(Map<String, dynamic> root) {
    _storage.saveJson(storageKey, root);
  }
}
