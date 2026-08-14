import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:trainflow_ai/data/models/ai_artifact.dart';
import 'package:trainflow_ai/features/ai_center/ai_center_page.dart';
import 'package:trainflow_ai/features/ai_center/application/ai_artifact_controller.dart';

import '../../support/test_harness.dart';

class _StaticAiArtifactController extends AiArtifactController {
  @override
  AiArtifactState build() => const AiArtifactState(
        artifacts: <AiArtifact>[],
        isSyncing: false,
        isGenerating: false,
        activeCapability: null,
        healthDataProcessingConsented: false,
        statusMessage: 'AI 结果会先生成卡片，确认后才影响本地训练。',
      );

  @override
  Future<void> sync() async {}
}

class _RecoveryAiArtifactController extends AiArtifactController {
  @override
  AiArtifactState build() => AiArtifactState(
        artifacts: <AiArtifact>[
          AiArtifact(
            id: 'recovery-a',
            capability: AiCapability.recovery,
            artifactType: 'recovery_dashboard_v1',
            schemaVersion: 1,
            decision: AiArtifactDecision.pending,
            contextDigest: 'digest',
            payload: const <String, dynamic>{
              'readiness_score': 68,
              'recommended_action': '按可用时间安排轻量训练。',
              'factors': <String>['可用时间 30 分钟'],
              'today_tasks': <String>['完成计划内低强度课'],
              'red_flags': <String>[],
              'safety_note': '如有疼痛请停止训练并寻求专业帮助。',
            },
            warnings: const <String>[],
            provider: 'test',
            model: 'test',
            generatedAt: DateTime(2026, 7, 15),
          ),
        ],
        isSyncing: false,
        isGenerating: false,
        activeCapability: null,
        healthDataProcessingConsented: false,
        statusMessage: '测试恢复卡片。',
      );
}

class _MixedTrainerAiArtifactController extends AiArtifactController {
  @override
  AiArtifactState build() => AiArtifactState(
        artifacts: <AiArtifact>[
          AiArtifact(
            id: 'prescription-newer',
            capability: AiCapability.trainer,
            artifactType: 'training_prescription_v1',
            schemaVersion: 1,
            decision: AiArtifactDecision.accepted,
            contextDigest: 'digest-new',
            payload: const <String, dynamic>{},
            warnings: const <String>[],
            provider: 'test',
            model: 'test',
            generatedAt: DateTime(2026, 7, 17),
          ),
          AiArtifact(
            id: 'trainer-old',
            capability: AiCapability.trainer,
            artifactType: 'trainer_plan_v1',
            schemaVersion: 1,
            decision: AiArtifactDecision.accepted,
            contextDigest: 'digest-old',
            payload: const <String, dynamic>{
              'cycle_label': '旧版四周建议摘要',
              'weekly_structure': '每周三练，仅供查看。',
              'workout_cards': <Map<String, dynamic>>[],
              'safety_notes': <String>['不能直接激活'],
            },
            warnings: const <String>[],
            provider: 'test',
            model: 'test',
            generatedAt: DateTime(2026, 7, 16),
          ),
        ],
        isSyncing: false,
        isGenerating: false,
        activeCapability: null,
        healthDataProcessingConsented: false,
        statusMessage: '测试混合 Trainer 产物。',
      );

  @override
  Future<void> sync() async {}
}

void main() {
  testWidgets('AI 中心只保留训练、动作和恢复三项能力', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(
        ProviderScope(
          overrides: [
            aiArtifactControllerProvider.overrideWith(
              _StaticAiArtifactController.new,
            ),
          ],
          child: const MaterialApp(home: AiCenterPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ai-showcase-header')),
      findsOneWidget,
    );
    expect(find.text('对话'), findsNothing);
    expect(find.text('训练'), findsOneWidget);
    expect(find.text('动作'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('Skill 四周计划'), findsOneWidget);
    await tester.tap(find.text('训练'));
    await tester.pumpAndSettle();
    expect(find.text('生成四周训练计划'), findsOneWidget);
    expect(find.text('历史 AI Trainer 摘要'), findsOneWidget);
    expect(find.text('一句话生成训练计划'), findsNothing);
    expect(find.text('生成训练卡'), findsNothing);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('健康、疼痛、准备度和成长指标只在本机计算'), findsOneWidget);
    expect(find.text('允许发送去标识化健康摘要'), findsNothing);
    expect(find.text('视频'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('云端恢复卡明确标为非健康计划适配预览', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(
        ProviderScope(
          overrides: [
            aiArtifactControllerProvider.overrideWith(
              _RecoveryAiArtifactController.new,
            ),
          ],
          child: const MaterialApp(home: AiCenterPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(find.text('非健康计划适配预览 68 分'), findsOneWidget);
    expect(find.textContaining('不是身体恢复或生理测量'), findsOneWidget);
    expect(find.textContaining('恢复准备度'), findsNothing);
  });

  testWidgets('新处方不会遮住更早的旧版 Trainer 摘要', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestHarness().buildApp(
        ProviderScope(
          overrides: [
            aiArtifactControllerProvider.overrideWith(
              _MixedTrainerAiArtifactController.new,
            ),
          ],
          child: const MaterialApp(home: AiCenterPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('训练'));
    await tester.pumpAndSettle();
    expect(find.text('旧版四周建议摘要'), findsOneWidget);
    expect(find.text('每周三练，仅供查看。'), findsOneWidget);
    expect(find.text('确认采用'), findsNothing);
  });

  testWidgets('AI 中心不再承载聊天输入，伙伴页是唯一主聊天入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TestHarness().buildApp(
        ProviderScope(
          overrides: [
            aiArtifactControllerProvider.overrideWith(
              _StaticAiArtifactController.new,
            ),
          ],
          child: const MaterialApp(home: AiCenterPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('ai-chat-voice')), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('伙伴对话已统一到“伙伴”'), findsOneWidget);
  });
}
