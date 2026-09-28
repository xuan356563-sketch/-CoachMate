import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/pilot_validation.dart';
import 'package:trainflow_ai/data/models/self_use_acceptance.dart';
import 'package:trainflow_ai/data/repositories/pilot_validation_repository.dart';
import 'package:trainflow_ai/data/repositories/self_use_acceptance_repository.dart';
import 'package:trainflow_ai/features/pilot_validation/application/pilot_validation_service.dart';
import 'package:trainflow_ai/features/self_use_acceptance/application/self_use_acceptance_service.dart';
import 'package:trainflow_ai/features/self_use_acceptance/self_use_acceptance_page.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('验收服务绕过页面调用时仍拒绝停用功能写入', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final PersistedPilotValidationRepository repository =
        PersistedPilotValidationRepository(storage);
    final PilotValidationService service = PilotValidationService(
      repository: repository,
      storage: storage,
      featureAccess: runtime,
    );

    await runtime.disable(PilotValidationService.featureId);
    await expectLater(
      service.addParticipant(
        scenario: PilotScenario.raceRunning,
        startedOn: DateTime(2026, 9, 4),
      ),
      throwsStateError,
    );

    expect(repository.listParticipants(), isEmpty);
    expect(
      storage.readJson(PersistedPilotValidationRepository.storageKey),
      isNull,
    );
  });

  test('自用验收停用后只读且清空例外不触发任何补写', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    final SelfUseAcceptanceRepository repository =
        PersistedSelfUseAcceptanceRepository(storage);
    final SelfUseAcceptanceService service = SelfUseAcceptanceService(
      repository: repository,
      storage: storage,
      featureAccess: runtime,
    );
    final SelfUseAcceptanceRecord started =
        await service.start(DateTime(2026, 9, 4));

    await runtime.disable(SelfUseAcceptanceService.featureId);
    expect(service.getRecord().startedAt, started.startedAt);
    await expectLater(
      service.updateDay(started.days.first.copyWith(bodyDataLogged: true)),
      throwsStateError,
    );
    expect(service.getRecord().days.first.bodyDataLogged, isFalse);

    await service.clear();
    expect(service.getRecord(), const SelfUseAcceptanceRecord.empty());
    expect(
      storage.readJson(PersistedSelfUseAcceptanceRepository.storageKey),
      isNull,
    );
  });

  test('自用验收update落盘失败时恢复原记录并返回中文错误', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _FailNextFlushStorage storage = _FailNextFlushStorage();
    final PersistedSelfUseAcceptanceRepository repository =
        PersistedSelfUseAcceptanceRepository(storage);
    final SelfUseAcceptanceService service = SelfUseAcceptanceService(
      repository: repository,
      storage: storage,
      featureAccess: runtime,
    );
    final SelfUseAcceptanceRecord started = await service.start(DateTime.now());
    storage.failNext = true;

    await expectLater(
      service.updateDay(started.days.first.copyWith(notes: '不应保存')),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('已恢复原记录'),
        ),
      ),
    );
    expect(service.getRecord().days.first.notes, isEmpty);
    expect(
      PersistedSelfUseAcceptanceRepository(storage)
          .getRecord()
          .days
          .first
          .notes,
      isEmpty,
    );
  });

  test('自用验收恢复flush也失败时不声称持久化恢复成功', () async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _FailNextFlushStorage storage = _FailNextFlushStorage();
    final PersistedSelfUseAcceptanceRepository repository =
        PersistedSelfUseAcceptanceRepository(storage);
    final SelfUseAcceptanceService service = SelfUseAcceptanceService(
      repository: repository,
      storage: storage,
      featureAccess: runtime,
    );
    final SelfUseAcceptanceRecord started = await service.start(DateTime.now());
    storage.failuresRemaining = 2;

    await expectLater(
      service.updateDay(started.days.first.copyWith(notes: '不应保存')),
      throwsA(
        isA<StateError>()
            .having(
              (StateError error) => error.message,
              'message',
              contains('恢复落盘也失败'),
            )
            .having(
              (StateError error) => error.message,
              'message',
              isNot(contains('已恢复原记录')),
            ),
      ),
    );
    expect(service.getRecord().days.first.notes, isEmpty);
  });

  testWidgets('自用验收保存失败只显示中文错误且不显示成功', (WidgetTester tester) async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _FailNextFlushStorage storage = _FailNextFlushStorage();
    PersistedSelfUseAcceptanceRepository(storage).start(DateTime.now());
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SelfUseAcceptancePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存今日记录'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '不应显示成功');
    storage.failNext = true;
    await tester.tap(find.text('保存今日记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已恢复原记录'), findsOneWidget);
    expect(find.text('今日验收记录已保存。'), findsNothing);
    expect(
      PersistedSelfUseAcceptanceRepository(storage)
          .getRecord()
          .days
          .first
          .notes,
      isEmpty,
    );
  });

  testWidgets('自用验收双flush失败时页面不声称恢复或保存成功', (WidgetTester tester) async {
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    final _FailNextFlushStorage storage = _FailNextFlushStorage();
    PersistedSelfUseAcceptanceRepository(storage).start(DateTime.now());
    final ProviderContainer container = ProviderContainer(overrides: [
      pluginRuntimeProvider.overrideWith((ref) => runtime),
      localStorageServiceProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SelfUseAcceptancePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存今日记录'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '不应显示成功');
    storage.failuresRemaining = 2;
    await tester.tap(find.text('保存今日记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('恢复落盘也失败'), findsOneWidget);
    expect(find.textContaining('已恢复原记录'), findsNothing);
    expect(find.text('今日验收记录已保存。'), findsNothing);
  });
}

class _FailNextFlushStorage extends InMemoryLocalStorageService {
  int failuresRemaining = 0;

  set failNext(bool value) {
    failuresRemaining = value ? 1 : 0;
  }

  @override
  Future<void> flush() async {
    if (failuresRemaining == 0) return;
    failuresRemaining -= 1;
    throw StateError('测试落盘失败');
  }
}
