import '../../data/models/plan_adjustment.dart';
import '../../data/repositories/plan_adjustment_repository.dart';
import '../../features/resource_library/assessment_record.dart';
import '../../features/resource_library/assessment_record_repository.dart';
import '../../features/motion_check/running/running_form_report_repository.dart';
import '../../features/motion_check/running/running_form_assessment_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/generated_training_plan.dart';
import '../../data/models/training_plan.dart';
import '../../data/models/training_log.dart';
import '../../data/models/weekly_report.dart';
import '../../data/models/training_metrics.dart';
import '../../data/models/growth_evidence.dart';
import '../../data/models/training_schedule.dart';
import '../../data/repositories/generated_training_plan_repository.dart';
import '../../data/repositories/training_log_repository.dart';
import '../../data/repositories/weekly_report_repository.dart';
import '../../data/repositories/training_schedule_repository.dart';
import '../../data/repositories/training_metrics_repository.dart';
import '../../data/repositories/growth_evidence_repository.dart';
import '../../features/growth/application/growth_evidence_controller.dart';
import '../../features/growth/application/training_metrics_provider.dart';
import '../../services/local_storage_service.dart';
import '../application/plugin_runtime_provider.dart';

/// 核心历史只读接口：不创建 fallback、重排日程、结算成长或补生成报告。
class CoreHistory {
  CoreHistory(
      {required this.storage,
      required this.metrics,
      required this.growth,
      required this.checkScope});
  final LocalStorageService storage;
  final TrainingMetricsRepository metrics;
  final GrowthEvidenceRepository growth;
  final void Function() checkScope;
  GeneratedTrainingPlanHistory getPlanHistory() {
    checkScope();
    return GeneratedTrainingPlanRepository(storage).getHistory();
  }

  TrainingPlan? getLegacyPlan() {
    checkScope();
    return GeneratedTrainingPlanRepository(storage).getPlan();
  }

  GeneratedPlanVersion? getPlanVersion(String versionId) {
    for (final version in getPlanHistory().versions) {
      if (version.id == versionId) return version;
    }
    return null;
  }

  List<AssessmentRecord> listAssessments() {
    checkScope();
    return AssessmentRecordRepository(storage).list();
  }

  List<RunningFormReport> listRunningReports() {
    checkScope();
    return RunningFormReportRepository(storage).list();
  }

  List<TrainingLog> listLogs() {
    checkScope();
    return PersistedTrainingLogRepository(storage).listLogs();
  }

  List<WeeklyReport> listWeeklyReports() {
    checkScope();
    return PersistedWeeklyReportRepository(storage).listReports();
  }

  List<ScheduledWorkout> listSchedule() {
    checkScope();
    return TrainingScheduleRepository(storage).listSchedule();
  }

  Future<List<ReportRevision>> listReportRevisions(
      {required String athleteProfileId,
      required MetricPeriod period,
      required DateTime periodStart}) async {
    checkScope();
    final result = await metrics.listReportRevisions(
        athleteProfileId: athleteProfileId,
        period: period,
        periodStart: periodStart);
    checkScope();
    return result;
  }

  List<PlanAdjustment> listCourseAdjustments() {
    checkScope();
    return PersistedPlanAdjustmentRepository(storage).listAdjustments()
        .where((a) => a.workoutSnapshot != null).toList(growable: false);
  }

  Future<List<WeeklyGrowthReport>> listGrowthReports(
      {required String athleteProfileId,
      int limit = 30,
      int offset = 0}) async {
    checkScope();
    final result = await growth.listWeeklyReports(
        athleteProfileId: athleteProfileId, limit: limit, offset: offset);
    checkScope();
    return result;
  }
}

final coreHistoryProvider = Provider<CoreHistory>((ref) {
  final storage = ref.watch(localStorageServiceProvider);
  final runtime = ref.read(pluginRuntimeProvider);
  final accountEpoch =
      ref.watch(pluginRuntimeProvider.select((value) => value.accountEpoch));
  var active = true;
  ref.onDispose(() => active = false);
  final history = CoreHistory(
      storage: storage,
      metrics: ref.watch(trainingMetricsRepositoryProvider),
      growth: ref.watch(growthEvidenceRepositoryProvider),
      checkScope: () {
        if (!active ||
            runtime.isAccountChanging ||
            accountEpoch != runtime.accountEpoch) {
          throw StateError('账户或数据域已变化，请重新打开历史记录。');
        }
      });
  final unregister = runtime.service('core.history')?.bind('reader', history);
  if (unregister != null) ref.onDispose(unregister);
  return history;
});
