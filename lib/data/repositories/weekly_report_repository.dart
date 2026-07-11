import '../models/weekly_report.dart';
import '../../services/local_storage_service.dart';

abstract class WeeklyReportRepository {
  List<WeeklyReport> listReports();

  WeeklyReport saveReport(WeeklyReport report);

  void clearReports();
}

class PersistedWeeklyReportRepository implements WeeklyReportRepository {
  static const String storageKey = 'trainflow.weekly_reports.v1';
  static const int _maxSavedReports = 8;

  final LocalStorageService _storageService;
  final List<WeeklyReport> _reports = [];

  PersistedWeeklyReportRepository(this._storageService) {
    _hydrate();
  }

  @override
  List<WeeklyReport> listReports() {
    _sortReports();
    return List<WeeklyReport>.unmodifiable(_reports);
  }

  @override
  WeeklyReport saveReport(WeeklyReport report) {
    _reports.removeWhere(
      (WeeklyReport item) => item.weekLabel == report.weekLabel,
    );
    _reports.insert(0, report);
    _sortReports();
    if (_reports.length > _maxSavedReports) {
      _reports.removeRange(_maxSavedReports, _reports.length);
    }
    _persist();
    return report;
  }

  @override
  void clearReports() {
    _reports.clear();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> reportItems =
        storedState['reports'] as List<dynamic>? ?? const [];
    _reports.addAll(
      reportItems
          .whereType<Map<String, dynamic>>()
          .map(WeeklyReport.fromJson)
          .toList(),
    );
    _sortReports();
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'reports':
          _reports.map((WeeklyReport report) => report.toJson()).toList(),
    });
  }

  void _sortReports() {
    _reports.sort(
      (WeeklyReport a, WeeklyReport b) =>
          b.generatedAt.compareTo(a.generatedAt),
    );
  }
}
