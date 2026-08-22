import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/trainflow_tokens.dart';
import '../router/app_routes.dart';
import 'trainmate_bottom_navigation.dart'
    show NavigationItem, NavigationItemRole;
import 'trainmate_bottom_navigation_v2.dart';

/// 底部导航 v2 槽位顺序：训练计划 / 今日训练 / 中央球体（运动搭子）/ 动作库 / 我的。
final List<NavigationItem> bottomNavItems = const [
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

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    final int currentIndex = _indexForLocation(location);
    // 全 App 已收敛为浅色「暖灰底 + 深紫品牌」，状态栏统一使用深色图标。
    final SystemUiOverlayStyle systemUiStyle = SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: AppColors.transparent,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey<String>('main-shell-system-ui-style'),
      value: systemUiStyle,
      child: Scaffold(
        extendBody: true,
        backgroundColor: AppColors.primary,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: TrainFlowTokens.pageMaxWidth,
            ),
            child: child,
          ),
        ),
        bottomNavigationBar: TrainMateBottomNavigationV2(
          items: bottomNavItems,
          selectedIndex: currentIndex,
          surfaceColor: Colors.transparent,
          animationDuration: TrainFlowMotion.resolve(
            context,
            TrainFlowMotion.selection,
          ),
          onDestinationSelected: (int index) {
            context.go(bottomNavItems[index].path);
          },
        ),
      ),
    );
  }

  int _indexForLocation(String location) {
    if (location.startsWith(AppRoutes.plans) ||
        location.startsWith(AppRoutes.races) ||
        location.startsWith(AppRoutes.starterProgram) ||
        location.startsWith(AppRoutes.starterGraduation)) {
      return 0;
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
      return 1;
    }
    if (location.startsWith(AppRoutes.companion) ||
        location.startsWith(AppRoutes.pet)) {
      return 2;
    }
    if (location.startsWith(AppRoutes.exercises) ||
        location.startsWith(AppRoutes.motionCheck)) {
      return 3;
    }
    if (location.startsWith(AppRoutes.profile) ||
        location.startsWith(AppRoutes.rehab) ||
        location.startsWith(AppRoutes.dataCenter) ||
        location.startsWith(AppRoutes.activityImport) ||
        location.startsWith(AppRoutes.mealGuide) ||
        location.startsWith(AppRoutes.onboarding) ||
        location.startsWith(AppRoutes.weeklyReport) ||
        location.startsWith(AppRoutes.userInsights) ||
        location.startsWith(AppRoutes.selfUseAcceptance) ||
        location.startsWith(AppRoutes.pilotValidation)) {
      return 4;
    }
    return 1;
  }
}
