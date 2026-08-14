import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  const String gpx = '''
<gpx><trk><name>重复导入测试</name><trkseg>
  <trkpt lat="39" lon="116"><time>2026-07-20T08:00:00Z</time></trkpt>
  <trkpt lat="39" lon="116.001"><time>2026-07-20T08:30:00Z</time></trkpt>
</trkseg></trk></gpx>
''';

  test('同一GPX只生成一条导入记录和训练日志且可单独删除路线', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final int initialLogCount = container.read(trainingMvpProvider).logs.length;

    container.read(trainingMvpProvider.notifier).importGpxDocument(
          gpx,
          fileName: 'duplicate.gpx',
        );
    container.read(trainingMvpProvider.notifier).importGpxDocument(
          gpx,
          fileName: 'renamed.gpx',
        );

    TrainingMvpState state = container.read(trainingMvpProvider);
    expect(state.importedWorkouts, hasLength(1));
    expect(state.logs, hasLength(initialLogCount + 1));
    expect(state.activityImportStatusMessage, contains('已导入过'));
    expect(state.importedWorkouts.single.hasRouteShape, isTrue);

    container
        .read(trainingMvpProvider.notifier)
        .removeImportedRouteShape(state.importedWorkouts.single.id);
    state = container.read(trainingMvpProvider);

    expect(state.importedWorkouts.single.routeShape, isEmpty);
    expect(state.logs, hasLength(initialLogCount + 1));
    expect(state.activityImportStatusMessage, contains('路线数据已删除'));

    await Future<void>.delayed(Duration.zero);
  });
}
