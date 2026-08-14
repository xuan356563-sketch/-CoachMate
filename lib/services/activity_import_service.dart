import 'dart:math';

import 'package:xml/xml.dart';

import '../data/models/imported_workout.dart';

class ActivityImportService {
  static const int maximumTrackPointCount = 100000;
  static const int maximumPersistedRoutePointCount = 600;

  ImportedWorkout parse(String rawText) {
    final String text = rawText.trim();
    if (text.isEmpty) {
      throw const FormatException('请先粘贴 GPX 内容或 FIT 摘要。');
    }
    if (text.contains('<gpx') || text.contains('<trkpt')) {
      return parseGpx(text);
    }
    return _parseFitSummary(text);
  }

  ImportedWorkout parseGpx(String rawText, {String? fileName}) {
    final String text = rawText.trim();
    if (text.isEmpty) {
      throw const FormatException('GPX 文件为空。');
    }

    late final XmlDocument document;
    try {
      document = XmlDocument.parse(text);
    } on XmlParserException {
      throw const FormatException('GPX XML 格式无效，请检查文件是否完整。');
    }

    final List<XmlElement> segmentElements = document.descendants
        .whereType<XmlElement>()
        .where((XmlElement element) => element.name.local == 'trkseg')
        .toList(growable: false);
    final int rawPointCount = segmentElements.fold<int>(
      0,
      (int total, XmlElement segment) =>
          total + _childElements(segment, 'trkpt').length,
    );
    if (rawPointCount > maximumTrackPointCount) {
      throw const FormatException('GPX 轨迹点超过 100000 个，请先在运动平台中简化轨迹。');
    }

    final List<_TrackPoint> points = <_TrackPoint>[];
    final Map<int, List<_TrackPoint>> pointsBySegment =
        <int, List<_TrackPoint>>{};
    for (int segmentIndex = 0;
        segmentIndex < segmentElements.length;
        segmentIndex += 1) {
      final List<_TrackPoint> segmentPoints = <_TrackPoint>[];
      for (final XmlElement element
          in _childElements(segmentElements[segmentIndex], 'trkpt')) {
        final double? latitude =
            double.tryParse(element.getAttribute('lat') ?? '');
        final double? longitude =
            double.tryParse(element.getAttribute('lon') ?? '');
        if (latitude == null ||
            longitude == null ||
            !latitude.isFinite ||
            !longitude.isFinite ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          continue;
        }
        final _TrackPoint point = _TrackPoint(
          latitude: latitude,
          longitude: longitude,
          elevationMeters: _firstElementDouble(element, 'ele'),
          time: _firstElementDateTime(element, 'time'),
          heartRate: _firstElementInt(element, 'hr'),
          segmentIndex: segmentIndex,
        );
        segmentPoints.add(point);
        points.add(point);
      }
      if (segmentPoints.isNotEmpty) {
        pointsBySegment[segmentIndex] = segmentPoints;
      }
    }

    if (!pointsBySegment.values.any(
      (List<_TrackPoint> segment) => segment.length >= 2,
    )) {
      throw const FormatException('GPX 至少需要一个包含 2 个有效轨迹点的轨迹段。');
    }

    double distanceKm = 0;
    double elevationGain = 0;
    final List<int> heartRates = <int>[];
    for (final List<_TrackPoint> segment in pointsBySegment.values) {
      for (int index = 0; index < segment.length; index += 1) {
        final _TrackPoint point = segment[index];
        if (point.heartRate != null && point.heartRate! > 0) {
          heartRates.add(point.heartRate!);
        }
        if (index == 0) continue;
        final _TrackPoint previous = segment[index - 1];
        distanceKm += _distanceKm(previous, point);
        if (previous.elevationMeters != null && point.elevationMeters != null) {
          final double climb =
              point.elevationMeters! - previous.elevationMeters!;
          if (climb > 0) elevationGain += climb;
        }
      }
    }

    final List<DateTime> timestamps = points
        .map((_TrackPoint point) => point.time)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final DateTime startedAt =
        timestamps.isEmpty ? DateTime.now() : timestamps.first;
    final int durationMinutes = timestamps.length < 2
        ? 0
        : max(0, timestamps.last.difference(timestamps.first).inMinutes);
    final int averageHeartRate = heartRates.isEmpty
        ? 0
        : (heartRates.reduce((int a, int b) => a + b) / heartRates.length)
            .round();
    final String fingerprint = _stableFingerprint(text);

    return ImportedWorkout(
      id: 'import-gpx-$fingerprint',
      source: ImportedWorkoutSource.gpx,
      title: _gpxTitle(document, fileName),
      startedAt: startedAt,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      elevationGainMeters: elevationGain.round(),
      averageHeartRate: averageHeartRate,
      trainingEffect: _trainingEffect(
        durationMinutes: durationMinutes,
        averageHeartRate: averageHeartRate,
        elevationGainMeters: elevationGain.round(),
      ),
      sourceFingerprint: 'gpx:$fingerprint',
      routeShape: _normalizeRoute(points, timestamps),
    );
  }

  ImportedWorkout _parseFitSummary(String text) {
    final Map<String, String> values = {};
    for (final String line in text.split(RegExp(r'\r?\n'))) {
      final RegExpMatch? match =
          RegExp(r'^\s*([a-zA-Z_ ]+)\s*[:=]\s*(.+?)\s*$').firstMatch(line);
      if (match == null) {
        continue;
      }
      values[match.group(1)!.trim().toLowerCase().replaceAll(' ', '_')] =
          match.group(2)!.trim();
    }

    final double distanceKm = _requiredDouble(
      values,
      const ['distance_km', 'distance'],
      'FIT 摘要缺少 distance_km。',
    );
    final int durationMinutes = _requiredDouble(
      values,
      const ['duration_minutes', 'duration'],
      'FIT 摘要缺少 duration_minutes。',
    ).round();
    final int elevationGainMeters = _optionalDouble(
      values,
      const ['elevation_gain_m', 'elevation_gain', 'ascent'],
    ).round();
    final int averageHeartRate = _optionalDouble(
      values,
      const ['avg_hr', 'average_heart_rate', 'heart_rate'],
    ).round();
    final DateTime startedAt = DateTime.tryParse(
          values['started_at'] ?? values['date'] ?? '',
        ) ??
        DateTime.now();

    final String fingerprint = _stableFingerprint(text);
    return ImportedWorkout(
      id: 'import-fit-$fingerprint',
      source: ImportedWorkoutSource.fitSummary,
      title: values['title'] ?? 'FIT 摘要导入训练',
      startedAt: startedAt,
      distanceKm: distanceKm,
      durationMinutes: max(1, durationMinutes),
      elevationGainMeters: elevationGainMeters,
      averageHeartRate: averageHeartRate,
      trainingEffect: _trainingEffect(
        durationMinutes: max(1, durationMinutes),
        averageHeartRate: averageHeartRate,
        elevationGainMeters: elevationGainMeters,
      ),
      sourceFingerprint: 'fit_summary:$fingerprint',
    );
  }

  List<XmlElement> _childElements(XmlElement element, String localName) {
    return element.childElements
        .where((XmlElement child) => child.name.local == localName)
        .toList(growable: false);
  }

  double? _firstElementDouble(XmlElement element, String localName) {
    final String? value = _firstElementText(element, localName);
    return value == null ? null : double.tryParse(value);
  }

  int? _firstElementInt(XmlElement element, String localName) {
    final String? value = _firstElementText(element, localName);
    return value == null ? null : int.tryParse(value);
  }

  DateTime? _firstElementDateTime(XmlElement element, String localName) {
    final String? value = _firstElementText(element, localName);
    return value == null ? null : DateTime.tryParse(value);
  }

  String? _firstElementText(XmlElement element, String localName) {
    for (final XmlElement child
        in element.descendants.whereType<XmlElement>()) {
      if (child.name.local != localName) continue;
      final String value = child.innerText.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String _gpxTitle(XmlDocument document, String? fileName) {
    for (final XmlElement element
        in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'trk') continue;
      final String? name = _firstElementText(element, 'name');
      if (name != null && name.isNotEmpty) return name;
    }
    final String normalizedFileName =
        (fileName ?? '').split(RegExp(r'[/\\]')).last;
    final String withoutExtension = normalizedFileName.replaceFirst(
      RegExp(r'\.gpx$', caseSensitive: false),
      '',
    );
    return withoutExtension.trim().isEmpty ? 'GPX 导入训练' : withoutExtension;
  }

  List<RouteShapePoint> _normalizeRoute(
    List<_TrackPoint> points,
    List<DateTime> timestamps,
  ) {
    if (points.length < 2) return const <RouteShapePoint>[];
    final List<_TrackPoint> sampled = _sampleRoutePoints(points);
    final double minLatitude =
        points.map((_TrackPoint point) => point.latitude).reduce(min);
    final double maxLatitude =
        points.map((_TrackPoint point) => point.latitude).reduce(max);
    final double minLongitude =
        points.map((_TrackPoint point) => point.longitude).reduce(min);
    final double maxLongitude =
        points.map((_TrackPoint point) => point.longitude).reduce(max);
    final double latitudeSpan = maxLatitude - minLatitude;
    final double longitudeSpan = maxLongitude - minLongitude;
    final DateTime? firstTime = timestamps.isEmpty ? null : timestamps.first;
    final DateTime? lastTime = timestamps.isEmpty ? null : timestamps.last;
    final int timeSpanMilliseconds = firstTime == null || lastTime == null
        ? 0
        : lastTime.difference(firstTime).inMilliseconds;

    return List<RouteShapePoint>.unmodifiable(
      sampled.map((_TrackPoint point) {
        final int originalIndex = points.indexOf(point);
        final double progress;
        if (point.time != null &&
            firstTime != null &&
            timeSpanMilliseconds > 0) {
          progress = point.time!.difference(firstTime).inMilliseconds /
              timeSpanMilliseconds;
        } else {
          progress = originalIndex / (points.length - 1);
        }
        return RouteShapePoint(
          x: longitudeSpan == 0
              ? 0.5
              : ((point.longitude - minLongitude) / longitudeSpan)
                  .clamp(0, 1)
                  .toDouble(),
          y: latitudeSpan == 0
              ? 0.5
              : (1 - (point.latitude - minLatitude) / latitudeSpan)
                  .clamp(0, 1)
                  .toDouble(),
          progress: progress.clamp(0, 1).toDouble(),
          segmentIndex: point.segmentIndex,
        );
      }),
    );
  }

  List<_TrackPoint> _sampleRoutePoints(List<_TrackPoint> points) {
    if (points.length <= maximumPersistedRoutePointCount) {
      return List<_TrackPoint>.unmodifiable(points);
    }
    final Set<int> selectedIndexes = <int>{0, points.length - 1};
    for (int index = 1; index < points.length; index += 1) {
      if (points[index].segmentIndex != points[index - 1].segmentIndex) {
        selectedIndexes
          ..add(index - 1)
          ..add(index);
      }
    }
    final int remaining =
        maximumPersistedRoutePointCount - selectedIndexes.length;
    if (remaining > 0) {
      final double step = (points.length - 1) / (remaining + 1);
      for (int index = 1; index <= remaining; index += 1) {
        selectedIndexes.add((index * step).round());
      }
    }
    final List<int> orderedIndexes = selectedIndexes.toList()..sort();
    if (orderedIndexes.length > maximumPersistedRoutePointCount) {
      orderedIndexes.removeRange(
        maximumPersistedRoutePointCount,
        orderedIndexes.length,
      );
    }
    return List<_TrackPoint>.unmodifiable(
      orderedIndexes.map((int pointIndex) => points[pointIndex]),
    );
  }

  String _stableFingerprint(String text) {
    int primaryHash = 17;
    int secondaryHash = 23;
    for (final int codeUnit in text.codeUnits) {
      primaryHash = (primaryHash * 31 + codeUnit) & 0x7FFFFFFF;
      secondaryHash = (secondaryHash * 131 + codeUnit) & 0x7FFFFFFF;
    }
    return '${primaryHash.toRadixString(16).padLeft(8, '0')}'
        '${secondaryHash.toRadixString(16).padLeft(8, '0')}';
  }

  TrainingEffectLabel _trainingEffect({
    required int durationMinutes,
    required int averageHeartRate,
    required int elevationGainMeters,
  }) {
    if (averageHeartRate >= 162 || elevationGainMeters >= 450) {
      return TrainingEffectLabel.anaerobic;
    }
    if (durationMinutes >= 30 || averageHeartRate >= 130) {
      return TrainingEffectLabel.aerobic;
    }
    return TrainingEffectLabel.recovery;
  }

  double _distanceKm(_TrackPoint a, _TrackPoint b) {
    const double earthRadiusKm = 6371;
    final double dLat = _radians(b.latitude - a.latitude);
    final double dLon = _radians(b.longitude - a.longitude);
    final double lat1 = _radians(a.latitude);
    final double lat2 = _radians(b.latitude);
    final double haversine = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    return earthRadiusKm * 2 * atan2(sqrt(haversine), sqrt(1 - haversine));
  }

  double _radians(double degrees) {
    return degrees * pi / 180;
  }

  double _requiredDouble(
    Map<String, String> values,
    List<String> keys,
    String message,
  ) {
    final double? value = _optionalValue(values, keys);
    if (value == null) {
      throw FormatException(message);
    }
    return value;
  }

  double _optionalDouble(Map<String, String> values, List<String> keys) {
    return _optionalValue(values, keys) ?? 0;
  }

  double? _optionalValue(Map<String, String> values, List<String> keys) {
    for (final String key in keys) {
      final String? raw = values[key];
      if (raw == null) {
        continue;
      }
      final RegExpMatch? number = RegExp(r'-?\d+(\.\d+)?').firstMatch(raw);
      if (number == null) {
        continue;
      }
      return double.tryParse(number.group(0)!);
    }
    return null;
  }
}

class _TrackPoint {
  final double latitude;
  final double longitude;
  final double? elevationMeters;
  final DateTime? time;
  final int? heartRate;
  final int segmentIndex;

  const _TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.elevationMeters,
    required this.time,
    required this.heartRate,
    required this.segmentIndex,
  });
}
