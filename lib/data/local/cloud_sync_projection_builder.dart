import 'dart:convert';

import '../models/cloud_sync.dart';

class CloudSyncProjectionBuilder {
  const CloudSyncProjectionBuilder._();

  static const String _profileKey = 'trainflow.user_profile.v1';
  static const String _availabilityKey = 'trainflow.training_availability.v1';
  static const String _planKey = 'trainflow.generated_training_plan.v1';
  static const String _scheduleKey = 'trainflow.training_schedule.v1';
  static const String _logsKey = 'trainflow.training_logs.v1';
  static const String _settingsKey = 'trainflow.reminder_settings.v1';

  static List<CloudSyncMutation> build({
    required String changedKey,
    required Map<String, Map<String, dynamic>> previousDocuments,
    required Map<String, Map<String, dynamic>> currentDocuments,
  }) {
    try {
      return switch (changedKey) {
        _profileKey ||
        _availabilityKey =>
          _trainingPreferences(currentDocuments),
        _planKey => _planVersion(currentDocuments),
        _scheduleKey => _scheduledWorkouts(currentDocuments),
        _logsKey => _completionSummaries(
            previousDocuments,
            currentDocuments,
          ),
        _settingsKey => _appSettings(currentDocuments),
        _ => const <CloudSyncMutation>[],
      };
    } on FormatException {
      return const <CloudSyncMutation>[];
    } on TypeError {
      return const <CloudSyncMutation>[];
    }
  }

  static List<CloudSyncMutation> _trainingPreferences(
    Map<String, Map<String, dynamic>> documents,
  ) {
    final Map<String, dynamic>? profile =
        _map(documents[_profileKey]?['profile']);
    final List<Map<String, dynamic>> slots =
        _maps(documents[_availabilityKey]?['slots']);
    if (profile == null || slots.isEmpty) {
      return const <CloudSyncMutation>[];
    }
    final String goal = _nonEmpty(profile['trainingGoal']) ?? '';
    final List<String> sports = _strings(profile['mainSports']);
    final String experience =
        _nonEmpty(profile['trainingExperienceLevel']) ?? 'unknown';
    final String equipment =
        _nonEmpty(profile['equipmentAccessType']) ?? 'unknown';
    final List<int> weekdays = slots
        .map((Map<String, dynamic> slot) {
          return DateTime.tryParse(slot['date'] as String? ?? '')?.weekday;
        })
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    if (goal.isEmpty || sports.isEmpty || weekdays.isEmpty) {
      return const <CloudSyncMutation>[];
    }
    return <CloudSyncMutation>[
      CloudSyncMutation.trainingPreferences(
        mutationId: generateCloudSyncMutationId(),
        entityId: stableCloudSyncEntityId(
          'training-preferences',
          'current',
        ),
        baseVersion: null,
        goal: goal,
        sportTypes: sports,
        experienceLevel: experience,
        weeklyAvailability: weekdays,
        equipment: <String>[equipment],
      ),
    ];
  }

  static List<CloudSyncMutation> _planVersion(
    Map<String, Map<String, dynamic>> documents,
  ) {
    final Map<String, dynamic>? plan = _currentPlan(documents);
    if (plan == null) return const <CloudSyncMutation>[];
    final String localId = _nonEmpty(plan['id']) ?? '';
    final String title = _nonEmpty(plan['title']) ?? '';
    final DateTime? startsOn =
        DateTime.tryParse(plan['createdAt'] as String? ?? '');
    if (localId.isEmpty || title.isEmpty || startsOn == null) {
      return const <CloudSyncMutation>[];
    }
    final int weeks = (plan['durationWeeks'] as num?)?.toInt() ?? 0;
    return <CloudSyncMutation>[
      CloudSyncMutation.planVersion(
        mutationId: generateCloudSyncMutationId(),
        entityId: _planEntityId(localId),
        baseVersion: null,
        title: title,
        startsOn: startsOn,
        endsOn: weeks <= 0 ? null : startsOn.add(Duration(days: weeks * 7 - 1)),
        state: 'active',
      ),
    ];
  }

  static List<CloudSyncMutation> _scheduledWorkouts(
    Map<String, Map<String, dynamic>> documents,
  ) {
    final Map<String, dynamic>? plan = _currentPlan(documents);
    if (plan == null) return const <CloudSyncMutation>[];
    final String localPlanId = _nonEmpty(plan['id']) ?? '';
    if (localPlanId.isEmpty) return const <CloudSyncMutation>[];
    final String planId = _planEntityId(localPlanId);
    final String fallbackSport = _nonEmpty(plan['sportType']) ?? 'unknown';
    final Map<String, String> titles = <String, String>{
      for (final Map<String, dynamic> day in _maps(plan['workoutDays']))
        if (_nonEmpty(day['id']) case final String id)
          id: _nonEmpty(day['title']) ?? '计划训练',
    };
    final List<CloudSyncMutation> mutations = <CloudSyncMutation>[];
    for (final Map<String, dynamic> workout
        in _maps(documents[_scheduleKey]?['workouts'])) {
      final String localId = _nonEmpty(workout['id']) ?? '';
      final String workoutDayId = _nonEmpty(workout['workoutDayId']) ?? '';
      final DateTime? scheduledDate =
          DateTime.tryParse(workout['scheduledDate'] as String? ?? '');
      final int duration = (workout['allocatedMinutes'] as num?)?.toInt() ?? 0;
      if (localId.isEmpty || scheduledDate == null || duration <= 0) {
        continue;
      }
      mutations.add(
        CloudSyncMutation.scheduledWorkout(
          mutationId: generateCloudSyncMutationId(),
          entityId: _workoutEntityId(localPlanId, localId),
          baseVersion: null,
          planVersionId: planId,
          scheduledDate: scheduledDate,
          sportType: _nonEmpty(workout['discipline']) ?? fallbackSport,
          title: titles[workoutDayId] ?? '计划训练',
          durationMinutes: duration,
          state: 'scheduled',
        ),
      );
    }
    return mutations;
  }

  static List<CloudSyncMutation> _completionSummaries(
    Map<String, Map<String, dynamic>> previous,
    Map<String, Map<String, dynamic>> current,
  ) {
    final Map<String, dynamic>? plan = _currentPlan(current);
    final String localPlanId = _nonEmpty(plan?['id']) ?? '';
    if (localPlanId.isEmpty) return const <CloudSyncMutation>[];
    final Map<String, Map<String, dynamic>> previousLogs = _byId(
      _maps(previous[_logsKey]?['logs']),
    );
    final Map<String, Map<String, dynamic>> currentLogs = _byId(
      _maps(current[_logsKey]?['logs']),
    );
    final List<CloudSyncMutation> mutations = <CloudSyncMutation>[];
    for (final MapEntry<String, Map<String, dynamic>> entry
        in currentLogs.entries) {
      final Map<String, dynamic>? old = previousLogs[entry.key];
      if (old != null && jsonEncode(old) == jsonEncode(entry.value)) {
        continue;
      }
      final CloudSyncMutation? mutation = _completionMutation(
        localPlanId,
        entry.value,
        revoked: false,
      );
      if (mutation != null) mutations.add(mutation);
    }
    for (final MapEntry<String, Map<String, dynamic>> entry
        in previousLogs.entries) {
      if (currentLogs.containsKey(entry.key)) continue;
      final CloudSyncMutation? mutation = _completionMutation(
        localPlanId,
        entry.value,
        revoked: true,
      );
      if (mutation != null) mutations.add(mutation);
    }
    return mutations;
  }

  static CloudSyncMutation? _completionMutation(
    String localPlanId,
    Map<String, dynamic> log, {
    required bool revoked,
  }) {
    if (log['logKind'] == 'playerStep') return null;
    final String localLogId = _nonEmpty(log['id']) ?? '';
    final String workoutReference =
        _nonEmpty(log['planItemId']) ?? _nonEmpty(log['workoutDayId']) ?? '';
    final DateTime? endedAt =
        DateTime.tryParse(log['createdAt'] as String? ?? '') ??
            DateTime.tryParse(log['date'] as String? ?? '');
    if (localLogId.isEmpty || workoutReference.isEmpty || endedAt == null) {
      return null;
    }
    final int durationMinutes =
        ((log['actualDurationMinutes'] as num?)?.toInt() ?? 0)
            .clamp(0, 2880)
            .toInt();
    int percentage = ((log['completionPercentage'] as num?)?.toInt() ?? 0)
        .clamp(0, 100)
        .toInt();
    if (percentage == 0 && log['completed'] == true) percentage = 100;
    return CloudSyncMutation.completionSummary(
      mutationId: generateCloudSyncMutationId(),
      entityId: stableCloudSyncEntityId('completion', localLogId),
      planVersionId: _planEntityId(localPlanId),
      scheduledWorkoutId: _workoutEntityId(
        localPlanId,
        workoutReference,
      ),
      startedAt: endedAt.subtract(Duration(minutes: durationMinutes)),
      endedAt: endedAt,
      durationSeconds: durationMinutes * 60,
      completionPercentage: percentage,
      revoked: revoked,
    );
  }

  static List<CloudSyncMutation> _appSettings(
    Map<String, Map<String, dynamic>> documents,
  ) {
    final Map<String, dynamic>? settings =
        _map(documents[_settingsKey]?['settings']);
    if (settings == null) return const <CloudSyncMutation>[];
    return <CloudSyncMutation>[
      CloudSyncMutation.appSettings(
        mutationId: generateCloudSyncMutationId(),
        entityId: stableCloudSyncEntityId('app-settings', 'current'),
        baseVersion: null,
        locale: 'zh-CN',
        weekStartsOn: 1,
        notificationsEnabled: settings['enabled'] == true,
      ),
    ];
  }

  static Map<String, dynamic>? _currentPlan(
    Map<String, Map<String, dynamic>> documents,
  ) {
    return _map(documents[_planKey]?['plan']);
  }

  static Map<String, Map<String, dynamic>> _byId(
    List<Map<String, dynamic>> values,
  ) {
    return <String, Map<String, dynamic>>{
      for (final Map<String, dynamic> value in values)
        if (_nonEmpty(value['id']) case final String id) id: value,
    };
  }

  static String _planEntityId(String localPlanId) {
    return stableCloudSyncEntityId('plan-version', localPlanId);
  }

  static String _workoutEntityId(String localPlanId, String localWorkoutId) {
    return stableCloudSyncEntityId(
      'scheduled-workout:$localPlanId',
      localWorkoutId,
    );
  }

  static Map<String, dynamic>? _map(Object? value) {
    return value is Map<String, dynamic> ? value : null;
  }

  static List<Map<String, dynamic>> _maps(Object? value) {
    return value is List<dynamic>
        ? value.whereType<Map<String, dynamic>>().toList(growable: false)
        : const <Map<String, dynamic>>[];
  }

  static List<String> _strings(Object? value) {
    return value is List<dynamic>
        ? value
            .whereType<String>()
            .where((String item) => item.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
