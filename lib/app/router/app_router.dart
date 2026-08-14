import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/trainflow_tokens.dart';
import '../../features/activity_import/activity_import_page.dart';
import '../../features/ai_center/ai_center_page.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_route_refresh.dart';
import '../../features/auth/presentation/auth_pages.dart';
import '../../features/companion/presentation/companion_archive_page.dart';
import '../../features/companion/presentation/companion_feed_page.dart';
import '../../features/companion/presentation/coach_memory_page.dart';
import '../../features/data_center/data_center_page.dart';
import '../../features/data_rights/data_rights_page.dart';
import '../../features/dashboard/today_training_page.dart';
import '../../features/daily_adjustment/daily_adjustment_page.dart';
import '../../features/daily_check_in/daily_check_in_page.dart';
import '../../features/exercise_library/exercise_detail_page.dart';
import '../../features/exercise_library/exercise_list_page.dart';
import '../../features/first_run_onboarding/application/first_run_onboarding_controller.dart';
import '../../features/first_run_onboarding/domain/first_run_models.dart';
import '../../features/first_run_onboarding/presentation/first_run_pages.dart';
import '../../features/growth/growth_evidence_page.dart';
import '../../features/guided_workout/presentation/guided_workout_pages.dart';
import '../../features/guided_workout/presentation/guided_workout_player_page.dart';
import '../../features/knowledge_library/knowledge_library_page.dart';
import '../../features/knowledge_library/knowledge_citation_detail_page.dart';
import '../../features/meal_guide/meal_guide_page.dart';
import '../../features/motion_check/motion_check_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/pilot_validation/pilot_validation_page.dart';
import '../../features/pet/presentation/pet_data_settings_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/race_prep/race_prep_page.dart';
import '../../features/rehab/rehab_page.dart';
import '../../features/rhythm/progress_review_page.dart';
import '../../features/rhythm/rhythm_detail_page.dart';
import '../../features/self_use_acceptance/self_use_acceptance_page.dart';
import '../../features/starter_program/starter_graduation_page.dart';
import '../../features/starter_program/starter_program_page.dart';
import '../../features/training_plan/plan_detail_page.dart';
import '../../features/training_plan/plan_generation_page.dart';
import '../../features/training_plan/plan_list_page.dart';
import '../../features/training_plan/workout_detail_page.dart';
import '../../features/user_insights/user_insight_page.dart';
import '../../features/weekly_report/weekly_report_page.dart';
import '../../features/workout_player/workout_player_page.dart';
import '../navigation/main_shell.dart';
import 'app_routes.dart';

final GoRouter router = GoRouter(
  initialLocation: AppRoutes.authLoading,
  refreshListenable: authRouteRefreshNotifier,
  redirect: (BuildContext context, GoRouterState state) {
    final String location = state.matchedLocation;
    final bool isPublic =
        location == AppRoutes.terms || location == AppRoutes.privacy;
    if (isPublic) {
      return null;
    }

    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final AsyncValue<AuthState> auth = container.read(authControllerProvider);
    final AsyncValue<FirstRunDraft> onboarding = container.read(
      firstRunOnboardingControllerProvider,
    );
    if (auth is AsyncLoading<AuthState>) {
      return location == AppRoutes.authLoading ? null : AppRoutes.authLoading;
    }
    if (auth case AsyncData<AuthState>(:final value)) {
      if (value.status == AuthStatus.accountConflict) {
        return location == AppRoutes.accountSwitch
            ? null
            : AppRoutes.accountSwitch;
      }
      if (value.isAuthenticated) {
        if (firstRunOnboardingV2Enabled) {
          final FirstRunDraft? draft = onboarding.value;
          if (draft != null) {
            if (draft.stage == OnboardingStage.login ||
                draft.stage == OnboardingStage.cloudConsent) {
              return location == AppRoutes.welcomeCloudConsent
                  ? null
                  : AppRoutes.welcomeCloudConsent;
            }
            if (draft.stage == OnboardingStage.membership) {
              return location == AppRoutes.welcomeMembership
                  ? null
                  : AppRoutes.welcomeMembership;
            }
          }
        }
        if (location == AppRoutes.login ||
            location == AppRoutes.authLoading ||
            location == AppRoutes.accountSwitch ||
            location.startsWith('/welcome/')) {
          return AppRoutes.companion;
        }
        return null;
      }
    }
    if (firstRunOnboardingV2Enabled) {
      if (onboarding is AsyncLoading<FirstRunDraft>) {
        return location == AppRoutes.authLoading ? null : AppRoutes.authLoading;
      }
      if (onboarding case AsyncData<FirstRunDraft>(value: final draft)) {
        final String target = switch (draft.stage) {
          OnboardingStage.personal => AppRoutes.welcomeProfile,
          OnboardingStage.training => AppRoutes.welcomeTraining,
          _ => AppRoutes.login,
        };
        return location == target ? null : target;
      }
    }
    return location == AppRoutes.login ? null : AppRoutes.login;
  },
  routes: [
    GoRoute(
      path: AppRoutes.authLoading,
      pageBuilder: _page(
        (state) => const AuthLoadingPage(),
        transition: TrainMateRouteTransition.onboarding,
      ),
    ),
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: _page(
        (state) => const LoginPage(),
        transition: TrainMateRouteTransition.onboarding,
      ),
    ),
    GoRoute(
      path: AppRoutes.terms,
      pageBuilder: _page((state) => const TermsPage()),
    ),
    GoRoute(
      path: AppRoutes.privacy,
      pageBuilder: _page((state) => const PrivacyPage()),
    ),
    GoRoute(
      path: AppRoutes.accountSwitch,
      pageBuilder: _page(
        (state) => const AccountSwitchPage(),
        transition: TrainMateRouteTransition.onboarding,
      ),
    ),
    GoRoute(
      path: AppRoutes.welcomeProfile,
      pageBuilder: _page(
        (state) => const PersonalProfileWelcomePage(),
        transition: TrainMateRouteTransition.onboarding,
      ),
    ),
    GoRoute(
      path: AppRoutes.welcomeTraining,
      pageBuilder: _page(
        (state) => const TrainingBaselineWelcomePage(),
        transition: TrainMateRouteTransition.onboarding,
      ),
    ),
    GoRoute(
      path: AppRoutes.welcomeCloudConsent,
      pageBuilder: _page(
        (state) => const HealthCloudConsentPage(),
        transition: TrainMateRouteTransition.onboarding,
      ),
    ),
    GoRoute(
      path: AppRoutes.welcomeMembership,
      pageBuilder: _page(
        (state) => const MembershipWelcomePage(),
        transition: TrainMateRouteTransition.onboarding,
      ),
    ),
    GoRoute(
      path: '/',
      redirect: (BuildContext context, GoRouterState state) {
        return AppRoutes.companion;
      },
    ),
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) {
        return MainShell(child: child);
      },
      routes: [
        GoRoute(
          path: AppRoutes.dashboard,
          pageBuilder: _page(
            (state) => const TodayTrainingPage(),
            transition: TrainMateRouteTransition.tabFade,
          ),
        ),
        GoRoute(
          path: AppRoutes.dailyAdjustment,
          pageBuilder: _page((state) => const DailyAdjustmentPage()),
        ),
        GoRoute(
          path: AppRoutes.dailyCheckIn,
          pageBuilder: _page((state) => const DailyCheckInPage()),
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          pageBuilder: _page((state) => const OnboardingPage()),
        ),
        GoRoute(
          path: AppRoutes.dataCenter,
          pageBuilder: _page((state) => const DataCenterPage()),
        ),
        GoRoute(
          path: AppRoutes.dataRights,
          pageBuilder: _page((state) => const DataRightsPage()),
        ),
        GoRoute(
          path: AppRoutes.activityImport,
          pageBuilder: _page((state) => const ActivityImportPage()),
        ),
        GoRoute(
          path: AppRoutes.reminders,
          redirect: (BuildContext context, GoRouterState state) =>
              AppRoutes.dailyCheckIn,
        ),
        GoRoute(
          path: AppRoutes.plans,
          pageBuilder: _page(
            (state) => const PlanListPage(),
            transition: TrainMateRouteTransition.tabFade,
          ),
        ),
        // 静态生成路由必须位于 :planId 之前，避免把 generate 当作计划 ID。
        GoRoute(
          path: AppRoutes.planGenerate,
          pageBuilder: _page((state) => const PlanGenerationPage()),
        ),
        GoRoute(
          path: AppRoutes.guidedWorkouts,
          pageBuilder: _page((state) => const GuidedWorkoutCatalogPage()),
        ),
        GoRoute(
          path: '${AppRoutes.guidedWorkouts}/:courseId/session',
          pageBuilder: _page(
            (state) => GuidedWorkoutPlayerPage(
              courseId: state.pathParameters['courseId']!,
            ),
            transition: TrainMateRouteTransition.immersive,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.guidedWorkouts}/:courseId',
          pageBuilder: _page(
            (state) => GuidedWorkoutCourseDetailPage(
              courseId: state.pathParameters['courseId']!,
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.plans}/:planId',
          pageBuilder: _page(
            (state) => PlanDetailPage(
              planId: state.pathParameters['planId']!,
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.plans}/:planId/workouts/:workoutDayId',
          pageBuilder: _page(
            (state) => WorkoutDetailPage(
              planId: state.pathParameters['planId']!,
              workoutDayId: state.pathParameters['workoutDayId']!,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.companion,
          pageBuilder: _page(
            (state) => CompanionFeedPage(
              initialMessageId: state.uri.queryParameters['messageId'],
            ),
            transition: TrainMateRouteTransition.tabFade,
          ),
        ),
        GoRoute(
          path: AppRoutes.companionArchive,
          pageBuilder: _page((state) => const CompanionArchivePage()),
        ),
        GoRoute(
          path: AppRoutes.companionMemories,
          pageBuilder: _page((state) => const CoachMemoryPage()),
        ),
        GoRoute(
          path: AppRoutes.pet,
          redirect: (BuildContext context, GoRouterState state) =>
              AppRoutes.companion,
        ),
        GoRoute(
          path: AppRoutes.petData,
          pageBuilder: _page((state) => const PetDataSettingsPage()),
        ),
        GoRoute(
          path: AppRoutes.exercises,
          pageBuilder: _page(
            (state) => const ExerciseListPage(),
            transition: TrainMateRouteTransition.tabFade,
          ),
        ),
        // 静态循环路由必须位于 :exerciseId 之前，避免被识别为动作详情。
        GoRoute(
          path: '${AppRoutes.exerciseCircuits}/:courseId/session',
          pageBuilder: _page(
            (state) => GuidedWorkoutPlayerPage(
              courseId: state.pathParameters['courseId']!,
              selectedRounds:
                  int.tryParse(state.uri.queryParameters['rounds'] ?? ''),
              fallbackRoute: AppRoutes.exerciseCircuitDetail(
                state.pathParameters['courseId']!,
              ),
            ),
            transition: TrainMateRouteTransition.immersive,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.exerciseCircuits}/:courseId',
          pageBuilder: _page(
            (state) => FunctionalCircuitDetailPage(
              courseId: state.pathParameters['courseId']!,
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.exercises}/:exerciseId',
          pageBuilder: _page(
            (state) => ExerciseDetailPage(
              exerciseId: state.pathParameters['exerciseId']!,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.aiCenter,
          redirect: (BuildContext context, GoRouterState state) =>
              state.uri.queryParameters['section'] == 'chat'
                  ? AppRoutes.companion
                  : null,
          pageBuilder: _page(
            (state) => const AiCenterPage(),
            transition: TrainMateRouteTransition.tabFade,
          ),
        ),
        GoRoute(
          path: AppRoutes.aiCoach,
          redirect: (BuildContext context, GoRouterState state) =>
              AppRoutes.companion,
        ),
        GoRoute(
          path: AppRoutes.knowledge,
          pageBuilder: _page((state) => const KnowledgeLibraryPage()),
        ),
        GoRoute(
          path: '${AppRoutes.knowledge}/items/:itemId',
          pageBuilder: _page(
            (state) => KnowledgeCitationDetailPage(
              itemId: state.pathParameters['itemId']!,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.rehab,
          pageBuilder: _page((state) => const RehabPage()),
        ),
        GoRoute(
          path: AppRoutes.mealGuide,
          pageBuilder: _page((state) => const MealGuidePage()),
        ),
        GoRoute(
          path: AppRoutes.motionCheck,
          pageBuilder: _page((state) => const MotionCheckPage()),
        ),
        GoRoute(
          path: AppRoutes.races,
          pageBuilder: _page((state) => const RacePrepPage()),
        ),
        GoRoute(
          path: AppRoutes.starterProgram,
          pageBuilder: _page((state) => const StarterProgramPage()),
        ),
        GoRoute(
          path: AppRoutes.starterGraduation,
          pageBuilder: _page((state) => const StarterGraduationPage()),
        ),
        GoRoute(
          path: AppRoutes.workoutPlayer,
          pageBuilder: _page(
            (state) => const WorkoutPlayerPage(),
            transition: TrainMateRouteTransition.immersive,
          ),
        ),
        GoRoute(
          path: AppRoutes.weeklyReport,
          pageBuilder: _page((state) => const WeeklyReportPage()),
        ),
        GoRoute(
          path: AppRoutes.growthEvidence,
          pageBuilder: _page((state) => const GrowthEvidencePage()),
        ),
        GoRoute(
          path: AppRoutes.rhythmDetail,
          pageBuilder: _page((state) => const RhythmDetailPage()),
        ),
        GoRoute(
          path: AppRoutes.progressReview,
          pageBuilder: _page((state) => const ProgressReviewPage()),
        ),
        GoRoute(
          path: AppRoutes.userInsights,
          pageBuilder: _page((state) => const UserInsightPage()),
        ),
        GoRoute(
          path: AppRoutes.profile,
          pageBuilder: _page(
            (state) => const ProfilePage(),
            transition: TrainMateRouteTransition.tabFade,
          ),
        ),
        GoRoute(
          path: AppRoutes.selfUseAcceptance,
          pageBuilder: _page((state) => const SelfUseAcceptancePage()),
        ),
        GoRoute(
          path: AppRoutes.pilotValidation,
          redirect: (BuildContext context, GoRouterState state) {
            final ProviderContainer container = ProviderScope.containerOf(
              context,
              listen: false,
            );
            final bool enabled = container.read(localPreviewEnabledProvider);
            final AsyncValue<AuthState> auth =
                container.read(authControllerProvider);
            final bool isLocal = switch (auth) {
              AsyncData<AuthState>(:final value) => value.isLocalPreview,
              _ => false,
            };
            return enabled || isLocal ? null : AppRoutes.dashboard;
          },
          pageBuilder: _page((state) => const PilotValidationPage()),
        ),
      ],
    ),
  ],
);

enum TrainMateRouteTransition { tabFade, drillIn, onboarding, immersive }

GoRouterPageBuilder _page(
  Widget Function(GoRouterState state) builder, {
  TrainMateRouteTransition transition = TrainMateRouteTransition.drillIn,
}) {
  return (BuildContext context, GoRouterState state) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: builder(state),
      transitionDuration: TrainFlowMotion.route,
      reverseTransitionDuration: TrainFlowMotion.route,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (!TrainFlowMotion.isEnabled(context)) {
          return child;
        }
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return switch (transition) {
          TrainMateRouteTransition.tabFade => FadeTransition(
              opacity: curved,
              child: child,
            ),
          TrainMateRouteTransition.drillIn => FadeTransition(
              opacity: curved,
              child: AnimatedBuilder(
                animation: curved,
                child: child,
                builder: (context, transitionChild) => Transform.translate(
                  offset: Offset(16 * (1 - curved.value), 0),
                  child: transitionChild,
                ),
              ),
            ),
          TrainMateRouteTransition.onboarding => FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
                child: child,
              ),
            ),
          TrainMateRouteTransition.immersive => FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                child: child,
              ),
            ),
        };
      },
    );
  };
}
