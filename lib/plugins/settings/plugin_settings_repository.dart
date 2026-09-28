import 'dart:convert';

import '../../services/local_storage_service.dart';
import 'plugin_settings.dart';

class PluginSettingsPersistenceException implements Exception {
  const PluginSettingsPersistenceException(this.message,
      {this.recoveryFailed = false});

  final String message;
  final bool recoveryFailed;

  @override
  String toString() => message;
}

class PluginSettingsRepository {
  PluginSettingsRepository(this.storage);

  final LocalStorageService storage;

  PluginSettingsReadResult read() {
    if (storage case final RawJsonDocumentStorage rawStorage) {
      final String? rawText =
          rawStorage.readRawJsonDocument(pluginSettingsStorageKey);
      if (rawText == null) {
        return const PluginSettingsReadResult(
          settings: PluginSettings(),
          rawDocument: null,
        );
      }
      try {
        final Object? decoded = jsonDecode(rawText);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('功能设置不是对象');
        }
        return _parse(decoded);
      } on FormatException {
        return PluginSettingsReadResult(
          settings: const PluginSettings(),
          rawDocument: null,
          rawDocumentText: rawText,
          recoveryMessage: _recoveryMessage(null),
        );
      }
    }

    Map<String, dynamic>? raw;
    try {
      raw = storage.readJson(pluginSettingsStorageKey);
    } on FormatException {
      return PluginSettingsReadResult(
        settings: const PluginSettings(),
        rawDocument: null,
        rawDocumentUnreadable: true,
        recoveryMessage: _recoveryMessage(null),
      );
    }
    if (raw == null) {
      return const PluginSettingsReadResult(
        settings: PluginSettings(),
        rawDocument: null,
      );
    }
    return _parse(raw);
  }

  PluginSettingsReadResult _parse(Map<String, dynamic> raw) {
    try {
      return PluginSettingsReadResult(
        settings: PluginSettings.fromJson(raw),
        rawDocument: Map<String, dynamic>.from(raw),
      );
    } on FormatException {
      return PluginSettingsReadResult(
        settings: const PluginSettings(),
        rawDocument: Map<String, dynamic>.from(raw),
        recoveryMessage: _recoveryMessage(raw['version']),
      );
    }
  }

  String _recoveryMessage(Object? version) => version is int && version > 1
      ? '本机功能设置来自更新版本，当前版本无法安全修改。请恢复默认设置或更新应用。'
      : '本机功能设置已损坏，已临时按默认功能启动。训练数据未被清除，请恢复默认设置后再修改。';

  Future<void> commit(
    PluginSettings next, {
    required Map<String, dynamic>? previousDocument,
    String? previousDocumentText,
    bool previousDocumentUnreadable = false,
  }) async {
    storage.saveJson(pluginSettingsStorageKey, next.toJson());
    try {
      await storage.flush();
    } catch (_) {
      if (previousDocumentText != null && storage is RawJsonDocumentStorage) {
        (storage as RawJsonDocumentStorage).saveRawJsonDocument(
          pluginSettingsStorageKey,
          previousDocumentText,
        );
      } else if (previousDocumentUnreadable) {
        throw const PluginSettingsPersistenceException(
          '功能设置保存失败，原设置无法安全恢复；请重启应用后重试。',
          recoveryFailed: true,
        );
      } else if (previousDocument == null) {
        storage.remove(pluginSettingsStorageKey);
      } else {
        storage.saveJson(pluginSettingsStorageKey, previousDocument);
      }
      try {
        await storage.flush();
      } catch (_) {
        throw const PluginSettingsPersistenceException(
          '功能设置保存失败，恢复落盘也失败；当前显示可能与下次启动不同，请重试或重启应用。',
          recoveryFailed: true,
        );
      }
      throw const PluginSettingsPersistenceException(
        '功能设置保存失败，已恢复原设置，请重试。',
      );
    }
  }
}
