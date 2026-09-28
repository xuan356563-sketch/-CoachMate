import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/features/built_in_features.dart';
import 'package:trainflow_ai/plugins/features/motion_check_plugin.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/features/motion_check/running/running_pose_models.dart';
import 'package:trainflow_ai/features/motion_check/running/running_video_pose_gateway.dart';
import 'package:trainflow_ai/features/motion_check/running/running_video_controller.dart';
import 'package:trainflow_ai/features/motion_check/running/running_form_report_repository.dart';
import 'package:trainflow_ai/features/motion_check/running/running_video_page.dart';
import 'package:trainflow_ai/features/motion_check/running/running_report_view.dart';
import 'running_metrics_test.dart' show sequence;
import 'running_repository_test.dart' show report;
import 'package:trainflow_ai/features/capabilities/running_history_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('没有发行开关或拍摄确认不能调用视频提取', () async {
    final f = await _Fixture.create(preview: false);
    addTearDown(f.close);
    await f.controller.start(captureConfirmed: true);
    expect(f.gateway.calls, 0);
    final g = await _Fixture.create();
    addTearDown(g.close);
    await g.controller.start(captureConfirmed: false);
    expect(g.gateway.calls, 0);
  });
  test('连续点击只选择一次，取消后迟到结果不保存不显示', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    final first = f.controller.start(captureConfirmed: true);
    await f.controller.start(captureConfirmed: true);
    await f.waitForExtraction();
    expect(f.gateway.calls, 1);
    await f.controller.cancel();
    f.gateway.pending!.complete(sequence());
    await first;
    expect(f.state.report, isNull);
    expect(f.repository.list(), isEmpty);
    expect(f.gateway.cancels, 1);
  });
  test('分析完成不自动保存，手动保存后计划及照片记录原样保留', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    f.storage
        .saveJson('trainflow.generated_training_plan.v1', {'sentinel': '有效计划'});
    f.storage.saveJson('trainflow.motion_analysis_results.v1', {'results': []});
    final future = f.controller.start(captureConfirmed: true);
    await f.waitForExtraction();
    f.gateway.pending!.complete(sequence());
    await future;
    expect(f.state.phase, RunningVideoPhase.ready);
    expect(f.repository.list(), isEmpty);
    await f.controller.save();
    expect(f.state.saved, isTrue);
    expect(f.repository.list(), hasLength(1));
    expect(f.storage.readJson('trainflow.generated_training_plan.v1'),
        {'sentinel': '有效计划'});
    expect(f.storage.readJson('trainflow.motion_analysis_results.v1'),
        {'results': []});
  });
  test('停用动作分析释放任务，重新启用后可以重新分析', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    final future = f.controller.start(captureConfirmed: true);
    await f.waitForExtraction();
    expect((await f.runtime.disable('feature.motion_check')).isSuccess, isTrue);
    f.gateway.pending!.complete(sequence());
    await future;
    expect(f.state.report, isNull);
    expect((await f.runtime.enable('feature.motion_check')).isSuccess, isTrue);
    final next = f.controller.start(captureConfirmed: true);
    await f.waitForExtraction();
    f.gateway.pending!.complete(sequence());
    await next;
    expect(f.state.report, isNotNull);
  });
  test('账号切换清理报告并丢弃旧域迟到结果', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    final future = f.controller.start(captureConfirmed: true);
    await f.waitForExtraction();
    await f.runtime.changeAccountScope(replaceScope: () async {
      f.storage.clearBusinessData();
      await f.storage.flush();
    });
    f.gateway.pending!.complete(sequence());
    await future;
    expect(f.state.report, isNull);
    expect(f.repository.list(), isEmpty);
  });
  test('进入后台立即使任务失效', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    final future = f.controller.start(captureConfirmed: true);
    await f.waitForExtraction();
    f.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    f.gateway.pending!.complete(sequence());
    await future;
    expect(f.state.report, isNull);
    expect(f.gateway.cancels, greaterThanOrEqualTo(1));
  });
  testWidgets('结果页显示骨架和分项，离开页面清理视频任务', (tester) async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: f.container,
        child: const MaterialApp(home: RunningVideoPage())));
    final future = f.controller.start(captureConfirmed: true);
    await tester.pump();
    await f.waitForExtraction();
    f.gateway.pending!.complete(sequence());
    await future;
    await tester.pumpAndSettle();
    expect(find.byType(RunningReportView), findsOneWidget);
    expect(find.text('周期节奏一致性'), findsOneWidget);
    expect(f.repository.list(), isEmpty);
    // 释放测试监听，验证页面退出触发 autoDispose 清理。
    f.subscription.close();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1));
    expect(f.gateway.cancels, greaterThanOrEqualTo(1));
  });
  testWidgets('停用后历史可读且不写存储，账号清理后旧报告不再显示', (tester) async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    await f.repository.save(report('history-report'));
    final before = f.storage.readJson(RunningFormReportRepository.storageKey);
    await f.runtime.disable('feature.motion_check');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: f.container,
        child: const MaterialApp(home: RunningHistoryPage())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-report')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-report')));
    await tester.pumpAndSettle();
    expect(find.byType(RunningReportView), findsOneWidget);
    expect(f.storage.readJson(RunningFormReportRepository.storageKey), before);
    expect(f.gateway.calls, 0);
    await f.runtime.changeAccountScope(replaceScope: () async {
      f.storage.clearBusinessData();
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-report')), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
  test('三项技能注册真实实现，运动引用不建立计划强依赖', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    final descriptor = f.runtime.registry.descriptors['feature.motion_check']!;
    expect(descriptor.skills, hasLength(3));
    for (final skill in descriptor.skills) {
      expect(f.runtime.registry.readCapability<Object>(skill.capabilityId!),
          isNotNull);
    }
    for (final id in ['sport.marathon', 'sport.trail_running', 'sport.hyrox']) {
      final sport = f.runtime.registry.descriptors[id]!;
      expect(sport.workflows.singleWhere((w) => w.capabilityId == 'feature.motion_check.running_review').ownerPluginId, 'feature.motion_check');
      expect(sport.dependencies, isNot(contains('feature.motion_check')));
    }
  });
}

class _Fixture {
  _Fixture(this.runtime, this.gateway, this.storage, this.container,
      this.subscription);
  final PluginRuntime runtime;
  final _Gateway gateway;
  final InMemoryLocalStorageService storage;
  final ProviderContainer container;
  final ProviderSubscription<RunningVideoState> subscription;
  RunningVideoController get controller =>
      container.read(runningVideoControllerProvider.notifier);
  RunningVideoState get state => container.read(runningVideoControllerProvider);
  RunningFormReportRepository get repository =>
      container.read(runningFormReportRepositoryProvider);
  static Future<_Fixture> create({bool preview = true}) async {
    final gateway = _Gateway(), storage = InMemoryLocalStorageService();
    final feature =
        builtInFeatures.singleWhere((f) => f.id == 'feature.motion_check');
    final runtime = PluginRuntime(PluginRegistry(
        plugins: builtInDistribution(replacements: {
      'feature.motion_check': BuiltInFeaturePlugin(feature,
          delegate: MotionCheckPlugin(gatewayFactory: () => gateway)),
    })));
    expect((await runtime.initialize()).isSuccess, isTrue);
    final container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
      runningVideoPreviewProvider.overrideWithValue(preview),
      runningVideoPickerProvider.overrideWithValue(_Picker())
    ]);
    final subscription =
        container.listen(runningVideoControllerProvider, (_, __) {});
    return _Fixture(runtime, gateway, storage, container, subscription);
  }

  Future<void> waitForExtraction() async {
    for (var i = 0;
        i < 20 && state.phase != RunningVideoPhase.extracting;
        i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(state.phase, RunningVideoPhase.extracting);
  }

  Future<void> close() async {
    container.dispose();
  }
}

class _Picker implements RunningVideoPicker {
  @override
  Future<String?> pick() async => '合成视频路径';
}

class _Gateway implements RunningVideoPoseGateway {
  int calls = 0, cancels = 0;
  Completer<RunningPoseSequence>? pending;
  @override
  bool get isSupported => true;
  @override
  Future<RunningPoseSequence> analyze(
      {required String taskId,
      required String path,
      required void Function(double) onProgress}) {
    calls++;
    pending = Completer<RunningPoseSequence>();
    onProgress(.5);
    return pending!.future;
  }

  @override
  Future<Uint8List?> thumbnail(String taskId, double seconds) async => null;
  @override
  Future<void> cancel(String taskId) async {
    cancels++;
  }

  @override
  Future<void> dispose() async {}
}
