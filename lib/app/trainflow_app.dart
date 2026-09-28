import '../plugins/application/plugin_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:trainflow_ai/core/constants/app_brand.dart';
import 'package:trainflow_ai/core/theme/tdesign_theme.dart';
import 'package:trainflow_ai/features/auth/application/auth_controller.dart';
import 'package:trainflow_ai/features/auth/application/auth_route_refresh.dart';

import 'router/app_router.dart';

class TrainFlowApp extends ConsumerWidget {
  const TrainFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (AsyncValue<AuthState>? previous, AsyncValue<AuthState> next) {
        authRouteRefreshNotifier.refresh();
      },
    );
    ref.listen(
        pluginRuntimeProvider, (_, __) => authRouteRefreshNotifier.refresh());
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: AppBrand.displayName,
          debugShowCheckedModeBanner: false,
          theme: TDesignTheme.lightTheme,
          darkTheme: TDesignTheme.darkTheme,
          themeMode: ThemeMode.light,
          routerConfig: router,
          builder: (context, child) {
            return child!;
          },
        );
      },
    );
  }
}
