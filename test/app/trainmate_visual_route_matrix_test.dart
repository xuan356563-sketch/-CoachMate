import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';

void main() {
  test('48 个生产目的页均保留真实 GoRouter 页面入口', () {
    final List<GoRoute> pages = <GoRoute>[];
    for (final RouteBase route in router.configuration.routes) {
      _collectPageRoutes(route, pages);
    }

    final List<String> productionPaths = pages
        .map((GoRoute route) => route.path)
        .where((String path) => path != AppRoutes.pilotValidation)
        .toList(growable: false);

    expect(productionPaths, hasLength(48));
    expect(productionPaths.toSet(), hasLength(48));
    expect(productionPaths, isNot(contains(AppRoutes.pilotValidation)));
    expect(
      productionPaths,
      containsAll(<String>[
        AppRoutes.authLoading,
        AppRoutes.login,
        AppRoutes.terms,
        AppRoutes.privacy,
        AppRoutes.dashboard,
        AppRoutes.plans,
        AppRoutes.companion,
        AppRoutes.companionArchive,
        AppRoutes.companionMemories,
        AppRoutes.aiCenter,
        AppRoutes.exercises,
        AppRoutes.profile,
        AppRoutes.workoutPlayer,
      ]),
    );
  });
}

void _collectPageRoutes(RouteBase route, List<GoRoute> result) {
  if (route is GoRoute && route.pageBuilder != null) {
    result.add(route);
  }
  for (final RouteBase child in route.routes) {
    _collectPageRoutes(child, result);
  }
}
