enum BodyMetricExportFormat {
  json,
  csv,
  packageSummary,
}

extension BodyMetricExportFormatLabel on BodyMetricExportFormat {
  String get label {
    switch (this) {
      case BodyMetricExportFormat.json:
        return 'JSON';
      case BodyMetricExportFormat.csv:
        return 'CSV';
      case BodyMetricExportFormat.packageSummary:
        return '导出包摘要';
    }
  }

  String get jsonValue {
    switch (this) {
      case BodyMetricExportFormat.json:
        return 'json';
      case BodyMetricExportFormat.csv:
        return 'csv';
      case BodyMetricExportFormat.packageSummary:
        return 'package_summary';
    }
  }
}

BodyMetricExportFormat bodyMetricExportFormatFromJson(String? value) {
  switch (value) {
    case 'csv':
      return BodyMetricExportFormat.csv;
    case 'package_summary':
      return BodyMetricExportFormat.packageSummary;
    case 'json':
    default:
      return BodyMetricExportFormat.json;
  }
}

class BodyMetricExportRecord {
  final String id;
  final BodyMetricExportFormat format;
  final int metricCount;
  final int byteCount;
  final String fileName;
  final DateTime exportedAt;

  const BodyMetricExportRecord({
    required this.id,
    required this.format,
    required this.metricCount,
    required this.byteCount,
    required this.fileName,
    required this.exportedAt,
  });

  factory BodyMetricExportRecord.fromJson(Map<String, dynamic> json) {
    return BodyMetricExportRecord(
      id: json['id'] as String? ?? '',
      format: bodyMetricExportFormatFromJson(json['format'] as String?),
      metricCount: (json['metricCount'] as num?)?.toInt() ?? 0,
      byteCount: (json['byteCount'] as num?)?.toInt() ?? 0,
      fileName: json['fileName'] as String? ?? '',
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'format': format.jsonValue,
      'metricCount': metricCount,
      'byteCount': byteCount,
      'fileName': fileName,
      'exportedAt': exportedAt.toIso8601String(),
    };
  }

  String get sizeLabel {
    if (byteCount >= 1024) {
      return '${(byteCount / 1024).toStringAsFixed(1)} KB';
    }
    return '$byteCount B';
  }

  String get exportedAtLabel {
    final String month = exportedAt.month.toString().padLeft(2, '0');
    final String day = exportedAt.day.toString().padLeft(2, '0');
    final String hour = exportedAt.hour.toString().padLeft(2, '0');
    final String minute = exportedAt.minute.toString().padLeft(2, '0');
    return '${exportedAt.year}-$month-$day $hour:$minute';
  }
}
