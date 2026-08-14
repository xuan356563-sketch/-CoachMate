import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/starter_program.dart';
import 'package:trainflow_ai/features/dashboard/training_mvp_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';
import 'package:trainflow_ai/services/starter_graduation_service.dart';

void main() {
  test('30 天引导的提醒、反馈与画像事件统一使用累计成长语义', () {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(
          InMemoryLocalStorageService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final TrainingMvpController controller =
        container.read(trainingMvpProvider.notifier);
    final String initialReminder = container
        .read(trainingMvpProvider)
        .trainingReminders
        .firstWhere((reminder) => reminder.id == 'starter-program')
        .reason;
    expect(initialReminder, contains('累计成长日 0 天'));
    _expectNoStreakSemantics(initialReminder);

    controller.useStarterRescueVersion();
    expect(
      container.read(trainingMvpProvider).starterProgramStatusMessage,
      '已切换 5 分钟补救版，完成后计入累计成长日。',
    );

    controller.postponeStarterProgramDay();
    expect(
      container.read(trainingMvpProvider).starterProgramStatusMessage,
      '计划已顺延：今天仍保留当前任务，完成后计入累计成长日。',
    );

    controller.completeStarterProgramDay(StarterProgramFeedback.tooTired);
    final TrainingMvpState completedState = container.read(trainingMvpProvider);
    expect(
      completedState.starterProgramStatusMessage,
      '已记录“太累了”：明天不加量，恢复优先。',
    );
    final String progressEvent = completedState.profileEvents
        .firstWhere((event) => event.id == 'event-starter-1')
        .detail;
    expect(progressEvent, '已累计完成 1 天。');
    _expectNoStreakSemantics(progressEvent);
  });

  test('毕业报告把兼容计数解释为累计完成天数', () {
    final report = StarterGraduationService().buildReport(
      goal: StarterProgramGoal.habit,
      starterProgramStreak: 8,
      starterProgramDayIndex: 9,
      starterProgramStatusMessage: '按当前节奏推进。',
      bodyMetrics: const [],
      logs: const [],
      readinessScore: 72,
      readinessLabel: '可训练',
      trainingStatusLabel: '正常',
    );

    expect(report.completedDays, 8);
    expect(report.subjectiveTrendLabel, '执行积累');
    expect(report.subjectiveTrendDetail, contains('已累计完成 8 天'));
    _expectNoStreakSemantics(report.subjectiveTrendDetail);
  });
}

void _expectNoStreakSemantics(String text) {
  expect(
    text,
    isNot(
      matches(
        RegExp(r'连续打卡|连续完成|连击|断签|漏练不惩罚|保住连续性'),
      ),
    ),
  );
}
