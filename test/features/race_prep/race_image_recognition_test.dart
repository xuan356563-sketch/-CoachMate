import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/auth/data/session_token_store.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/race_prep/application/race_image_recognition_controller.dart';
import 'package:trainflow_ai/features/race_prep/race_prep_page.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class MemoryTokenStore implements SessionTokenStore {
  @override
  String? accessToken = 'test-access-token';
  String? refreshToken = 'test-refresh-token';

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> updateAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
}

class FakeRaceImagePicker implements RaceImagePicker {
  final RaceImageFile? image;
  final PlatformException? error;
  RaceImageSource? lastSource;

  FakeRaceImagePicker({this.image, this.error});

  @override
  Future<RaceImageFile?> pick(RaceImageSource source) async {
    lastSource = source;
    if (error != null) {
      throw error!;
    }
    return image;
  }
}

class StaticRaceImageRecognitionController
    extends RaceImageRecognitionController {
  @override
  Future<RaceImageRecognitionState> build() async {
    return RaceImageRecognitionState(
      status: RaceImageRecognitionStatus.success,
      image: RaceImageFile(bytes: _png, name: 'race.png'),
      result: const RaceImageRecognitionResult(
        provider: 'minimax',
        model: 'MiniMax-M3',
        name: '城市秋季马拉松',
        type: 'marathon',
        raceDate: '2026-11-29',
        targetResult: '04:00:00',
        courseInfo: '城市公路，42.195km',
        normalizedText: '赛事：城市秋季马拉松\n类型：marathon\n日期：2026-11-29\n'
            '目标：04:00:00\n赛道：城市公路，42.195km',
        matchedFieldCount: 5,
        warnings: <String>[],
      ),
    );
  }
}

void main() {
  test('选择图片后完成识别，但不会自动覆盖赛事文本', () async {
    final FakeRaceImagePicker picker = FakeRaceImagePicker(
      image: RaceImageFile(bytes: _png, name: 'race.png'),
    );
    final ProviderContainer container = _container(
      picker: picker,
      client: _recognitionClient(),
    );
    addTearDown(container.dispose);
    final String originalText = container.read(raceImportTextProvider);
    await container.read(raceImageRecognitionControllerProvider.future);

    await container
        .read(raceImageRecognitionControllerProvider.notifier)
        .pickAndRecognize(RaceImageSource.gallery);

    final RaceImageRecognitionState state =
        container.read(raceImageRecognitionControllerProvider).requireValue;
    expect(state.status, RaceImageRecognitionStatus.success);
    expect(state.result?.name, '城市秋季马拉松');
    expect(state.result?.matchedFieldCount, 5);
    expect(container.read(raceImportTextProvider), originalText);
    expect(picker.lastSource, RaceImageSource.gallery);
  });

  test('取消选择保持空状态', () async {
    final ProviderContainer container = _container(
      picker: FakeRaceImagePicker(),
      client: _recognitionClient(),
    );
    addTearDown(container.dispose);
    await container.read(raceImageRecognitionControllerProvider.future);

    await container
        .read(raceImageRecognitionControllerProvider.notifier)
        .pickAndRecognize(RaceImageSource.gallery);

    expect(
      container
          .read(raceImageRecognitionControllerProvider)
          .requireValue
          .status,
      RaceImageRecognitionStatus.idle,
    );
  });

  test('相册权限拒绝显示中文提示', () async {
    final ProviderContainer container = _container(
      picker: FakeRaceImagePicker(
        error: PlatformException(code: 'photo_access_denied'),
      ),
      client: _recognitionClient(),
    );
    addTearDown(container.dispose);
    await container.read(raceImageRecognitionControllerProvider.future);

    await container
        .read(raceImageRecognitionControllerProvider.notifier)
        .pickAndRecognize(RaceImageSource.gallery);

    final RaceImageRecognitionState state =
        container.read(raceImageRecognitionControllerProvider).requireValue;
    expect(state.status, RaceImageRecognitionStatus.failure);
    expect(state.errorMessage, contains('允许 TrainFlow 访问照片'));
  });

  test('超过 10MB 的图片在上传前被拒绝', () async {
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      return _jsonResponse(<String, dynamic>{});
    });
    final ProviderContainer container = _container(
      picker: FakeRaceImagePicker(
        image: RaceImageFile(
          bytes: Uint8List(
            RaceImageRecognitionController.maxImageBytes + 1,
          ),
          name: 'large.png',
        ),
      ),
      client: client,
    );
    addTearDown(container.dispose);
    await container.read(raceImageRecognitionControllerProvider.future);

    await container
        .read(raceImageRecognitionControllerProvider.notifier)
        .pickAndRecognize(RaceImageSource.gallery);

    final RaceImageRecognitionState state =
        container.read(raceImageRecognitionControllerProvider).requireValue;
    expect(state.status, RaceImageRecognitionStatus.failure);
    expect(state.errorMessage, '图片不能超过 10MB');
    expect(requestCount, 0);
  });

  test('后端限流错误会显示稳定中文提示', () async {
    final ProviderContainer container = _container(
      picker: FakeRaceImagePicker(
        image: RaceImageFile(bytes: _png, name: 'race.png'),
      ),
      client: MockClient((http.Request request) async {
        return _jsonResponse(
          <String, dynamic>{
            'code': 'race_recognition_rate_limited',
            'detail': '图片识别次数过多，请十分钟后再试',
          },
          statusCode: 429,
        );
      }),
    );
    addTearDown(container.dispose);
    await container.read(raceImageRecognitionControllerProvider.future);

    await container
        .read(raceImageRecognitionControllerProvider.notifier)
        .pickAndRecognize(RaceImageSource.gallery);

    final RaceImageRecognitionState state =
        container.read(raceImageRecognitionControllerProvider).requireValue;
    expect(state.status, RaceImageRecognitionStatus.failure);
    expect(state.errorMessage, contains('十分钟后再试'));
  });

  test('赛事识别 Future 迟到时停用会清理结果且不关闭共享客户端', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _DeferredHttpClient client = _DeferredHttpClient();
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      raceImagePickerProvider.overrideWithValue(FakeRaceImagePicker(
        image: RaceImageFile(bytes: _png, name: 'late.png'),
      )),
      sessionTokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      httpClientProvider.overrideWithValue(client),
    ]);
    addTearDown(container.dispose);
    await container.read(raceImageRecognitionControllerProvider.future);
    final Future<void> pending = container
        .read(raceImageRecognitionControllerProvider.notifier)
        .pickAndRecognize(RaceImageSource.gallery);
    await client.called.future;

    await runtime.disable('feature.race_prep');
    client.response.complete(_jsonResponse(<String, dynamic>{
      'provider': 'test',
      'model': 'test',
      'fields': <String, dynamic>{'name': '迟到赛事'},
      'normalized_text': '迟到赛事',
      'matched_field_count': 1,
      'warnings': <String>[],
    }));

    await expectLater(pending, throwsStateError);
    final RaceImageRecognitionState value =
        container.read(raceImageRecognitionControllerProvider).requireValue;
    expect(value.status, RaceImageRecognitionStatus.idle);
    expect(value.image, isNull);
    expect(value.result, isNull);
    expect(client.closed, isFalse);
  });

  testWidgets('点击填入并编辑后才更新文本，并沿用原导入比赛流程', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        raceImageRecognitionControllerProvider.overrideWith(
          StaticRaceImageRecognitionController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    final String originalText = container.read(raceImportTextProvider);
    final int originalRaceCount =
        container.read(trainingMvpProvider).races.length;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RacePrepPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(raceImportTextProvider), originalText);

    final Finder importToggle =
        find.byKey(const ValueKey<String>('race-import-toggle'));
    await _bringIntoViewport(tester, importToggle);
    await tester.tap(importToggle);
    await tester.pumpAndSettle();

    final Finder fillButton = find.widgetWithText(FilledButton, '填入并编辑');
    await _bringIntoViewport(tester, fillButton);
    await tester.tap(fillButton);
    await tester.pumpAndSettle();

    expect(container.read(raceImportTextProvider), contains('城市秋季马拉松'));
    final TextFormField field = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(field.initialValue, contains('2026-11-29'));

    final Finder importButton = find.widgetWithText(FilledButton, '导入比赛');
    await _bringIntoViewport(tester, importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    expect(
      container.read(trainingMvpProvider).races.length,
      originalRaceCount + 1,
    );
    expect(storage.readJson('trainflow.races.v1'), isNotNull);
    expect(tester.takeException(), isNull);
  });
}

class _DeferredHttpClient extends http.BaseClient {
  final Completer<void> called = Completer<void>();
  final Completer<http.Response> response = Completer<http.Response>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!called.isCompleted) called.complete();
    final http.Response value = await response.future;
    return http.StreamedResponse(
      Stream<List<int>>.value(value.bodyBytes),
      value.statusCode,
      headers: value.headers,
      request: request,
    );
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

Future<void> _bringIntoViewport(WidgetTester tester, Finder target) async {
  final Finder scrollable = find.byType(Scrollable).first;
  for (int attempt = 0; attempt < 8; attempt++) {
    final Rect rect = tester.getRect(target);
    if (rect.top >= 0 && rect.bottom <= 840) {
      return;
    }
    await tester.drag(
      scrollable,
      Offset(0, rect.bottom > 840 ? -320 : 320),
    );
    await tester.pumpAndSettle();
  }
}

ProviderContainer _container({
  required RaceImagePicker picker,
  required http.Client client,
}) {
  return ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(
        InMemoryLocalStorageService(),
      ),
      raceImagePickerProvider.overrideWithValue(picker),
      sessionTokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      httpClientProvider.overrideWithValue(client),
    ],
  );
}

MockClient _recognitionClient() {
  return MockClient((http.Request request) async {
    expect(request.url.path, '/v1/races/image-recognition');
    expect(request.headers['authorization'], 'Bearer test-access-token');
    return _jsonResponse(<String, dynamic>{
      'provider': 'minimax',
      'model': 'MiniMax-M3',
      'fields': <String, dynamic>{
        'name': '城市秋季马拉松',
        'type': 'marathon',
        'race_date': '2026-11-29',
        'target_result': '04:00:00',
        'course_info': '城市公路，42.195km',
      },
      'normalized_text': '赛事：城市秋季马拉松\n类型：marathon\n日期：2026-11-29',
      'matched_field_count': 5,
      'warnings': <String>[],
    });
  });
}

http.Response _jsonResponse(
  Map<String, dynamic> body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8'
    },
  );
}
