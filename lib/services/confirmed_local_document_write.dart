import 'local_storage_service.dart';

/// 仓储持有写锁时准备的候选文档；只有提交成功才能发布到共享缓存。
class PreparedLocalDocumentWrite {
  PreparedLocalDocumentWrite({
    required this.key,
    required this.document,
    required this.publish,
    required this.blockRecovery,
    required void Function() release,
    this.changed = true,
  }) : _release = release;

  final String key;
  final Map<String, dynamic> document;
  final bool changed;
  final void Function() publish;
  final void Function() blockRecovery;
  final void Function() _release;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

/// 复用现有文档存储；失败补写各自原文档，不替换整库。
/// 不承诺断电或进程强杀时的跨文档原子性。
Future<void> commitLocalDocumentWrites(
    LocalStorageService storage, List<PreparedLocalDocumentWrite> writes,
    {required String label}) async {
  try {
    final changed = writes.where((write) => write.changed).toList();
    final previous = {
      for (final write in changed) write.key: storage.readJson(write.key)
    };
    try {
      for (final write in changed) {
        storage.saveJson(write.key, write.document);
      }
      if (changed.isNotEmpty) await storage.flush();
    } catch (_) {
      var recoveryFailed = false;
      // 即使一份文档恢复失败，也继续尝试恢复其余文档并等待写队列结束。
      for (final entry in previous.entries) {
        try {
          if (entry.value == null) {
            storage.remove(entry.key);
          } else {
            storage.saveJson(entry.key, entry.value!);
          }
        } catch (_) {
          recoveryFailed = true;
        }
      }
      try {
        await storage.flush();
      } catch (_) {
        recoveryFailed = true;
      }
      if (recoveryFailed) {
        for (final write in writes) {
          write.blockRecovery();
        }
        throw StateError('$label保存失败，原记录恢复也失败；磁盘状态无法确认，请重启检查后再操作。');
      }
      throw StateError('$label保存失败，已恢复原记录；请重试。');
    }
    for (final write in writes) {
      write.publish();
    }
  } finally {
    for (final write in writes) {
      write.release();
    }
  }
}
