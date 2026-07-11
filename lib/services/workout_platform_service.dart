import 'workout_platform_service_stub.dart'
    if (dart.library.html) 'workout_platform_service_web.dart' as platform;

class WorkoutPlatformService {
  Future<bool> speak(String text) {
    return platform.speak(text);
  }

  Future<void> stopSpeech() {
    return platform.stopSpeech();
  }

  Future<bool> setScreenAwake(bool enabled) {
    return platform.setScreenAwake(enabled);
  }
}
