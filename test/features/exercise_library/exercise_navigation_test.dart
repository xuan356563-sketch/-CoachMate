import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/core/widgets/trainmate_action_character.dart';
import 'package:trainflow_ai/data/models/body_region.dart';
import 'package:trainflow_ai/data/models/exercise.dart';
import 'package:trainflow_ai/data/seed/seed_exercises.dart';
import 'package:trainflow_ai/features/exercise_library/exercise_list_page.dart';

import '../../support/test_harness.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => router.go(AppRoutes.dashboard));

    await tester.pumpWidget(
      TestHarness().buildApp(const TrainFlowApp()),
    );
    router.go(AppRoutes.dashboard);
    await tester.pumpAndSettle();
  }

  String currentPath() => router.routeInformationProvider.value.uri.path;

  testWidgets('393×852 下展示 11 个部位筛选和每组 4 个动作预览', (tester) async {
    await pumpApp(tester);
    router.go(AppRoutes.exercises);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('exercises-showcase-header')),
      findsOneWidget,
    );
    expect(find.byType(ExerciseListPage), findsOneWidget);
    final Map<BodyRegion, List<Exercise>> grouped =
        groupExercisesByBodyRegion(seedExercises);
    expect(find.text('训练动作 · 共 ${seedExercises.length} 个'), findsOneWidget);
    expect(grouped, hasLength(BodyRegion.values.length));

    final MapEntry<BodyRegion, List<Exercise>> firstRegion =
        grouped.entries.first;
    await tester.scrollUntilVisible(
      find.text('${firstRegion.key.label} ${firstRegion.value.length}'),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final BodyRegion region in BodyRegion.values) {
      final String label = '${region.label} ${grouped[region]!.length}';
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == label,
        ),
        findsOneWidget,
        reason: '缺少部位筛选：$label',
      );
    }

    final List<Exercise> chestExercises = grouped[BodyRegion.chest]!;
    final Finder chestSection = find.text('胸 · ${chestExercises.length} 个');
    await tester.scrollUntilVisible(
      chestSection,
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final Exercise exercise in chestExercises.take(4)) {
      expect(find.text(exercise.name), findsWidgets);
    }
    expect(find.text(chestExercises[4].name), findsNothing);

    final Finder showAllChest = find.text('查看全部 ${chestExercises.length} 个胸动作');
    await tester.scrollUntilVisible(
      showAllChest,
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(showAllChest);
    await tester.pumpAndSettle();

    final Finder selectedChest = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics &&
          widget.properties.label == '胸 ${chestExercises.length}',
    );
    await tester.scrollUntilVisible(
      selectedChest,
      -360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(selectedChest).properties.selected, isTrue);
    await tester.scrollUntilVisible(
      find.text(chestExercises[4].name),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(chestExercises[4].name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('动作详情返回键具备中文语义且直接链接无历史时回动作库', (tester) async {
    await pumpApp(tester);

    for (final String exerciseId in <String>[
      'exercise-standing-calf-raise',
      'exercise-not-found',
    ]) {
      router.go(AppRoutes.exerciseDetail(exerciseId));
      await tester.pumpAndSettle();
      expect(currentPath(), AppRoutes.exerciseDetail(exerciseId));

      final Finder backButton = find.byKey(
        const ValueKey<String>('exercise-detail-back'),
      );
      expect(backButton, findsOneWidget);
      final Finder brandBackButton = find.descendant(
        of: backButton,
        matching: find.byKey(
          const ValueKey<String>('trainmate-back-button'),
        ),
      );
      expect(brandBackButton, findsOneWidget);
      expect(
        find.descendant(
          of: brandBackButton,
          matching: find.byType(TrainMateActionCharacter),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(backButton).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(backButton).height, greaterThanOrEqualTo(48));

      final Finder semanticBack = find.descendant(
        of: backButton,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == '返回',
        ),
      );
      expect(semanticBack, findsOneWidget);
      final Semantics semanticsWidget = tester.widget<Semantics>(semanticBack);
      expect(semanticsWidget.properties.button, isTrue);
      expect(semanticsWidget.properties.onTap, isNotNull);

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(currentPath(), AppRoutes.exercises);
      expect(find.byType(ExerciseListPage), findsOneWidget);
    }
  });

  testWidgets('动作库进入关联动作后逐级返回并保留筛选和滚动位置', (tester) async {
    await pumpApp(tester);
    router.go(AppRoutes.exercises);
    await tester.pumpAndSettle();

    final Map<BodyRegion, List<Exercise>> grouped =
        groupExercisesByBodyRegion(seedExercises);
    final String calfLabel = '小腿足踝 ${grouped[BodyRegion.calf]!.length}';
    await tester.scrollUntilVisible(
      find.text(calfLabel),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final Finder calfFilter = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics &&
          RegExp(r'^小腿足踝 \d+$').hasMatch(widget.properties.label ?? ''),
    );
    expect(calfFilter, findsOneWidget);
    await tester.tap(calfFilter);
    await tester.pumpAndSettle();

    final Finder scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('站姿提踵'),
      320,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final double listOffsetBeforeOpen =
        tester.state<ScrollableState>(scrollable).position.pixels;

    final Finder visibleStandingCalfRaise = find.text('站姿提踵').hitTestable();
    expect(visibleStandingCalfRaise, findsOneWidget);
    await tester.tap(visibleStandingCalfRaise);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('exercise-detail-back')),
      findsOneWidget,
    );
    expect(find.text('站姿提踵'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('坐姿小腿等长收缩'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final Finder visibleRelation = find.text('坐姿小腿等长收缩').hitTestable();
    expect(visibleRelation, findsOneWidget);
    await tester.tap(visibleRelation);
    await tester.pumpAndSettle();
    expect(find.text('坐姿小腿等长收缩'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('exercise-detail-back')),
    );
    await tester.pumpAndSettle();
    expect(find.text('动作调整'), findsOneWidget);

    final bool handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();

    expect(currentPath(), AppRoutes.exercises);
    final Finder restoredScrollable = find.byType(Scrollable).first;
    expect(
      tester.state<ScrollableState>(restoredScrollable).position.pixels,
      closeTo(listOffsetBeforeOpen, 1),
    );
    final Finder selectedCalfFilter = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics &&
          RegExp(r'^小腿足踝 \d+$').hasMatch(widget.properties.label ?? ''),
    );
    await tester.scrollUntilVisible(
      selectedCalfFilter,
      -320,
      scrollable: restoredScrollable,
    );
    expect(
      tester.widget<Semantics>(selectedCalfFilter).properties.selected,
      isTrue,
    );
  });

  testWidgets('动作检测打开安全提示后返回动作检测原页面', (tester) async {
    await pumpApp(tester);
    router.go(AppRoutes.motionCheck);
    await tester.pumpAndSettle();

    await tester.tap(find.text('纠错规则'));
    await tester.pumpAndSettle();
    final Finder safetyEntry =
        find.widgetWithText(TextButton, '查看动作安全提示').first;
    await tester.scrollUntilVisible(
      safetyEntry,
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final Finder visibleSafetyEntry = safetyEntry.hitTestable();
    expect(visibleSafetyEntry, findsOneWidget);
    await tester.tap(visibleSafetyEntry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('exercise-detail-back')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('exercise-detail-back')),
    );
    await tester.pumpAndSettle();

    expect(currentPath(), AppRoutes.motionCheck);
    expect(
      find.widgetWithText(TextButton, '查看动作安全提示').hitTestable(),
      findsWidgets,
    );
  });
}
