import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

const int maximumGpxFileBytes = 20 * 1024 * 1024;

class ActivityDocument {
  const ActivityDocument({
    required this.fileName,
    required this.contents,
    required this.sizeBytes,
  });

  final String fileName;
  final String contents;
  final int sizeBytes;

  factory ActivityDocument.fromBytes({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (!fileName.toLowerCase().endsWith('.gpx')) {
      throw const FormatException('仅支持 .gpx 训练轨迹文件。');
    }
    if (bytes.length > maximumGpxFileBytes) {
      throw const FormatException('GPX 文件不能超过 20 MB。');
    }
    try {
      return ActivityDocument(
        fileName: fileName,
        contents: utf8.decode(bytes, allowMalformed: false),
        sizeBytes: bytes.length,
      );
    } on FormatException {
      throw const FormatException('GPX 文件不是有效的 UTF-8 文本。');
    }
  }
}

abstract interface class ActivityDocumentPicker {
  Future<ActivityDocument?> pickGpx();
}

class SystemActivityDocumentPicker implements ActivityDocumentPicker {
  const SystemActivityDocumentPicker();

  static const XTypeGroup _gpxTypeGroup = XTypeGroup(
    label: 'GPX 训练轨迹',
    extensions: <String>['gpx'],
  );

  @override
  Future<ActivityDocument?> pickGpx() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_gpxTypeGroup],
    );
    if (file == null) return null;
    final int length = await file.length();
    if (length > maximumGpxFileBytes) {
      throw const FormatException('GPX 文件不能超过 20 MB。');
    }
    return ActivityDocument.fromBytes(
      fileName: file.name,
      bytes: await file.readAsBytes(),
    );
  }
}
