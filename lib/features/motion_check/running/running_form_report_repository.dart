import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../services/local_storage_service.dart';
import 'running_form_assessment_service.dart';

/// 只写独立本地文档；外层控制器必须用账号域操作的 commit 包住写入。
class RunningFormReportRepository {
  RunningFormReportRepository(this.storage);
  static const storageKey = 'trainflow.running_form_reports.v1';
  final LocalStorageService storage;
  bool _writing = false;
  bool _needsRecovery = false;
  List<RunningFormReport>? _lastGood;
  List<RunningFormReport> list() {
    if (_needsRecovery && _lastGood != null) {
      return List.unmodifiable(_lastGood!);
    }
    final raw = storage.readJson(storageKey);
    if (raw == null) return const [];
    if (raw['schemaVersion'] != 1 ||
        raw['reports'] is! List ||
        (raw['reports'] as List).length > 20) {
      throw const FormatException('跑姿报告格式不受支持，已保留原始数据');
    }
    final reports = (raw['reports'] as List)
        .map((r) =>
            RunningFormReport.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(reports);
  }

  Future<void> save(RunningFormReport report) async {
    // 与读取执行同样的兼容和边界验证。
    RunningFormReport.fromJson(report.toJson());
    final reports = list();
    if (!report.captureConfirmed) throw StateError('缺少拍摄条件确认，不能保存报告');
    if (!reports.any((r) => r.id == report.id) && reports.length >= 20) {
      throw StateError('已保存 20 份报告，请先在报告管理中选择删除旧报告');
    }
    await _write([report, ...reports.where((r) => r.id != report.id)]);
  }

  Future<void> delete(String id) =>
      _write(list().where((r) => r.id != id).toList());
  Future<void> _write(List<RunningFormReport> reports) async {
    if (_writing) throw StateError('报告正在保存，请稍后重试');
    if (_needsRecovery) throw StateError('报告存储回滚失败，请重启应用后复核本地数据');
    _writing = true;
    final previous = storage.readJson(storageKey);
    _lastGood = list();
    try {
      // SQLite 由启动链路保护；iOS 旧存储需要先排除其偏好目录备份。
      if (storage is SharedPreferencesLocalStorageService &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        await const MethodChannel('trainflow.ai/running_video')
            .invokeMethod<void>('protectPreferences');
      }
      storage.saveJson(storageKey, {
        'schemaVersion': 1,
        'reports': reports.map((r) => r.toJson()).toList()
      });
      await storage.flush();
    } catch (error) {
      try {
        if (previous == null) {
          storage.remove(storageKey);
        } else {
          storage.saveJson(storageKey, previous);
        }
        await storage.flush();
      } catch (_) {
        _needsRecovery = true;
      }
      rethrow;
    } finally {
      _writing = false;
    }
  }
}
