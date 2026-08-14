import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/daily_activity_summary.dart';
import 'package:trainflow_ai/features/pet/application/daily_activity_sync_controller.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_data_settings_page.dart';

void main() {
  testWidgets('非 iOS 显示平台不可用且缺失字段保持未授权', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyActivitySyncControllerProvider.overrideWith(
            _UnsupportedActivityController.new,
          ),
        ],
        child: const MaterialApp(home: PetDataSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('伙伴数据'), findsOneWidget);
    expect(find.textContaining('当前平台不支持 Apple 健康'), findsOneWidget);
    for (final String field in <String>[
      'steps',
      'activeEnergyKcal',
      'exerciseMinutes',
      'standHours',
    ]) {
      final Finder card = find.byKey(ValueKey<String>('metric-$field'));
      await tester.scrollUntilVisible(
        card,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: card, matching: find.text('未授权')),
        findsOneWidget,
      );
    }
    expect(find.text('0 步'), findsNothing);
  });

  testWidgets('可人工补录步数并恢复自动同步', (tester) async {
    final _ManualActivityController controller = _ManualActivityController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyActivitySyncControllerProvider.overrideWith(() => controller),
        ],
        child: const MaterialApp(home: PetDataSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('manual-steps')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('manual-value-input')),
      '8000',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存补录'));
    await tester.pumpAndSettle();

    expect(controller.lastManualField, DailyActivityField.steps);
    expect(controller.lastManualValue, 8000);
    expect(find.text('8000 步'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('restore-steps')));
    await tester.pumpAndSettle();
    expect(controller.lastRestoredField, DailyActivityField.steps);
  });
}

class _UnsupportedActivityController extends DailyActivitySyncController {
  @override
  Future<DailyActivitySyncState> build() async => DailyActivitySyncState(
        supported: false,
        syncing: false,
        summaries: const <DailyActivitySummary>[],
        suggestedGoals: null,
        statusMessage: '当前平台不支持 Apple 健康同步。',
      );
}

class _ManualActivityController extends DailyActivitySyncController {
  DailyActivityField? lastManualField;
  num? lastManualValue;
  DailyActivityField? lastRestoredField;

  @override
  Future<DailyActivitySyncState> build() async => _state(6200);

  @override
  Future<void> setManualValue(DailyActivityField field, num value) async {
    lastManualField = field;
    lastManualValue = value;
    state = AsyncData<DailyActivitySyncState>(_state(value.toInt()));
  }

  @override
  Future<void> restoreAutomatic(DailyActivityField field) async {
    lastRestoredField = field;
  }

  DailyActivitySyncState _state(int steps) {
    return DailyActivitySyncState(
      supported: true,
      syncing: false,
      summaries: <DailyActivitySummary>[
        DailyActivitySummary(
          athleteProfileId: 'athlete-a',
          localDate: '2026-08-02',
          timeZoneName: 'Asia/Shanghai',
          timeZoneOffsetMinutes: 480,
          steps: steps,
          stepGoal: 6000,
          activeEnergyKcal: 260,
          activeEnergyGoalKcal: 300,
          exerciseMinutes: 30,
          exerciseGoalMinutes: 30,
          standHours: 10,
          standGoalHours: 10,
          fieldSources: const <DailyActivityField, ActivityFieldSource>{
            DailyActivityField.steps: ActivityFieldSource.manualOverride,
          },
          syncedAt: DateTime.utc(2026, 8, 2),
        ),
      ],
      suggestedGoals: null,
      statusMessage: '已读取本机 Apple 健康数据。',
    );
  }
}
