import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/services/activity_document_picker.dart';

void main() {
  test('GPX文档只接受正确扩展名和UTF-8内容', () {
    final ActivityDocument document = ActivityDocument.fromBytes(
      fileName: 'morning-run.GPX',
      bytes: Uint8List.fromList(utf8.encode('<gpx></gpx>')),
    );

    expect(document.fileName, 'morning-run.GPX');
    expect(document.contents, '<gpx></gpx>');
  });

  test('非GPX文件显示中文错误', () {
    expect(
      () => ActivityDocument.fromBytes(
        fileName: 'workout.txt',
        bytes: Uint8List.fromList(utf8.encode('<gpx></gpx>')),
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('仅支持 .gpx'),
        ),
      ),
    );
  });

  test('超过20MB的GPX在解码前被拒绝', () {
    expect(
      () => ActivityDocument.fromBytes(
        fileName: 'too-large.gpx',
        bytes: Uint8List(maximumGpxFileBytes + 1),
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('20 MB'),
        ),
      ),
    );
  });
}
