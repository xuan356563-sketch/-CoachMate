import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/features/ai_center/ai_center_page.dart';
import 'package:trainflow_ai/features/auth/presentation/auth_pages.dart';
import 'package:trainflow_ai/features/daily_check_in/daily_check_in_page.dart';
import 'package:trainflow_ai/features/dashboard/today_training_page.dart';
import 'package:trainflow_ai/features/exercise_library/exercise_detail_page.dart';
import 'package:trainflow_ai/features/exercise_library/exercise_list_page.dart';
import 'package:trainflow_ai/features/first_run_onboarding/presentation/first_run_pages.dart';
import 'package:trainflow_ai/features/pet/presentation/pet_home_page.dart';
import 'package:trainflow_ai/features/profile/profile_page.dart';
import 'package:trainflow_ai/features/training_plan/plan_list_page.dart';
import 'package:trainflow_ai/features/weekly_report/weekly_report_page.dart';
import 'package:trainflow_ai/features/workout_player/workout_player_page.dart';

import '../support/test_harness.dart';

void main() {
  final List<({String name, Widget page, bool authenticated})> cases =
      <({String name, Widget page, bool authenticated})>[
    (
      name: '01-today',
      page: const TodayTrainingPage(),
      authenticated: true,
    ),
    (
      name: '02-plans',
      page: const PlanListPage(),
      authenticated: true,
    ),
    (
      name: '03-pet',
      page: const PetHomePage(),
      authenticated: true,
    ),
    (
      name: '04-ai',
      page: const AiCenterPage(),
      authenticated: true,
    ),
    (
      name: '05-exercises',
      page: const ExerciseListPage(),
      authenticated: true,
    ),
    (
      name: '06-profile',
      page: const ProfilePage(),
      authenticated: true,
    ),
    (
      name: '07-login',
      page: const LoginPage(),
      authenticated: false,
    ),
    (
      name: '08-onboarding',
      page: const PersonalProfileWelcomePage(),
      authenticated: false,
    ),
    (
      name: '09-form',
      page: const DailyCheckInPage(),
      authenticated: true,
    ),
    (
      name: '10-detail',
      page: const ExerciseDetailPage(exerciseId: 'exercise-bodyweight-squat'),
      authenticated: true,
    ),
    (
      name: '11-report',
      page: const WeeklyReportPage(),
      authenticated: true,
    ),
    (
      name: '12-player',
      page: const WorkoutPlayerPage(),
      authenticated: true,
    ),
  ];

  for (final item in cases) {
    testWidgets('${item.name} 视觉基线', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TestHarness(authenticated: item.authenticated).buildApp(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: TDesignTheme.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(393, 852),
                disableAnimations: true,
              ),
              child: Scaffold(body: item.page),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('baselines/${item.name}.png'),
      );
    });
  }
}
