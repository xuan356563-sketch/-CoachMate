import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/training_schedule.dart';
import 'package:trainflow_ai/data/models/user_profile.dart';
import 'package:trainflow_ai/data/repositories/training_schedule_repository.dart';
import 'package:trainflow_ai/features/profile/application/training_schedule_controller.dart';
import 'package:trainflow_ai/features/profile/application/user_profile_controller.dart';
import 'package:trainflow_ai/services/local_storage_service.dart';

void main() {
  test('保存可训练时间后生成排期，并可从本地重新读取', () {
    final storage = InMemoryLocalStorageService();
    final now = DateTime(2026, 7, 13, 8);
    ProviderContainer createContainer() => ProviderContainer(overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          trainingScheduleNowProvider.overrideWithValue(now),
        ]);

    final first = createContainer();
    first.read(trainingScheduleControllerProvider.notifier).addSlot(
          date: now,
          startMinute: 12 * 60,
          endMinute: 12 * 60 + 35,
        );

    final state = first.read(trainingScheduleControllerProvider);
    expect(state.availability, hasLength(1));
    expect(state.workouts, isNotEmpty);
    expect(state.workouts.first.period, TrainingTimePeriod.midday);
    expect(state.workouts.first.version, ScheduledWorkoutVersion.compact);
    first.dispose();

    final second = createContainer();
    expect(second.read(trainingScheduleControllerProvider).availability,
        hasLength(1));
    expect(
        second.read(trainingScheduleControllerProvider).workouts, isNotEmpty);
    second.dispose();
  });

  test('重叠时间段会合并，同一天最多保留三个时间段', () {
    final storage = InMemoryLocalStorageService();
    final now = DateTime(2026, 7, 13, 8);
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      trainingScheduleNowProvider.overrideWithValue(now),
    ]);
    addTearDown(container.dispose);
    final controller =
        container.read(trainingScheduleControllerProvider.notifier);

    controller.addSlot(date: now, startMinute: 360, endMinute: 420);
    controller.addSlot(date: now, startMinute: 400, endMinute: 480);
    controller.addSlot(date: now, startMinute: 720, endMinute: 760);
    controller.addSlot(date: now, startMinute: 1020, endMinute: 1080);
    controller.addSlot(date: now, startMinute: 1260, endMinute: 1320);

    final slots =
        container.read(trainingScheduleControllerProvider).availability;
    expect(slots, hasLength(3));
    expect(slots.first.timeLabel, '06:00-08:00');
  });

  test('读取旧排期时不根据 allocatedMinutes 补猜主目标', () {
    final storage = InMemoryLocalStorageService();
    final now = DateTime(2026, 7, 13, 8);
    ProviderContainer createContainer() => ProviderContainer(overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          trainingScheduleNowProvider.overrideWithValue(now),
        ]);

    final ProviderContainer first = createContainer();
    first.read(trainingScheduleControllerProvider.notifier).addSlot(
          date: now,
          startMinute: 18 * 60,
          endMinute: 19 * 60,
        );
    final Map<String, dynamic> saved =
        storage.readJson(TrainingScheduleRepository.scheduleStorageKey)!;
    final List<Map<String, dynamic>> legacyWorkouts =
        (saved['workouts'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> item) {
      final Map<String, dynamic> legacy = Map<String, dynamic>.from(item);
      legacy.remove('discipline');
      legacy.remove('primaryTargetKind');
      legacy.remove('targetMinutes');
      return legacy;
    }).toList();
    storage.saveJson(TrainingScheduleRepository.scheduleStorageKey, {
      'schemaVersion': 1,
      'workouts': legacyWorkouts,
    });
    first.dispose();

    final ProviderContainer second = createContainer();
    final ScheduledWorkout legacy =
        second.read(trainingScheduleControllerProvider).workouts.first;
    expect(legacy.discipline, isNull);
    expect(legacy.primaryTargetKind, isNull);
    expect(legacy.targetMinutes, isNull);
    second.dispose();
  });

  test('确认主目标后，训练日程使用对应的个性化四周计划', () {
    final storage = InMemoryLocalStorageService();
    final now = DateTime(2026, 7, 13, 8);
    final container = ProviderContainer(overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      trainingScheduleNowProvider.overrideWithValue(now),
    ]);
    addTearDown(container.dispose);
    final UserProfile profile =
        container.read(userProfileControllerProvider).profile.copyWith(
      mainSports: const <MainSport>[MainSport.strength],
      weeklyTrainingDays: 3,
    );
    container.read(userProfileControllerProvider.notifier).save(profile);
    final TrainingScheduleController controller =
        container.read(trainingScheduleControllerProvider.notifier);

    for (final int dayOffset in const <int>[0, 2, 4]) {
      controller.addSlot(
        date: now.add(Duration(days: dayOffset)),
        startMinute: 18 * 60,
        endMinute: 19 * 60,
        repeatWeekly: true,
      );
    }

    final TrainingScheduleState state =
        container.read(trainingScheduleControllerProvider);
    expect(state.workouts, hasLength(12));
    expect(
      state.workouts.every(
        (ScheduledWorkout item) => item.workoutDayId.startsWith('generated-'),
      ),
      isTrue,
    );
  });
}
