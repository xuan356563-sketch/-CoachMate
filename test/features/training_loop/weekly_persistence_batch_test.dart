import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as timezone;
import 'package:trainflow_ai/data/models/weekly_psych_check_in.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/features/auth/application/account_switch_coordinator.dart';
import 'package:trainflow_ai/features/weekly_report/weekly_report_page.dart';
import 'package:trainflow_ai/features/reminders/application/reminder_settings_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/plugins/history/core_history.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/system_training_notification_service.dart';

import '../../support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('磁盘完成前不发布成功，重复保存和方向变更不得交错', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    await f.save('旧报告');
    final old = f.state.savedWeeklyReports.single;
    f.storage.pending = Completer<void>();
    final saving = f.save('新报告');
    await Future<void>.delayed(Duration.zero);
    expect(f.state.savedWeeklyReports.single.toJson(), old.toJson());
    expect(f.state.weeklyReportSaveStatusMessage, contains('正在保存'));
    await expectLater(f.save('重复操作'), throwsStateError);
    await expectLater(
        Future<void>.sync(() => f.controller.selectWeeklyReportOption(
            reportId: old.id, optionId: old.options.first.id)),
        throwsStateError);
    f.storage.pending!.complete();
    await saving;
    expect(f.state.savedWeeklyReports, hasLength(1));
    expect(f.state.savedWeeklyReports.single.psychCheckIn!.weekNote, '新报告');
  });

  for (final synchronous in [false, true]) {
    test('${synchronous ? '同步写入' : '异步持久化'}失败恢复原报告和缓存，重试只保存一份', () async {
      final f = await _Fixture.create();
      addTearDown(f.close);
      await f.save('保留的报告');
      final before =
          f.storage.readJson(PersistedWeeklyReportRepository.storageKey);
      final old = f.state.savedWeeklyReports.single.toJson();
      f.storage.failSync = synchronous;
      f.storage.failFlushes = synchronous ? 0 : 1;
      await expectLater(f.save('失败的报告'), throwsStateError);
      expect(f.state.savedWeeklyReports.single.toJson(), old);
      expect(f.storage.readJson(PersistedWeeklyReportRepository.storageKey),
          before);
      expect(
          PersistedWeeklyReportRepository(f.storage)
              .listReports()
              .single
              .toJson(),
          old);
      await f.save('重试成功');
      expect(f.state.savedWeeklyReports, hasLength(1));
      expect(f.state.savedWeeklyReports.single.psychCheckIn!.weekNote, '重试成功');
    });
  }

  test('首次保存失败不遗留报告，下周方向失败保留旧选择', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    f.storage.failFlushes = 1;
    await expectLater(f.save('未落盘'), throwsStateError);
    expect(
        f.storage.readJson(PersistedWeeklyReportRepository.storageKey), isNull);
    expect(f.state.savedWeeklyReports, isEmpty);
    await f.save('已落盘');
    final report = f.state.savedWeeklyReports.single;
    final before =
        f.storage.readJson(PersistedWeeklyReportRepository.storageKey);
    f.storage.failFlushes = 1;
    await expectLater(
        Future<void>.sync(() => f.controller.selectWeeklyReportOption(
            reportId: report.id, optionId: report.options.first.id)),
        throwsStateError);
    expect(f.state.savedWeeklyReports.single.selectedOptionId, isNull);
    expect(
        f.storage.readJson(PersistedWeeklyReportRepository.storageKey), before);
    await Future<void>.sync(() => f.controller.selectWeeklyReportOption(
        reportId: report.id, optionId: report.options.first.id));
    expect(
        PersistedWeeklyReportRepository(f.storage)
            .listReports()
            .single
            .selectedOptionId,
        report.options.first.id);
  });

  test('恢复写入也失败时明确不确定，禁止显示保存成功', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    await f.save('旧报告');
    f.storage.failFlushes = 2;
    await expectLater(
        f.save('新报告'),
        throwsA(isA<StateError>()
            .having((e) => e.message, '恢复状态', contains('恢复'))));
    expect(f.state.weeklyReportSaveStatusMessage, isNot(contains('已保存')));
    expect(f.state.savedWeeklyReports.single.psychCheckIn!.weekNote, '旧报告');
    await expectLater(f.save('恢复前不得继续写入'), throwsStateError);
  });

  test('保存期间阻止停用及换账号，完成后停用仍可读核心历史', () async {
    final f = await _Fixture.create();
    addTearDown(f.close);
    f.storage.pending = Completer<void>();
    final saving = f.save('账号甲');
    await Future<void>.delayed(Duration.zero);
    await expectLater(
        f.runtime.disable('feature.weekly_report'), throwsStateError);
    var scopeReplaced = false;
    await expectLater(f.runtime.changeAccountScope(replaceScope: () {
      scopeReplaced = true;
      f.storage.clearBusinessData();
    }), throwsStateError);
    expect(scopeReplaced, isFalse);
    f.storage.pending!.complete();
    await saving;
    await f.runtime.disable('feature.weekly_report');
    await expectLater(f.save('停用后不得写入'), throwsStateError);
    expect(
        f.container
            .read(coreHistoryProvider)
            .listWeeklyReports()
            .single
            .psychCheckIn!
            .weekNote,
        '账号甲');
    await f.runtime.enable('feature.weekly_report');
    await f.save('重新启用');
    expect(f.state.savedWeeklyReports.single.psychCheckIn!.weekNote, '重新启用');
    await f.runtime.changeAccountScope(replaceScope: () async {
      f.storage.clearBusinessData();
      await f.storage.flush();
    });
    f.container.read(accountSwitchCoordinatorProvider).resetInMemoryState();
    expect(f.state.savedWeeklyReports, isEmpty);
    await f.save('账号乙');
    expect(f.state.savedWeeklyReports, hasLength(1));
    expect(f.state.savedWeeklyReports.single.psychCheckIn!.weekNote, '账号乙');
  });

  test('控制器销毁后的迟到保存完成不更新新控制器', () async {
    final f = await _Fixture.create();
    f.storage.pending = Completer<void>();
    final saving = f.save('旧控制器已提交的记录');
    await Future<void>.delayed(Duration.zero);
    f.close();
    final next = await _Fixture.create();
    addTearDown(next.close);
    f.storage.pending!.complete();
    await saving;
    expect(next.state.savedWeeklyReports, isEmpty);
    expect(next.storage.readJson(PersistedWeeklyReportRepository.storageKey),
        isNull);
  });

  testWidgets('失败保留填写内容并允许重试，等待时禁用保存按钮', (tester) async {
    tester.view.physicalSize = const Size(393, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _ControlledStorage();
    await tester.pumpWidget(TestHarness(storageService: storage)
        .buildApp(const MaterialApp(home: WeeklyReportPage())));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('weekly-psych-note')), '合成复盘保留');
    storage.failFlushes = 1;
    storage.pending = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('weekly-psych-save')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('weekly-psych-save')))
            .onPressed,
        isNull);
    storage.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsWidgets);
    expect(find.text('合成复盘保留'), findsOneWidget);
    expect(
        storage.readJson(PersistedWeeklyReportRepository.storageKey), isNull);
    await tester.tap(find.byKey(const ValueKey('weekly-psych-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('周报状态已保存在本地'), findsOneWidget);
    expect(
        PersistedWeeklyReportRepository(storage)
            .listReports()
            .single
            .psychCheckIn!
            .weekNote,
        '合成复盘保留');
  });
}

class _ControlledStorage extends InMemoryLocalStorageService {
  Completer<void>? pending;
  int failFlushes = 0;
  bool failSync = false;
  @override
  void saveJson(String key, Map<String, dynamic> value) {
    if (key == PersistedWeeklyReportRepository.storageKey && failSync) {
      failSync = false;
      throw StateError('合成同步写入失败');
    }
    super.saveJson(key, value);
  }

  @override
  Future<void> flush() async {
    await pending?.future;
    if (failFlushes > 0) {
      failFlushes--;
      throw StateError('合成磁盘写入失败');
    }
  }
}

class _Fixture {
  _Fixture(this.storage, this.runtime, this.container);
  final _ControlledStorage storage;
  final PluginRuntime runtime;
  final ProviderContainer container;
  TrainingMvpController get controller =>
      container.read(trainingMvpProvider.notifier);
  TrainingMvpState get state => container.read(trainingMvpProvider);
  Future<void> save(String note) =>
      Future<void>.sync(() => controller.savePsychologyWeeklyReport(
          psychCheckIn: WeeklyPsychCheckIn(weekNote: note)));
  static Future<_Fixture> create() async {
    final storage = _ControlledStorage();
    final runtime =
        PluginRuntime(PluginRegistry(plugins: builtInDistribution()));
    await runtime.initialize();
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      trainingNotificationSchedulerProvider.overrideWithValue(
          TrainingNotificationScheduler(_NotificationGateway())),
    ]);
    container.read(trainingMvpProvider);
    await Future<void>.delayed(Duration.zero);
    return _Fixture(storage, runtime, container);
  }

  void close() => container.dispose();
}

class _NotificationGateway implements TrainingNotificationGateway {
  @override
  Future<void> cancelTrainingNotifications() async {}
  @override
  Future<timezone.Location> loadLocalLocation() async => timezone.UTC;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(TrainingNotificationRequest request) async {}
}
