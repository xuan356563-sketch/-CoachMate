class AppRoutes {
  static const String authLoading = '/auth-loading';
  static const String login = '/login';
  static const String terms = '/terms';
  static const String privacy = '/privacy';
  static const String accountSwitch = '/account-switch';
  static const String welcomeProfile = '/welcome/profile';
  static const String welcomeTraining = '/welcome/training';
  static const String welcomeCloudConsent = '/welcome/cloud-consent';
  static const String welcomeMembership = '/welcome/membership';
  static const String dashboard = '/dashboard';
  static const String dailyAdjustment = '/daily-adjustment';
  static const String dailyCheckIn = '/daily-check-in';
  static const String dataCenter = '/data-center';
  static const String dataRights = '/data-privacy';
  static const String activityImport = '/activity-import';
  static const String reminders = '/reminders';
  static const String onboarding = '/onboarding';
  static const String plans = '/plans';
  static const String planGenerate = '/plans/generate';
  static const String guidedWorkouts = '/plans/jump-rope';
  static const String exercises = '/exercises';
  static const String exerciseCircuits = '/exercises/circuits';
  static const String pet = '/pet';
  static const String petData = '/pet/data';
  static const String companion = '/companion';
  static const String companionArchive = '/companion/archive';
  static const String companionMemories = '/companion/memories';
  static const String aiCenter = '/ai-center';
  static const String aiCoach = '/ai-coach';
  static const String knowledge = '/knowledge';
  static const String rehab = '/rehab';
  static const String mealGuide = '/meal-guide';
  static const String motionCheck = '/motion-check';
  static const String races = '/races';
  static const String starterProgram = '/starter-program';
  static const String starterGraduation = '/starter-graduation';
  static const String workoutPlayer = '/workout-player';
  static const String weeklyReport = '/weekly-report';
  static const String growthEvidence = '/growth-evidence';
  static const String rhythmDetail = '/rhythm-detail';
  static const String progressReview = '/progress-review';
  static const String userInsights = '/user-insights';
  static const String profile = '/profile';
  static const String selfUseAcceptance = '/self-use-acceptance';
  static const String pilotValidation = '/pilot-validation';

  static String planDetail(String planId) {
    return '$plans/$planId';
  }

  static String workoutDetail(String planId, String workoutDayId) {
    return '$plans/$planId/workouts/$workoutDayId';
  }

  static String guidedWorkoutDetail(String courseId) {
    return '$guidedWorkouts/$courseId';
  }

  static String guidedWorkoutSession(String courseId) {
    return '${guidedWorkoutDetail(courseId)}/session';
  }

  static String exerciseDetail(String exerciseId) {
    return '$exercises/$exerciseId';
  }

  static String exerciseCircuitDetail(String courseId) {
    return '$exerciseCircuits/$courseId';
  }

  static String exerciseCircuitSession(String courseId, {int? rounds}) {
    final String base = '${exerciseCircuitDetail(courseId)}/session';
    return rounds == null ? base : '$base?rounds=$rounds';
  }

  static String knowledgeItem(String itemId) {
    return '$knowledge/items/$itemId';
  }
}
