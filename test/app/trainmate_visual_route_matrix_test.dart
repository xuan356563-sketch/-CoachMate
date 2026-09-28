import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';

void main() {
  test('50 个 pageBuilder 目的页和能力管理 builder 均保留真实入口', () {
    final List<GoRoute> routes = <GoRoute>[];
    for (final RouteBase route in router.configuration.routes) {
      _collectRoutes(route, routes);
    }

    final List<GoRoute> productionRoutes = routes
        .where((GoRoute route) => route.path != AppRoutes.pilotValidation)
        .toList(growable: false);
    final List<String> productionPagePaths = productionRoutes
        .where((GoRoute route) => route.pageBuilder != null)
        .map((GoRoute route) => route.path)
        .toList(growable: false);

    expect(productionPagePaths, hasLength(50));
    expect(productionPagePaths.toSet(), hasLength(50));
    expect(productionPagePaths, isNot(contains(AppRoutes.pilotValidation)));
    expect(
      productionPagePaths,
      containsAll(<String>[
        AppRoutes.authLoading,
        AppRoutes.login,
        AppRoutes.terms,
        AppRoutes.privacy,
        AppRoutes.dashboard,
        AppRoutes.history,
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
    final GoRoute capabilities = productionRoutes.singleWhere(
      (GoRoute route) => route.path == AppRoutes.capabilities,
    );
    expect(capabilities.builder, isNotNull);
    expect(capabilities.pageBuilder, isNull);
  });
}

void _collectRoutes(RouteBase route, List<GoRoute> result) {
  if (route is GoRoute) result.add(route);
  for (final RouteBase child in route.routes) {
    _collectRoutes(child, result);
  }
}
