import '../../../plugins/application/feature_controller_binding.dart';
import '../../../plugins/application/feature_access.dart';
import '../../../plugins/application/plugin_runtime_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/training_schedule.dart';
import '../../../data/repositories/training_plan_repository.dart';
import '../../../data/repositories/training_schedule_repository.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/training_schedule_service.dart';
import '../../training_plan/application/four_week_plan_controller.dart';
import 'user_profile_controller.dart';

final trainingScheduleNowProvider =
    Provider<DateTime>((Ref ref) => DateTime.now());

final trainingScheduleRepositoryProvider = Provider<TrainingScheduleRepository>(
  (Ref ref) =>
      TrainingScheduleRepository(ref.watch(localStorageServiceProvider)),
);

final trainingScheduleControllerProvider =
    NotifierProvider<TrainingScheduleController, TrainingScheduleState>(
  TrainingScheduleController.new,
);

class TrainingScheduleState {
  final List<TrainingAvailabilitySlot> availability;
  final List<ScheduledWorkout> workouts;
  final String statusMessage;

  const TrainingScheduleState({
    required this.availability,
    required this.workouts,
    required this.statusMessage,
  });

  ScheduledWorkout? workoutFor(DateTime date) {
    for (final ScheduledWorkout workout in workouts) {
      if (_isSameDate(workout.scheduledDate, date)) return workout;
    }
    return null;
  }

  List<TrainingAvailabilitySlot> slotsFor(DateTime date) => availability
      .where((TrainingAvailabilitySlot item) => _isSameDate(item.date, date))
      .toList();
}

class TrainingScheduleController extends Notifier<TrainingScheduleState> {
  final TrainingScheduleService _service = TrainingScheduleService();

  @override
  TrainingScheduleState build() {
    bindFeatureController(ref, 'feature.training_plan', 'schedule', this);
    ref.watch(userProfileControllerProvider);
    ref.watch(fourWeekPlanControllerProvider);
    final TrainingScheduleRepository repository =
        ref.watch(trainingScheduleRepositoryProvider);
    final List<TrainingAvailabilitySlot> availability =
        repository.listAvailability();
    final List<ScheduledWorkout> workouts = repository.listSchedule();
    return TrainingScheduleState(
      availability: availability,
      workouts: workouts,
      statusMessage: availability.isEmpty ? '尚未设置可训练时间。' : '已读取训练日程。',
    );
  }

  Future<void> initializeSchedule() async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    final List<TrainingAvailabilitySlot> availability =
        ref.read(trainingScheduleRepositoryProvider).listAvailability();
    if (availability.isEmpty) return;
    await _saveAndRebuild(
      availability,
      '已读取训练日程。',
      operation: operation,
    );
  }

  Future<void> addSlot({
    required DateTime date,
    required int startMinute,
    required int endMinute,
    bool repeatWeekly = false,
  }) async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    if (startMinute < 0 ||
        endMinute > 24 * 60 ||
        endMinute - startMinute < 15) {
      state = TrainingScheduleState(
        availability: state.availability,
        workouts: state.workouts,
        statusMessage: '时间段至少需要 15 分钟，且不能跨越午夜。',
      );
      return;
    }
    final DateTime now = ref.read(trainingScheduleNowProvider);
    final List<TrainingAvailabilitySlot> next = List.of(state.availability);
    final int repetitions = repeatWeekly ? 12 : 1;
    for (int week = 0; week < repetitions; week += 1) {
      final DateTime target = DateTime(date.year, date.month, date.day)
          .add(Duration(days: week * 7));
      next.add(TrainingAvailabilitySlot(
        id: 'availability-${target.millisecondsSinceEpoch}-$startMinute',
        date: target,
        startMinute: startMinute,
        endMinute: endMinute,
        createdAt: now,
        updatedAt: now,
      ));
    }
    await _saveAndRebuild(
      _normalize(next),
      '已保存可训练时间并重新安排训练。',
      operation: operation,
    );
  }

  Future<void> removeSlot(String id) async {
    final FeatureOperation operation =
        ref.read(featureAccessProvider).beginOperation('feature.training_plan');
    await _saveAndRebuild(
      state.availability
          .where((TrainingAvailabilitySlot item) => item.id != id)
          .toList(),
      '已删除时间段并重新安排训练。',
      operation: operation,
    );
  }

  Future<void> _saveAndRebuild(
    List<TrainingAvailabilitySlot> availability,
    String message, {
    required FeatureOperation operation,
  }) async {
    final repository = ref.read(trainingScheduleRepositoryProvider);
    final UserProfileState profileState =
        ref.read(userProfileControllerProvider);
    final profile = profileState.profile;
    final plan = profileState.isCompleted
        ? ref.read(fourWeekPlanControllerProvider).activePlan
        : InMemoryTrainingPlanRepository().listPlans().first;
    final workouts = _service.build(
      plan: plan,
      availability: availability,
      weeklyTrainingDays: profile.weeklyTrainingDays,
      now: ref.read(trainingScheduleNowProvider),
    );
    await operation.commit(() async {
      repository.saveAvailability(availability);
      repository.saveSchedule(workouts);
      await ref.read(localStorageServiceProvider).flush();
      state = TrainingScheduleState(
        availability: availability,
        workouts: workouts,
        statusMessage: message,
      );
    });
  }

  List<TrainingAvailabilitySlot> _normalize(
    List<TrainingAvailabilitySlot> slots,
  ) {
    slots.sort((a, b) {
      final dateOrder = a.date.compareTo(b.date);
      return dateOrder == 0
          ? a.startMinute.compareTo(b.startMinute)
          : dateOrder;
    });
    final List<TrainingAvailabilitySlot> normalized =
        <TrainingAvailabilitySlot>[];
    for (final slot in slots) {
      final sameDay = normalized.isNotEmpty &&
          _isSameDate(normalized.last.date, slot.date) &&
          slot.startMinute <= normalized.last.endMinute;
      if (!sameDay) {
        if (normalized
                .where((item) => _isSameDate(item.date, slot.date))
                .length <
            3) {
          normalized.add(slot);
        }
        continue;
      }
      final previous = normalized.removeLast();
      normalized.add(TrainingAvailabilitySlot(
        id: previous.id,
        date: previous.date,
        startMinute: previous.startMinute,
        endMinute: slot.endMinute > previous.endMinute
            ? slot.endMinute
            : previous.endMinute,
        createdAt: previous.createdAt,
        updatedAt: slot.updatedAt,
      ));
    }
    return normalized;
  }
}

bool _isSameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
