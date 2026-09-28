import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trainflow_ai/app/router/app_router.dart';
import 'package:trainflow_ai/app/router/app_routes.dart';
import 'package:trainflow_ai/app/trainflow_app.dart';
import 'package:trainflow_ai/data/models/pre_exercise_clearance.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/pre_exercise_clearance_repository.dart';
import 'package:trainflow_ai/data/repositories/user_profile_repository.dart';
import 'package:trainflow_ai/features/auth/data/authenticated_api_client.dart';
import 'package:trainflow_ai/features/training_plan/application/official_clearance_link_launcher.dart';
import 'package:trainflow_ai/features/training_plan/application/pre_exercise_clearance_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

import '../../support/test_harness.dart';

class _ClearanceRepository implements PreExerciseClearanceRepository {
  PreExerciseClearance value = PreExerciseClearance.recorded(
    status: PreExerciseClearanceStatus.selfCleared,
    currentInjuryOrRestriction: false,
    completedAt: DateTime(2026, 7, 17),
  );

  @override
  Future<void> clear() async {
    value = const PreExerciseClearance.notCompleted();
  }

  @override
  Future<PreExerciseClearance> read({
    required String accountId,
    required String installationId,
  }) async =>
      value;

  @override
  Future<void> save({
    required String accountId,
    required String installationId,
    required PreExerciseClearance clearance,
  }) async {
    value = clearance;
  }
}

class _FailingLinkLauncher implements OfficialClearanceLinkLauncher {
  bool wasCalled = false;

  @override
  Future<bool> open() async {
    wasCalled = true;
    return false;
  }
}

void main() {
  testWidgets('/plans/generate 优先匹配静态路由并展示隐私门槛', (tester) async {
    tester.view.physicalSize = const Size(393, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final InMemoryLocalStorageService storage = InMemoryLocalStorageService();
    PersistedUserProfileRepository(storage).saveProfile(
      InMemoryUserProfileRepository.defaultProfile.copyWith(
        age: 32,
        trainingExperienceLevel: TrainingExperienceLevel.intermediate,
        mainSports: const <MainSport>[MainSport.hyrox],
        weeklyTrainingDays: 7,
        injuryHistory: const <String>['历史记录，不代表当前伤病'],
      ),
    );
    final MockClient httpClient = MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/v1/ai/training-prescriptions/capabilities',
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'enabled': true,
          'contract_version': 1,
          'skills': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'training-plan-builder',
              'version': '1.0.0',
              'display_name': '训练计划生成器',
              'sports': <String>['hyrox'],
              'source_sha256': _digestA,
              'runtime_sha256': _digestB,
            },
          ],
        }),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final _FailingLinkLauncher linkLauncher = _FailingLinkLauncher();
    await tester.pumpWidget(
      TestHarness(storageService: storage).buildApp(
        ProviderScope(
          overrides: [
            httpClientProvider.overrideWithValue(httpClient),
            preExerciseClearanceRepositoryProvider.overrideWithValue(
              _ClearanceRepository(),
            ),
            preExerciseClearanceRealtimeClockProvider.overrideWithValue(
              () => DateTime(2026, 7, 17),
            ),
            officialClearanceLinkLauncherProvider.overrideWithValue(
              linkLauncher,
            ),
          ],
          child: const TrainFlowApp(),
        ),
      ),
    );
    router.go(AppRoutes.planGenerate);
    await tester.pumpAndSettle();
    addTearDown(() => router.go(AppRoutes.dashboard));

    expect(find.text('生成四周训练计划'), findsWidgets);
    expect(find.text('2. 官方运动前筛查'), findsOneWidget);
    expect(find.textContaining('练搭 CoachMate 不复制 PAR-Q+ 题目'), findsOneWidget);
    expect(find.textContaining('不发送姓名、年龄、身体数据'), findsOneWidget);
    expect(find.textContaining('即使可用 7 天，仍最多安排 6 练'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.text('打开 PAR-Q+ / ePARmed-X+ 官方页面'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        OutlinedButton,
        '打开 PAR-Q+ / ePARmed-X+ 官方页面',
      ),
    );
    await tester.pumpAndSettle();
    expect(linkLauncher.wasCalled, isTrue);

    await tester.scrollUntilVisible(
      find.text('生成四周计划预览'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('生成四周计划预览'), findsOneWidget);
  });
}

const String _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
