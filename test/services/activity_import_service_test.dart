import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/imported_workout.dart';
import 'package:trainflow_ai/services/activity_import_service.dart';

void main() {
  const String namespacedMultiSegmentGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <trk>
    <name>周末双段跑</name>
    <trkseg>
      <trkpt lon="116.0000" lat="39.0000">
        <ele>10</ele><time>2026-07-20T08:00:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
      <trkpt lat="39.0000" lon="116.0010">
        <ele>20</ele><time>2026-07-20T08:01:00Z</time>
        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>150</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
      </trkpt>
    </trkseg>
    <trkseg>
      <trkpt lat="40.0000" lon="117.0000"><ele>30</ele><time>2026-07-20T08:02:00Z</time></trkpt>
      <trkpt lat="40.0000" lon="117.0010"><ele>35</ele><time>2026-07-20T08:03:00Z</time></trkpt>
    </trkseg>
  </trk>
</gpx>
''';

  test('真实GPX支持命名空间和多轨迹段且不跨段计算距离', () {
    final ImportedWorkout workout = ActivityImportService().parseGpx(
      namespacedMultiSegmentGpx,
      fileName: 'weekend-run.gpx',
    );

    expect(workout.title, '周末双段跑');
    expect(workout.source, ImportedWorkoutSource.gpx);
    expect(workout.distanceKm, greaterThan(0.15));
    expect(workout.distanceKm, lessThan(0.25));
    expect(workout.durationMinutes, 3);
    expect(workout.elevationGainMeters, 15);
    expect(workout.averageHeartRate, 145);
    expect(workout.routeShape, isNotEmpty);
    expect(
      workout.routeShape
          .map((RouteShapePoint point) => point.segmentIndex)
          .toSet(),
      <int>{0, 1},
    );
  });

  test('路线持久化只包含归一化形状不包含经纬度', () {
    final ImportedWorkout workout = ActivityImportService().parseGpx(
      namespacedMultiSegmentGpx,
      fileName: 'privacy.gpx',
    );

    final String persisted = jsonEncode(workout.toJson());
    expect(persisted, isNot(contains('latitude')));
    expect(persisted, isNot(contains('longitude')));
    expect(workout.routeShape.every((RouteShapePoint point) {
      return point.x >= 0 &&
          point.x <= 1 &&
          point.y >= 0 &&
          point.y <= 1 &&
          point.progress >= 0 &&
          point.progress <= 1;
    }), isTrue);
  });

  test('相同源文件生成稳定指纹且内容变化后指纹不同', () {
    final ActivityImportService service = ActivityImportService();
    final ImportedWorkout first = service.parseGpx(namespacedMultiSegmentGpx);
    final ImportedWorkout second = service.parseGpx(namespacedMultiSegmentGpx);
    final ImportedWorkout changed = service.parseGpx(
      namespacedMultiSegmentGpx.replaceFirst('周末双段跑', '周末双段训练'),
    );

    expect(first.sourceFingerprint, second.sourceFingerprint);
    expect(first.id, second.id);
    expect(changed.sourceFingerprint, isNot(first.sourceFingerprint));
  });

  test('缺少时间的GPX不伪造时长或配速', () {
    const String gpx = '''
<gpx><trk><trkseg>
  <trkpt lat="39" lon="116"></trkpt>
  <trkpt lat="39" lon="116.001"></trkpt>
</trkseg></trk></gpx>
''';

    final ImportedWorkout workout = ActivityImportService().parseGpx(gpx);

    expect(workout.durationMinutes, 0);
    expect(workout.paceLabel, '无配速');
    expect(workout.routeShape, hasLength(2));
  });

  test('旧版导入记录缺少路线字段时保持兼容', () {
    final ImportedWorkout workout = ImportedWorkout.fromJson({
      'id': 'legacy-import',
      'source': 'gpx',
      'title': '旧记录',
      'startedAt': '2026-07-20T08:00:00.000Z',
      'distanceKm': 5.0,
      'durationMinutes': 30,
      'elevationGainMeters': 10,
      'averageHeartRate': 140,
      'trainingEffect': 'aerobic',
    });

    expect(workout.routeShape, isEmpty);
    expect(workout.sourceFingerprint, isEmpty);
  });
}
