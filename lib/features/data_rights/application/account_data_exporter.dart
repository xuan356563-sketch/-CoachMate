import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountDataExporterProvider = Provider<AccountDataExporter>(
  (Ref ref) => const SystemAccountDataExporter(),
);

abstract interface class AccountDataExporter {
  /// 返回保存路径；用户取消保存时返回空值。
  Future<String?> saveJson(Uint8List bytes, String suggestedName);
}

class SystemAccountDataExporter implements AccountDataExporter {
  const SystemAccountDataExporter();

  static const XTypeGroup _jsonType = XTypeGroup(
    label: 'JSON 数据文件',
    extensions: <String>['json'],
    mimeTypes: <String>['application/json'],
  );

  @override
  Future<String?> saveJson(Uint8List bytes, String suggestedName) async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const <XTypeGroup>[_jsonType],
      confirmButtonText: '保存',
    );
    if (location == null) return null;
    await XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: suggestedName,
    ).saveTo(location.path);
    return location.path;
  }
}
