import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity_import/activity_import_page.dart';
import '../../features/ai_coach/ai_coach_page.dart';
import '../../features/data_center/data_center_page.dart';
import '../../features/dashboard/today_training_page.dart';
import '../../features/daily_adjustment/daily_adjustment_page.dart';
import '../../features/daily_check_in/daily_check_in_page.dart';
import '../../features/exercise_library/exercise_detail_page.dart';
import '../../features/exercise_library/exercise_list_page.dart';
import '../../features/knowledge_library/knowledge_library_page.dart';
import '../../features/meal_guide/meal_guide_page.dart';
import '../../features/motion_check/motion_check_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/race_prep/race_prep_page.dart';
import '../../features/rehab/rehab_page.dart';
import '../../features/reminders/training_reminder_page.dart';
import '../../features/self_use_acceptance/self_use_acceptance_page.dart';
import '../../features/starter_program/starter_graduation_page.dart';
import '../../features/starter_program/starter_program_page.dart';
import '../../features/training_plan/plan_detail_page.dart';
import '../../features/training_plan/plan_list_page.dart';
import '../../features/training_plan/workout_detail_page.dart';
import '../../features/user_insights/user_insight_page.dart';
import '../../features/weekly_report/weekly_report_page.dart';
import '../../features/workout_player/workout_player_page.dart';
import '../navigation/main_shell.dart';
import 'app_routes.dart';

final GoRouter router = GoRouter(
  initialLocation: AppRoutes.dashboard,
  routes: [
    GoRoute(
      path: '/',
      redirect: (BuildContext context, GoRouterState state) {
        return AppRoutes.dashboard;
      },
    ),
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) {
        return MainShell(child: child);
      },
      routes: [
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (BuildContext context, GoRouterState state) {
            return const TodayTrainingPage();
          },
        ),
        GoRoute(
          path: AppRoutes.dailyAdjustment,
          builder: (BuildContext context, GoRouterState state) {
            return const DailyAdjustmentPage();
          },
        ),
        GoRoute(
          path: AppRoutes.dailyCheckIn,
          builder: (BuildContext context, GoRouterState state) {
            return const DailyCheckInPage();
          },
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (BuildContext context, GoRouterState state) {
            return const OnboardingPage();
          },
        ),
        GoRoute(
          path: AppRoutes.dataCenter,
          builder: (BuildContext context, GoRouterState state) {
            return const DataCenterPage();
          },
        ),
        GoRoute(
          path: AppRoutes.activityImport,
          builder: (BuildContext context, GoRouterState state) {
            return const ActivityImportPage();
          },
        ),
        GoRoute(
          path: AppRoutes.reminders,
          builder: (BuildContext context, GoRouterState state) {
            return const TrainingReminderPage();
          },
        ),
        GoRoute(
          path: AppRoutes.plans,
          builder: (BuildContext context, GoRouterState state) {
            return const PlanListPage();
          },
        ),
        GoRoute(
          path: '${AppRoutes.plans}/:planId',
          builder: (BuildContext context, GoRouterState state) {
            return PlanDetailPage(planId: state.pathParameters['planId']!);
          },
        ),
        GoRoute(
          path: '${AppRoutes.plans}/:planId/workouts/:workoutDayId',
          builder: (BuildContext context, GoRouterState state) {
            return WorkoutDetailPage(
              planId: state.pathParameters['planId']!,
              workoutDayId: state.pathParameters['workoutDayId']!,
            );
          },
        ),
        GoRoute(
          path: AppRoutes.exercises,
          builder: (BuildContext context, GoRouterState state) {
            return const ExerciseListPage();
          },
        ),
        GoRoute(
          path: '${AppRoutes.exercises}/:exerciseId',
          builder: (BuildContext context, GoRouterState state) {
            return ExerciseDetailPage(
              exerciseId: state.pathParameters['exerciseId']!,
            );
          },
        ),
        GoRoute(
          path: AppRoutes.aiCoach,
          builder: (BuildContext context, GoRouterState state) {
            return const AiCoachPage();
          },
        ),
        GoRoute(
          path: AppRoutes.knowledge,
          builder: (BuildContext context, GoRouterState state) {
            return const KnowledgeLibraryPage();
          },
        ),
        GoRoute(
          path: AppRoutes.rehab,
          builder: (BuildContext context, GoRouterState state) {
            return const RehabPage();
          },
        ),
        GoRoute(
          path: AppRoutes.mealGuide,
          builder: (BuildContext context, GoRouterState state) {
            return const MealGuidePage();
          },
        ),
        GoRoute(
          path: AppRoutes.motionCheck,
          builder: (BuildContext context, GoRouterState state) {
            return const MotionCheckPage();
          },
        ),
        GoRoute(
          path: AppRoutes.races,
          builder: (BuildContext context, GoRouterState state) {
            return const RacePrepPage();
          },
        ),
        GoRoute(
          path: AppRoutes.starterProgram,
          builder: (BuildContext context, GoRouterState state) {
            return const StarterProgramPage();
          },
        ),
        GoRoute(
          path: AppRoutes.starterGraduation,
          builder: (BuildContext context, GoRouterState state) {
            return const StarterGraduationPage();
          },
        ),
        GoRoute(
          path: AppRoutes.workoutPlayer,
          builder: (BuildContext context, GoRouterState state) {
            return const WorkoutPlayerPage();
          },
        ),
        GoRoute(
          path: AppRoutes.weeklyReport,
          builder: (BuildContext context, GoRouterState state) {
            return const WeeklyReportPage();
          },
        ),
        GoRoute(
          path: AppRoutes.userInsights,
          builder: (BuildContext context, GoRouterState state) {
            return const UserInsightPage();
          },
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (BuildContext context, GoRouterState state) {
            return const ProfilePage();
          },
        ),
        GoRoute(
          path: AppRoutes.selfUseAcceptance,
          builder: (BuildContext context, GoRouterState state) {
            return const SelfUseAcceptancePage();
          },
        ),
      ],
    ),
  ],
);
