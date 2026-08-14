import '../../../data/models/cloud_sync.dart';
import '../../auth/data/authenticated_api_client.dart';

abstract interface class CloudSyncRemoteGateway {
  Future<CloudSyncSnapshot> fetchSnapshot();

  Future<List<CloudSyncMutationResult>> sendMutations(
    List<CloudSyncMutation> mutations,
  );

  Future<CloudSyncChangePage> fetchChanges({
    required int after,
    int limit = 100,
  });
}

class CloudSyncApi implements CloudSyncRemoteGateway {
  CloudSyncApi(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<CloudSyncSnapshot> fetchSnapshot() async {
    try {
      final Map<String, dynamic> response = await _client.getJson(
        '/v1/sync/snapshot',
        authenticated: true,
      );
      return CloudSyncSnapshot.fromJson(response);
    } on ApiException catch (error) {
      throw _mapTransportError(error);
    }
  }

  @override
  Future<List<CloudSyncMutationResult>> sendMutations(
    List<CloudSyncMutation> mutations,
  ) async {
    try {
      final Map<String, dynamic> response = await _client.postJson(
        '/v1/sync/mutations',
        <String, dynamic>{
          'mutations': mutations
              .map(
                (CloudSyncMutation mutation) => mutation.toRequestJson(),
              )
              .toList(growable: false),
        },
        authenticated: true,
      );
      final Object? rawResults = response['results'];
      if (rawResults is! List<dynamic>) {
        throw const FormatException('云同步响应格式无效');
      }
      return rawResults
          .map(
            (Object? item) => CloudSyncMutationResult.fromJson(
              (item as Map<String, dynamic>),
            ),
          )
          .toList(growable: false);
    } on ApiException catch (error) {
      throw _mapTransportError(error);
    }
  }

  @override
  Future<CloudSyncChangePage> fetchChanges({
    required int after,
    int limit = 100,
  }) async {
    try {
      final Map<String, dynamic> response = await _client.getJson(
        '/v1/sync/changes?after=$after&limit=$limit',
        authenticated: true,
      );
      final Object? rawChanges = response['changes'];
      if (rawChanges is! List<dynamic>) {
        throw const FormatException('云同步增量格式无效');
      }
      return CloudSyncChangePage(
        changes: rawChanges
            .map(
              (Object? item) => CloudSyncChange.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(growable: false),
        nextCursor: response['next_cursor'] as int,
        hasMore: response['has_more'] as bool,
      );
    } on ApiException catch (error) {
      throw _mapTransportError(error);
    }
  }
}

Object _mapTransportError(ApiException error) {
  if (error.code == 'network_unavailable' ||
      error.statusCode == 502 ||
      error.statusCode == 503 ||
      error.statusCode == 504) {
    return const CloudSyncTransportException();
  }
  return error;
}
