import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../plugins/application/plugin_runtime_provider.dart';
import '../../plugins/application/plugin_routes.dart';
import '../../plugins/core/plugin_core.dart';
import '../../plugins/features/built_in_features.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/trainmate_visual_mode.dart';
import '../../core/theme/trainflow_tokens.dart';
import '../router/app_routes.dart';
import 'trainmate_bottom_navigation.dart'
    show NavigationItem, NavigationItemRole;
import 'trainmate_bottom_navigation_v2.dart';

/// 底部导航槽位顺序：训练计划 / 今日训练 / 运动搭子 / 动作库 / 我的。
const List<NavigationItem> _navigationVisuals = [
  NavigationItem(
    path: AppRoutes.plans,
    label: '训练计划',
    displayLabel: '计划',
    icon: Icons.calendar_month_outlined,
    role: NavigationItemRole.plan,
  ),
  NavigationItem(
    path: AppRoutes.dashboard,
    label: '今日训练',
    displayLabel: '今日',
    icon: Icons.insights_outlined,
    role: NavigationItemRole.today,
  ),
  NavigationItem(
    path: AppRoutes.companion,
    label: '运动搭子',
    displayLabel: '伙伴',
    icon: Icons.pets_outlined,
    role: NavigationItemRole.partner,
  ),
  NavigationItem(
    path: AppRoutes.exercises,
    label: '动作库',
    displayLabel: '动作库',
    icon: Icons.menu_book_outlined,
    role: NavigationItemRole.exercises,
  ),
  NavigationItem(
    path: AppRoutes.profile,
    label: '我的',
    displayLabel: '我的',
    icon: Icons.person_outline,
    role: NavigationItemRole.profile,
  ),
];

List<NavigationItem> navigationItemsFor(
    Iterable<FeatureContribution> contributions) {
  final entries = contributions.whereType<NavigationContribution>().toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return [
    for (final entry in entries)
      for (final visual in _navigationVisuals)
        if (visual.path == entry.routeId)
          NavigationItem(
              path: entry.routeId,
              label: visual.label,
              displayLabel: entry.label,
              icon: visual.icon,
              role: visual.role)
  ];
}

final List<NavigationItem> bottomNavItems = navigationItemsFor(
    [for (final feature in builtInFeatures) ...feature.contributions]);

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String location = GoRouterState.of(context).uri.toString();
    final runtime = ref.watch(pluginRuntimeProvider);
    final items = navigationItemsFor(runtime.contributions);
    final String? unavailable =
        disabledRouteOwner(runtime, Uri.parse(location).path);
    if (unavailable != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('${AppRoutes.capabilities}?feature=$unavailable');
        }
      });
    }
    final selectedRoute = _routeForLocation(location);
    final matchedIndex = items.indexWhere((item) => item.path == selectedRoute);
    final currentIndex = matchedIndex >= 0
        ? matchedIndex
        : items.indexWhere((item) => item.path == AppRoutes.dashboard);
    final bool immersive = _isImmersivePlayer(location);
    final TrainMatePageAccent? pageAccent = _accentForLocation(location);
    final SystemUiOverlayStyle systemUiStyle =
        (immersive ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: AppColors.transparent);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey<String>('main-shell-system-ui-style'),
      value: systemUiStyle,
      child: Scaffold(
        extendBody: !immersive,
        backgroundColor: TrainFlowTokens.showcaseActionSurface,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: TrainFlowTokens.pageMaxWidth,
            ),
            child: TrainMatePageStyleScope(
              accent: pageAccent,
              immersive: immersive,
              child: child,
            ),
          ),
        ),
        bottomNavigationBar: immersive
            ? null
            : TrainMateBottomNavigationV2(
                items: items,
                selectedIndex: currentIndex,
                surfaceColor: Colors.transparent,
                animationDuration: TrainFlowMotion.resolve(
                  context,
                  TrainFlowMotion.navigation,
                ),
                onDestinationSelected: (int index) {
                  context.go(items[index].path);
                },
              ),
      ),
    );
  }

  bool _isImmersivePlayer(String location) {
    return location.startsWith(AppRoutes.workoutPlayer) ||
        (location.endsWith('/session') &&
            (location.startsWith(AppRoutes.guidedWorkouts) ||
                location.startsWith(AppRoutes.exerciseCircuits)));
  }

  TrainMatePageAccent? _accentForLocation(String location) {
    if (location.startsWith(AppRoutes.weeklyReport) ||
        location.startsWith(AppRoutes.growthEvidence) ||
        location.startsWith(AppRoutes.progressReview) ||
        location.startsWith(AppRoutes.userInsights)) {
      return TrainMatePageAccent.profile;
    }
    if (location.startsWith(AppRoutes.plans) ||
        location.startsWith(AppRoutes.guidedWorkouts) ||
        location.startsWith(AppRoutes.races)) {
      return TrainMatePageAccent.plan;
    }
    if (location.startsWith(AppRoutes.dashboard) ||
        location.startsWith(AppRoutes.dailyAdjustment) ||
        location.startsWith(AppRoutes.dailyCheckIn) ||
        location.startsWith(AppRoutes.workoutPlayer) ||
        location.startsWith(AppRoutes.rhythmDetail)) {
      return TrainMatePageAccent.today;
    }
    if (location.startsWith(AppRoutes.companion)) {
      return TrainMatePageAccent.companion;
    }
    if (location.startsWith(AppRoutes.exercises) ||
        location.startsWith(AppRoutes.motionCheck)) {
      return TrainMatePageAccent.exercises;
    }
    if (location.startsWith(AppRoutes.profile) ||
        location.startsWith(AppRoutes.history)) {
      return TrainMatePageAccent.profile;
    }
    return null;
  }

  String _routeForLocation(String location) {
    if (location.startsWith(AppRoutes.plans) ||
        location.startsWith(AppRoutes.races) ||
        location.startsWith(AppRoutes.starterProgram) ||
        location.startsWith(AppRoutes.starterGraduation)) {
      return AppRoutes.plans;
    }
    if (location.startsWith(AppRoutes.dashboard) ||
        location.startsWith(AppRoutes.aiCenter) ||
        location.startsWith(AppRoutes.aiCoach) ||
        location.startsWith(AppRoutes.knowledge) ||
        location.startsWith(AppRoutes.dailyAdjustment) ||
        location.startsWith(AppRoutes.dailyCheckIn) ||
        location.startsWith(AppRoutes.workoutPlayer) ||
        location.startsWith(AppRoutes.growthEvidence) ||
        location.startsWith(AppRoutes.rhythmDetail) ||
        location.startsWith(AppRoutes.progressReview)) {
      return AppRoutes.dashboard;
    }
    if (location.startsWith(AppRoutes.companion) ||
        location.startsWith(AppRoutes.pet)) {
      return AppRoutes.companion;
    }
    if (location.startsWith(AppRoutes.exercises) ||
        location.startsWith(AppRoutes.motionCheck)) {
      return AppRoutes.exercises;
    }
    if (location.startsWith(AppRoutes.profile) ||
        location.startsWith(AppRoutes.history) ||
        location.startsWith(AppRoutes.rehab) ||
        location.startsWith(AppRoutes.dataCenter) ||
        location.startsWith(AppRoutes.activityImport) ||
        location.startsWith(AppRoutes.mealGuide) ||
        location.startsWith(AppRoutes.onboarding) ||
        location.startsWith(AppRoutes.weeklyReport) ||
        location.startsWith(AppRoutes.userInsights) ||
        location.startsWith(AppRoutes.selfUseAcceptance) ||
        location.startsWith(AppRoutes.pilotValidation)) {
      return AppRoutes.profile;
    }
    return AppRoutes.dashboard;
  }
}
