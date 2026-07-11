enum WeeklyReportExportFormat {
  markdown,
  png,
}

extension WeeklyReportExportFormatLabel on WeeklyReportExportFormat {
  String get label {
    switch (this) {
      case WeeklyReportExportFormat.markdown:
        return 'Markdown';
      case WeeklyReportExportFormat.png:
        return 'PNG 图片';
    }
  }

  String get jsonValue {
    switch (this) {
      case WeeklyReportExportFormat.markdown:
        return 'markdown';
      case WeeklyReportExportFormat.png:
        return 'png';
    }
  }
}

WeeklyReportExportFormat weeklyReportExportFormatFromJson(String? value) {
  switch (value) {
    case 'png':
      return WeeklyReportExportFormat.png;
    case 'markdown':
    default:
      return WeeklyReportExportFormat.markdown;
  }
}

class WeeklyReportExportRecord {
  final String id;
  final String reportId;
  final String weekLabel;
  final WeeklyReportExportFormat format;
  final int byteCount;
  final String fileName;
  final DateTime exportedAt;

  const WeeklyReportExportRecord({
    required this.id,
    required this.reportId,
    required this.weekLabel,
    required this.format,
    required this.byteCount,
    required this.fileName,
    required this.exportedAt,
  });

  factory WeeklyReportExportRecord.fromJson(Map<String, dynamic> json) {
    return WeeklyReportExportRecord(
      id: json['id'] as String? ?? '',
      reportId: json['reportId'] as String? ?? '',
      weekLabel: json['weekLabel'] as String? ?? '',
      format: weeklyReportExportFormatFromJson(json['format'] as String?),
      byteCount: (json['byteCount'] as num?)?.toInt() ?? 0,
      fileName: json['fileName'] as String? ?? '',
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reportId': reportId,
      'weekLabel': weekLabel,
      'format': format.jsonValue,
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
