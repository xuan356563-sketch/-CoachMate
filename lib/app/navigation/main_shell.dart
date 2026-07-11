import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_routes.dart';

class NavigationItem {
  final String path;
  final String label;
  final IconData icon;

  const NavigationItem({
    required this.path,
    required this.label,
    required this.icon,
  });
}

final List<NavigationItem> bottomNavItems = const [
  NavigationItem(
    path: AppRoutes.dashboard,
    label: '今日训练',
    icon: Icons.fitness_center,
  ),
  NavigationItem(
    path: AppRoutes.plans,
    label: '训练计划',
    icon: Icons.calendar_month,
  ),
  NavigationItem(
    path: AppRoutes.exercises,
    label: '动作库',
    icon: Icons.menu_book,
  ),
  NavigationItem(
    path: AppRoutes.profile,
    label: '我的',
    icon: Icons.person_outline,
  ),
];

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    final int currentIndex = _indexForLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (int index) {
          context.go(bottomNavItems[index].path);
        },
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE6F0FF),
        destinations: [
          for (final NavigationItem item in bottomNavItems)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.icon, color: const Color(0xFF276EF1)),
              label: item.label,
            ),
        ],
      ),
    );
  }

  int _indexForLocation(String location) {
    if (location.startsWith(AppRoutes.plans)) {
      return 1;
    }
    if (location.startsWith(AppRoutes.exercises)) {
      return 2;
    }
    if (location.startsWith(AppRoutes.profile)) {
      return 3;
    }
    return 0;
  }
}
