class AppRoutes {
  static const String dashboard = '/dashboard';
  static const String dailyAdjustment = '/daily-adjustment';
  static const String dailyCheckIn = '/daily-check-in';
  static const String dataCenter = '/data-center';
  static const String activityImport = '/activity-import';
  static const String reminders = '/reminders';
  static const String onboarding = '/onboarding';
  static const String plans = '/plans';
  static const String exercises = '/exercises';
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
  static const String userInsights = '/user-insights';
  static const String profile = '/profile';
  static const String selfUseAcceptance = '/self-use-acceptance';

  static String planDetail(String planId) {
    return '$plans/$planId';
  }

  static String workoutDetail(String planId, String workoutDayId) {
    return '$plans/$planId/workouts/$workoutDayId';
  }

  static String exerciseDetail(String exerciseId) {
    return '$exercises/$exerciseId';
  }
}
