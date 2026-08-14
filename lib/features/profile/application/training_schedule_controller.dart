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
    final UserProfileState profileState =
        ref.watch(userProfileControllerProvider);
    final FourWeekPlanState generatedPlanState =
        ref.watch(fourWeekPlanControllerProvider);
    final TrainingScheduleRepository repository =
        ref.watch(trainingScheduleRepositoryProvider);
    final List<TrainingAvailabilitySlot> availability =
        repository.listAvailability();
    List<ScheduledWorkout> workouts = repository.listSchedule();
    if (availability.isNotEmpty) {
      final plan = profileState.isCompleted
          ? generatedPlanState.activePlan
          : InMemoryTrainingPlanRepository().listPlans().first;
      final List<ScheduledWorkout> rebuilt = _service.build(
        plan: plan,
        availability: availability,
        weeklyTrainingDays: profileState.profile.weeklyTrainingDays,
        now: ref.watch(trainingScheduleNowProvider),
      );
      if (!_sameSchedule(workouts, rebuilt)) {
        repository.saveSchedule(rebuilt);
        workouts = rebuilt;
      }
    }
    return TrainingScheduleState(
      availability: availability,
      workouts: workouts,
      statusMessage: availability.isEmpty ? '尚未设置可训练时间。' : '已读取训练日程。',
    );
  }

  void addSlot({
    required DateTime date,
    required int startMinute,
    required int endMinute,
    bool repeatWeekly = false,
  }) {
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
    _saveAndRebuild(_normalize(next), '已保存可训练时间并重新安排训练。');
  }

  void removeSlot(String id) {
    _saveAndRebuild(
      state.availability
          .where((TrainingAvailabilitySlot item) => item.id != id)
          .toList(),
      '已删除时间段并重新安排训练。',
    );
  }

  void _saveAndRebuild(
    List<TrainingAvailabilitySlot> availability,
    String message,
  ) {
    final repository = ref.read(trainingScheduleRepositoryProvider);
    repository.saveAvailability(availability);
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
    repository.saveSchedule(workouts);
    state = TrainingScheduleState(
      availability: availability,
      workouts: workouts,
      statusMessage: message,
    );
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

bool _sameSchedule(
  List<ScheduledWorkout> first,
  List<ScheduledWorkout> second,
) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index += 1) {
    final ScheduledWorkout left = first[index];
    final ScheduledWorkout right = second[index];
    final bool isLegacyL1Item = left.discipline == null ||
        left.primaryTargetKind == null ||
        left.targetMinutes == null;
    // 旧 JSON 的 L1 字段保持为空，避免静默补猜；新排期仍比较完整字段。
    // 用户真正修改可训练时间后会走 _saveAndRebuild，并保存新的完整排期。
    if (left.id != right.id ||
        left.workoutDayId != right.workoutDayId ||
        left.scheduledDate != right.scheduledDate ||
        left.startMinute != right.startMinute ||
        left.allocatedMinutes != right.allocatedMinutes ||
        left.period != right.period ||
        left.version != right.version ||
        (!isLegacyL1Item &&
            (left.discipline != right.discipline ||
                left.primaryTargetKind != right.primaryTargetKind ||
                left.targetMinutes != right.targetMinutes))) {
      return false;
    }
  }
  return true;
}

bool _isSameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
