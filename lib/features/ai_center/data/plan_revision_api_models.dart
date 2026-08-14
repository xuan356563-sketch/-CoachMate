import '../../../data/models/ai_training_prescription.dart';
import '../../../data/models/adaptation_signals.dart';

class PlanRevisionRequest {
  final String clientContextDigest;
  final List<DateTime> remainingDates;
  final int completedSessions;
  final int missedSessions;
  final List<DateTime> scheduleChangeDates;
  final int availableMinutes;
  final List<String> equipmentAccess;
  final bool equipmentChanged;
  final List<String> safetyConstraintCodes;
  final AiTrainingPrescription currentPrescription;
  final AdaptationSignals? adaptationSignals;
  final bool force;

  const PlanRevisionRequest({
    required this.clientContextDigest,
    required this.remainingDates,
    required this.completedSessions,
    required this.missedSessions,
    required this.scheduleChangeDates,
    required this.availableMinutes,
    required this.equipmentAccess,
    required this.equipmentChanged,
    required this.safetyConstraintCodes,
    required this.currentPrescription,
    this.adaptationSignals,
    this.force = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'contract_version': 1,
        'client_context_digest': clientContextDigest,
        'remaining_dates': remainingDates
            .map(_dateOnly)
            .toSet()
            .take(28)
            .toList(growable: false),
        'completion_summary': <String, dynamic>{
          'completed_sessions': completedSessions,
          'missed_sessions': missedSessions,
        },
        'schedule_change_dates': scheduleChangeDates
            .map(_dateOnly)
            .toSet()
            .take(14)
            .toList(growable: false),
        'available_minutes': availableMinutes,
        'equipment_access': equipmentAccess,
        'equipment_changed': equipmentChanged,
        'safety_constraint_codes': safetyConstraintCodes,
        if (adaptationSignals != null)
          'adaptation_signals': adaptationSignals!.toJson(),
        'current_prescription': <String, dynamic>{
          'cycle_focus': currentPrescription.cycleFocus,
          'weekly_sessions': currentPrescription.weeklySessions
              .map((AiSessionBlueprint item) => item.toJson())
              .toList(growable: false),
          'progression_mode': currentPrescription.progressionMode.jsonValue,
        },
        'force': force,
      };
}

String _dateOnly(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
