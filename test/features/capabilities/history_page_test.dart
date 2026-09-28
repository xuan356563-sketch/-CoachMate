import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/data/models/generated_training_plan.dart';
import 'package:trainflow_ai/data/models/growth_evidence.dart';
import 'package:trainflow_ai/data/models/training_log.dart';
import 'package:trainflow_ai/data/models/training_metrics.dart';
import 'package:trainflow_ai/data/models/training_plan.dart';
import 'package:trainflow_ai/data/models/weekly_report.dart';
import 'package:trainflow_ai/data/models/weekly_psych_check_in.dart';
import 'package:trainflow_ai/data/models/exercise_training_profile.dart';
import 'package:trainflow_ai/data/repositories/generated_training_plan_repository.dart';
import 'package:trainflow_ai/data/repositories/growth_evidence_repository.dart';
import 'package:trainflow_ai/data/repositories/training_log_repository.dart';
import 'package:trainflow_ai/data/repositories/training_metrics_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/data/repositories/weekly_report_repository.dart';
import 'package:trainflow_ai/features/capabilities/history_page.dart';
import 'package:trainflow_ai/features/growth/application/growth_evidence_controller.dart';
import 'package:trainflow_ai/features/growth/application/training_metrics_provider.dart';
import 'package:trainflow_ai/features/profile/application/health_sync_controller.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime.dart';
import 'package:trainflow_ai/plugins/application/plugin_runtime_provider.dart';
import 'package:trainflow_ai/plugins/assembly/built_in_distribution.dart';
import 'package:trainflow_ai/plugins/core/plugin_core.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  testWidgets('周报停用后完整回读保存时的依据、手动复盘和方向，不重算或写入', (tester) async {
    final report = _detailedWeeklyReport();
    final fixture = await _HistoryFixture.create(weeklyReport: report);
    final before = fixture.storage.readJson(PersistedWeeklyReportRepository.storageKey);
    await fixture.runtime.disable('feature.weekly_report');
    await tester.pumpWidget(fixture.app(const HistoryPage()));
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('history-weekly-${report.id}'));
    await _scrollTo(tester, card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('保存时的训练目标'), findsOneWidget);
    expect(find.text('保存时依据：窗口内 2 条记录，折算 0.50/3 次完成单位。'), findsOneWidget);
    expect(find.text('力量：实际记录 1 次，计划 0 次'), findsOneWidget);
    expect(find.text('训练动机：4/5'), findsOneWidget);
    expect(find.text('感知压力：未填写'), findsOneWidget);
    expect(find.text('恢复感：2/5'), findsOneWidget);
    expect(find.text('备注：合成历史备注'), findsOneWidget);
    expect(find.text('已保存方向：保存时的力量焦点'), findsOneWidget);
    expect(find.text('方向选择仅为复盘记录，不表示计划已调整。'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('weekly-psych-save')), findsNothing);
    expect(fixture.storage.writeCount, 0);
    expect(fixture.storage.readJson(PersistedWeeklyReportRepository.storageKey), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('旧周报缺少新增内容时保留原摘要，明确未记录而不补算', (tester) async {
    final fixture = await _HistoryFixture.create();
    await fixture.runtime.disable('feature.weekly_report');
    await tester.pumpWidget(fixture.app(const HistoryPage()));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('history-weekly-compatibility-report'));
    await _scrollTo(tester, card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('保持当前节奏'), findsOneWidget);
    expect(find.text('恢复正常'), findsOneWidget);
    expect(find.text('此报告未保存事实依据，不重新推断。'), findsOneWidget);
    expect(find.text('此报告未保存手动复盘。'), findsOneWidget);
    expect(find.text('状态依据未记录或不足，无法评估。'), findsOneWidget);
    expect(find.text('未保存下周方向选择。'), findsOneWidget);
    expect(fixture.storage.writeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('方向来源缺失时不默认选中首项，跳过评分仍显示未填写', (tester) async {
    final report = _detailedWeeklyReport().copyWith(
        selectedOptionId: 'missing-option', psychCheckIn: const WeeklyPsychCheckIn());
    final fixture = await _HistoryFixture.create(weeklyReport: report);
    await tester.pumpWidget(fixture.app(const HistoryPage()));
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('history-weekly-${report.id}'));
    await _scrollTo(tester, card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('原方向选择无法匹配保存的选项，未自动替换。'), findsOneWidget);
    expect(find.text('已保存方向：保存时的力量焦点'), findsNothing);
    expect(find.text('训练动机：未填写'), findsOneWidget);
    expect(find.text('感知压力：未填写'), findsOneWidget);
    expect(find.text('恢复感：未填写'), findsOneWidget);
    expect(fixture.storage.writeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('核心历史读取旧计划版本、日志和三类报告且不写存储', (WidgetTester tester) async {
    final _HistoryFixture fixture = await _HistoryFixture.create();
    final Map<String, dynamic>? planBefore = fixture.storage
        .readJson(GeneratedTrainingPlanRepository.versionsStorageKey);
    final Map<String, dynamic>? logsBefore =
        fixture.storage.readJson(PersistedTrainingLogRepository.storageKey);
    await tester.pumpWidget(fixture.app(const HistoryPage()));
    await tester.pumpAndSettle();

    expect(find.text('历史四周计划'), findsOneWidget);
    final Finder logCard =
        find.byKey(const ValueKey<String>('history-log-history-log'));
    await _scrollTo(tester, logCard);
    await tester.tap(logCard);
    await tester.pumpAndSettle();
    expect(find.text('备注：测试训练备注'), findsOneWidget);
    await _scrollTo(
        tester,
        find.byKey(
            const ValueKey<String>('history-weekly-compatibility-report')));
    expect(find.text('2026 第 36 周'), findsOneWidget);
    await _scrollTo(tester,
        find.byKey(const ValueKey<String>('history-growth-growth-report')));
    expect(find.textContaining('成长周报'), findsOneWidget);
    // 报告属于固定历史周；通过日期入口读取，不能依赖测试当天恰好在该周。
    await _scrollTo(tester, find.text('选择要查看的周/月'));
    await tester.tap(find.text('选择要查看的周/月'));
    await tester.pumpAndSettle();
    final localizations = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)));
    await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '09/04/2026');
    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(find.text('2026-09-04'), findsOneWidget);
    await _scrollTo(tester, find.text('周报修订 2'));
    expect(find.text('周报修订 2'), findsOneWidget);
    expect(fixture.storage.writeCount, 0);
    expect(
      fixture.storage
          .readJson(GeneratedTrainingPlanRepository.versionsStorageKey),
      planBefore,
    );
    expect(
      fixture.storage.readJson(PersistedTrainingLogRepository.storageKey),
      logsBefore,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('计划版本详情从真实版本仓储只读展开训练日', (WidgetTester tester) async {
    final _HistoryFixture fixture = await _HistoryFixture.create();
    await tester.pumpWidget(
      fixture.app(const HistoryPlanDetailPage(versionId: 'history-version')),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史四周计划'), findsOneWidget);
    expect(find.text('只读版本，不能从这里激活、回退或开始训练。'), findsOneWidget);
    final Finder firstWorkout = find.byKey(
      ValueKey<String>(
        'history-workout-${fixture.plan.workoutDays.first.id}',
      ),
    );
    await _scrollTo(tester, firstWorkout);
    expect(find.text(fixture.plan.workoutDays.first.title), findsOneWidget);
    expect(fixture.storage.writeCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('成长周报满30条时可加载第31条且全程不写存储', (WidgetTester tester) async {
    final _HistoryFixture fixture =
        await _HistoryFixture.create(growthReportCount: 31);
    final List<WeeklyGrowthReport> allReports =
        await fixture.growth.listWeeklyReports(
      athleteProfileId: 'history-athlete',
      limit: 100,
    );
    final WeeklyGrowthReport olderReport = allReports[30];
    await tester.pumpWidget(fixture.app(const HistoryPage()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey<String>('history-growth-${olderReport.id}')),
      findsNothing,
    );
    final Finder loadMore = find.byKey(
      const ValueKey<String>('history-growth-load-more'),
    );
    await _scrollTo(tester, loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(ValueKey<String>('history-growth-${olderReport.id}')),
    );

    expect(
      find.byKey(ValueKey<String>('history-growth-${olderReport.id}')),
      findsOneWidget,
    );
    expect(fixture.storage.writeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('成长周报翻页期间账号域变化会丢弃旧域迟到页', (WidgetTester tester) async {
    final _HistoryFixture fixture =
        await _HistoryFixture.create(growthReportCount: 31);
    final List<WeeklyGrowthReport> allReports =
        await fixture.growth.listWeeklyReports(
      athleteProfileId: 'history-athlete',
      limit: 100,
    );
    final _DelayedGrowthRepository delayed = _DelayedGrowthRepository(
      fixture.storage,
      firstPage: allReports.take(30).toList(),
    );
    await tester.pumpWidget(
      fixture.app(const HistoryPage(), growthOverride: delayed),
    );
    await tester.pumpAndSettle();
    final Finder loadMore = find.byKey(
      const ValueKey<String>('history-growth-load-more'),
    );
    await _scrollTo(tester, loadMore);
    await tester.tap(loadMore);
    await tester.pump();

    final Future<void> switchScope = fixture.runtime.changeAccountScope(
      replaceScope: () async {
        delayed.completeSecondPage(<WeeklyGrowthReport>[allReports[30]]);
      },
    );
    await switchScope;
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey<String>('history-growth-${allReports[30].id}')),
      findsNothing,
    );
    expect(find.textContaining('账户或数据域已变化'), findsOneWidget);
    expect(fixture.storage.writeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

WeeklyReport _detailedWeeklyReport() => WeeklyReport(
    id: 'detailed-weekly-report', weekLabel: '合成报告历史',
    generatedAt: DateTime(2026, 9, 16), completedWorkouts: 0,
    plannedWorkouts: 3, completionRate: 0.5 / 3,
    loadTrendLabel: '保存时趋势', decisionReview: '保存时决策',
    recoverySummary: '保存时恢复说明',
    highlights: const ['保存时亮点'], nextWeekFocus: const ['保存时重点'],
    goalSummary: '保存时的训练目标',
    realityObservation: '保存时依据：窗口内 2 条记录，折算 0.50/3 次完成单位。',
    options: const [WeeklyReportOption(id: 'strength-focus', label: '保存时的力量焦点')],
    reflectionQuestion: '保存时的复盘问题', selectedOptionId: 'strength-focus',
    psychCheckIn: const WeeklyPsychCheckIn(motivation: 4, recoveryFeel: 2, weekNote: '合成历史备注'),
    recoveryEvidenceAvailable: false,
    dimensionExposure: const [TrainingDimensionExposure(dimension: TrainingDimension.strength,
        plannedSessions: 0, completedSessions: 1)]);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

class _HistoryFixture {
  _HistoryFixture({
    required this.storage,
    required this.runtime,
    required this.metrics,
    required this.growth,
    required this.plan,
  });

  final _CountingStorage storage;
  final PluginRuntime runtime;
  final InMemoryTrainingMetricsRepository metrics;
  final PersistedGrowthEvidenceRepository growth;
  final TrainingPlan plan;

  static Future<_HistoryFixture> create({int growthReportCount = 1, WeeklyReport? weeklyReport}) async {
    final _CountingStorage storage = _CountingStorage();
    final plan = FourWeekPlanGenerator()
        .generate(
          profile: InMemoryUserProfileRepository.defaultProfile,
          startsOn: DateTime(2026, 8, 31),
        )
        .plan
        .copyWith(title: '历史四周计划');
    final GeneratedPlanVersion version = GeneratedPlanVersion(
      id: 'history-version',
      plan: plan,
      weekPhases: const <String>['baseline'],
      source: GeneratedPlanSource.localRules,
      createdAt: DateTime(2026, 8, 31),
      activatedAt: DateTime(2026, 8, 31),
      inputDigest: 'history',
      artifactId: null,
      skillRef: null,
      compilerVersion: 'history-test',
      auditSummary: const PlanAuditSummary(
        passCount: 1,
        warningCount: 0,
        failCount: 0,
        blockingReasons: <String>[],
      ),
    );
    storage.saveJson(
      GeneratedTrainingPlanRepository.versionsStorageKey,
      <String, dynamic>{
        'schemaVersion': 1,
        ...GeneratedTrainingPlanHistory(
          activeVersionId: version.id,
          versions: <GeneratedPlanVersion>[version],
          activationEvents: const <GeneratedPlanActivationEvent>[],
        ).toJson(),
      },
    );
    PersistedTrainingLogRepository(storage).saveLog(TrainingLog(
      id: 'history-log',
      workoutDayId: plan.workoutDays.first.id,
      date: DateTime(2026, 9, 1),
      completed: true,
      rpe: 6,
      fatigueLevel: 4,
      sleepQuality: 8,
      painNote: null,
      userNote: '测试训练备注',
      createdAt: DateTime(2026, 9, 1),
    ));
    PersistedWeeklyReportRepository(storage).saveReport(weeklyReport ?? WeeklyReport(
      id: 'compatibility-report',
      weekLabel: '2026 第 36 周',
      generatedAt: DateTime(2026, 9, 4),
      completedWorkouts: 3,
      plannedWorkouts: 4,
      completionRate: 0.75,
      loadTrendLabel: '稳定',
      decisionReview: '保持当前节奏',
      recoverySummary: '恢复正常',
      highlights: const <String>[],
      nextWeekFocus: const <String>[],
    ));
    final PersistedGrowthEvidenceRepository growth =
        PersistedGrowthEvidenceRepository(storage);
    for (int index = 0; index < growthReportCount; index += 1) {
      await growth.saveWeeklyReport(_growthReport(index));
    }
    final InMemoryTrainingMetricsRepository metrics =
        InMemoryTrainingMetricsRepository();
    await metrics.saveReportRevision(ReportRevision(
      id: 'weekly-revision',
      athleteProfileId: 'history-athlete',
      period: MetricPeriod.week,
      periodStart: DateTime(2026, 8, 31),
      revision: 2,
      generatedAt: DateTime(2026, 9, 4),
      metricIds: const <String>[],
      narrative: '结构化周报内容',
      algorithmVersion: 'v1',
    ));
    final PluginRuntime runtime = PluginRuntime(
      PluginRegistry(plugins: builtInDistribution()),
    );
    await runtime.initialize();
    storage.writeCount = 0;
    return _HistoryFixture(
      storage: storage,
      runtime: runtime,
      metrics: metrics,
      growth: growth,
      plan: plan,
    );
  }

  Widget app(
    Widget child, {
    GrowthEvidenceRepository? growthOverride,
  }) =>
      ProviderScope(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          pluginRuntimeProvider.overrideWith((Ref ref) => runtime),
          trainingMetricsRepositoryProvider.overrideWithValue(metrics),
          growthEvidenceRepositoryProvider
              .overrideWithValue(growthOverride ?? growth),
          healthSyncAthleteIdProvider.overrideWithValue('history-athlete'),
        ],
        child: MaterialApp(home: child),
      );
}

WeeklyGrowthReport _growthReport(int index) {
  final DateTime weekStartsOn =
      DateTime(2026, 8, 31).subtract(Duration(days: index * 7));
  return WeeklyGrowthReport(
    id: index == 0 ? 'growth-report' : 'growth-report-$index',
    athleteProfileId: 'history-athlete',
    weekKey: _dateKey(weekStartsOn),
    weekStartsOn: weekStartsOn,
    weekEndsOn: weekStartsOn.add(const Duration(days: 6)),
    generatedAt: weekStartsOn.add(const Duration(days: 4)),
    lockedAt: null,
    regeneratedAt: null,
    consecutiveTrainingDays: 3,
    runningDistanceKm: 12,
    strengthSessionCount: 2,
    completionRate: 0.75,
    trainingLoad: 240,
    growthIndex: 82,
    availableIndexDimensions: 3,
    recoverySummary: '成长恢复正常',
    evidenceEventIds: const <String>[],
    modelVersion: 1,
  );
}

String _dateKey(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _DelayedGrowthRepository extends PersistedGrowthEvidenceRepository {
  _DelayedGrowthRepository(
    super.storage, {
    required this.firstPage,
  });

  final List<WeeklyGrowthReport> firstPage;
  final Completer<List<WeeklyGrowthReport>> _secondPage =
      Completer<List<WeeklyGrowthReport>>();

  @override
  Future<List<WeeklyGrowthReport>> listWeeklyReports({
    required String athleteProfileId,
    int limit = 30,
    int offset = 0,
  }) {
    if (offset == 0) return Future<List<WeeklyGrowthReport>>.value(firstPage);
    return _secondPage.future;
  }

  void completeSecondPage(List<WeeklyGrowthReport> reports) {
    if (!_secondPage.isCompleted) _secondPage.complete(reports);
  }
}

class _CountingStorage extends InMemoryLocalStorageService {
  int writeCount = 0;

  @override
  void saveJson(String key, Map<String, dynamic> value) {
    writeCount++;
    super.saveJson(key, value);
  }

  @override
  void remove(String key) {
    writeCount++;
    super.remove(key);
  }
}
