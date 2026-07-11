import 'dart:math';

import '../data/models/imported_workout.dart';

class ActivityImportService {
  ImportedWorkout parse(String rawText) {
    final String text = rawText.trim();
    if (text.isEmpty) {
      throw const FormatException('请先粘贴 GPX 内容或 FIT 摘要。');
    }
    if (text.contains('<gpx') || text.contains('<trkpt')) {
      return _parseGpx(text);
    }
    return _parseFitSummary(text);
  }

  ImportedWorkout _parseGpx(String text) {
    final Iterable<RegExpMatch> matches = RegExp(
      r'<trkpt[^>]*lat="([^"]+)"[^>]*lon="([^"]+)"[^>]*>(.*?)</trkpt>',
      dotAll: true,
    ).allMatches(text);
    final List<_TrackPoint> points = [
      for (final RegExpMatch match in matches)
        _TrackPoint(
          latitude: double.parse(match.group(1)!),
          longitude: double.parse(match.group(2)!),
          elevationMeters: _firstDouble(match.group(3)!, r'<ele>([^<]+)</ele>'),
          time: _firstDateTime(match.group(3)!, r'<time>([^<]+)</time>'),
          heartRate:
              _firstInt(match.group(3)!, r'<[^<:>]*:?hr>([^<]+)</[^>]+>'),
        ),
    ];

    if (points.length < 2) {
      throw const FormatException('GPX 至少需要 2 个轨迹点才能计算距离。');
    }

    double distanceKm = 0;
    double elevationGain = 0;
    final List<int> heartRates = [];

    for (int i = 0; i < points.length; i += 1) {
      final _TrackPoint point = points[i];
      if (point.heartRate != null) {
        heartRates.add(point.heartRate!);
      }
      if (i == 0) {
        continue;
      }
      final _TrackPoint previous = points[i - 1];
      distanceKm += _distanceKm(previous, point);
      final double climb =
          (point.elevationMeters ?? 0) - (previous.elevationMeters ?? 0);
      if (climb > 0) {
        elevationGain += climb;
      }
    }

    final DateTime startedAt = points.first.time ?? DateTime.now();
    final DateTime endedAt = points.last.time ?? startedAt;
    final int durationMinutes = max(1, endedAt.difference(startedAt).inMinutes);
    final int averageHeartRate = heartRates.isEmpty
        ? 0
        : (heartRates.reduce((int a, int b) => a + b) / heartRates.length)
            .round();

    return ImportedWorkout(
      id: 'import-gpx-${DateTime.now().millisecondsSinceEpoch}',
      source: ImportedWorkoutSource.gpx,
      title: 'GPX 导入训练',
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

    return ImportedWorkout(
      id: 'import-fit-${DateTime.now().millisecondsSinceEpoch}',
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
    );
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

  double? _firstDouble(String text, String pattern) {
    final String? value = RegExp(pattern).firstMatch(text)?.group(1);
    return value == null ? null : double.tryParse(value);
  }

  int? _firstInt(String text, String pattern) {
    final String? value = RegExp(pattern).firstMatch(text)?.group(1);
    return value == null ? null : int.tryParse(value);
  }

  DateTime? _firstDateTime(String text, String pattern) {
    final String? value = RegExp(pattern).firstMatch(text)?.group(1);
    return value == null ? null : DateTime.tryParse(value);
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

  const _TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.elevationMeters,
    required this.time,
    required this.heartRate,
  });
}
