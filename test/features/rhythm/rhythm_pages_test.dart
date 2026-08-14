import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/body_rhythm.dart';
import 'package:trainflow_ai/features/rhythm/application/body_rhythm_controller.dart';
import 'package:trainflow_ai/features/rhythm/progress_review_page.dart';
import 'package:trainflow_ai/features/rhythm/rhythm_detail_page.dart';

void main() {
  testWidgets('节奏详情显示状态年龄、速度、四项依据和医学免责声明', (
    WidgetTester tester,
  ) async {
    final BodyRhythmState seed = _seedState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyRhythmControllerProvider.overrideWith(
            () => _FakeBodyRhythmController(seed),
          ),
        ],
        child: const MaterialApp(home: RhythmDetailPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('31.7'), findsOneWidget);
    expect(find.text('1.1×'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('四项怎么影响速度'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    for (final RhythmFactor factor in RhythmFactor.values) {
      expect(find.text(factor.label), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('rhythm-medical-disclaimer')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('rhythm-medical-disclaimer')),
      findsOneWidget,
    );
    expect(find.textContaining('这不是医学年龄'), findsOneWidget);
  });

  testWidgets('未解锁复盘显示真实计数和缺口，不显示百分比', (
    WidgetTester tester,
  ) async {
    final BodyRhythmState seed = _seedState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyRhythmControllerProvider.overrideWith(
            () => _FakeBodyRhythmController(seed),
          ),
        ],
        child: const MaterialApp(home: ProgressReviewPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('15 天复盘正在积累证据'), findsOneWidget);
    expect(find.textContaining('还需记录 4 个饮食日'), findsOneWidget);
    expect(find.textContaining('饮食 3/7 天'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}

class _FakeBodyRhythmController extends BodyRhythmController {
  _FakeBodyRhythmController(this.seed);

  final BodyRhythmState seed;

  @override
  Future<BodyRhythmState> build() async => seed;
}

BodyRhythmState _seedState() {
  final DateTime now = DateTime(2026, 7, 27);
  final Map<RhythmFactor, RhythmFactorResult> factors =
      <RhythmFactor, RhythmFactorResult>{
    RhythmFactor.sleep: const RhythmFactorResult(
      factor: RhythmFactor.sleep,
      contribution: 0.03,
      isSufficient: true,
      summary: '近 30 天平均 6.8 小时 · 20 晚',
    ),
    RhythmFactor.activity: const RhythmFactorResult(
      factor: RhythmFactor.activity,
      contribution: 0.02,
      isSufficient: true,
      summary: '近 30 天平均 6277 步/天 · 20 天',
    ),
    RhythmFactor.training: const RhythmFactorResult(
      factor: RhythmFactor.training,
      contribution: 0,
      isSufficient: false,
      summary: '暂时没有可用训练记录',
    ),
    RhythmFactor.restingHeartRate: const RhythmFactorResult(
      factor: RhythmFactor.restingHeartRate,
      contribution: 0.05,
      isSufficient: true,
      summary: '近 30 天趋势 +4.0 BPM',
    ),
  };
  return BodyRhythmState(
    snapshot: RhythmSnapshot(
      id: 'rhythm:user:2026-07-27',
      athleteProfileId: 'user',
      weekStart: now,
      timeZoneName: 'Asia/Shanghai',
      utcOffsetMinutes: 480,
      speed: 1.1,
      actualAge: 29.7,
      stateAge: 31.7,
      factors: factors,
      configVersion: 'rhythm-v1.0.0',
      createdAt: now,
    ),
    reviewStatus: const ReviewUnlockStatus(
      isUnlocked: false,
      dietDays: 3,
      weightRecords: 2,
      weightSpanDays: 4,
      trainingDays: 1,
      gaps: <String>[
        '还需记录 4 个饮食日',
        '还需记录 2 次体重',
        '体重首末记录还需间隔至少 7 天',
      ],
    ),
    mealRecords: <MealRecord>[
      for (int day = 25; day <= 27; day++)
        MealRecord(
          id: 'meal-$day',
          athleteProfileId: 'user',
          localDate: DateTime(2026, 7, day),
          mealType: MealType.dinner,
          summary: '晚餐记录',
          createdAt: DateTime(2026, 7, day, 19),
        ),
    ],
    weightDates: <DateTime>[
      DateTime(2026, 7, 23),
      DateTime(2026, 7, 27),
    ],
    trainingDates: <DateTime>[DateTime(2026, 7, 26)],
    statusMessage: '本周身体节奏已建立。',
    canPersist: true,
  );
}
