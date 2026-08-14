import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/config/api_config.dart';

void main() {
  group('ApiConfig.resolveBaseUrl', () {
    test('开发环境未配置时使用本机地址', () {
      expect(
        ApiConfig.resolveBaseUrl(
          configuredBaseUrl: '',
          isProduct: false,
        ),
        'http://127.0.0.1:8000',
      );
    });

    test('生产环境必须显式配置 API 地址', () {
      expect(
        () => ApiConfig.resolveBaseUrl(
          configuredBaseUrl: '',
          isProduct: true,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('必须显式配置'),
          ),
        ),
      );
    });

    test('生产环境拒绝 HTTP 和 localhost', () {
      for (final String value in <String>[
        'http://api.trainmate.example',
        'https://localhost:8000',
        'https://127.0.0.1:8000',
      ]) {
        expect(
          () => ApiConfig.resolveBaseUrl(
            configuredBaseUrl: value,
            isProduct: true,
          ),
          throwsStateError,
        );
      }
    });

    test('生产环境接受 HTTPS 并移除末尾斜杠', () {
      expect(
        ApiConfig.resolveBaseUrl(
          configuredBaseUrl: 'https://api.trainmate.example///',
          isProduct: true,
        ),
        'https://api.trainmate.example',
      );
    });
  });
}
