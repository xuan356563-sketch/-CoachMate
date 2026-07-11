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

  // 旧 Demo 常量保留给未删除的示例源码引用。
  static const String index = dashboard;
  static const String basic = '/basic';
  static const String component = '/component';
  static const String template = '/template';
  static const String about = '/about';
  static const String color = '/basic/color';
  static const String icon = '/basic/icon';
  static const String button = '/basic/button';
  static const String typography = '/basic/typography';
  static const String border = '/basic/border';
  static const String shadow = '/basic/shadow';
  static const String flex = '/basic/flex';
  static const String title = '/basic/title';

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
