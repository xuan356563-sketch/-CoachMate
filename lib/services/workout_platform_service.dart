import 'workout_platform_service_stub.dart'
    if (dart.library.html) 'workout_platform_service_web.dart'
    if (dart.library.io) 'workout_platform_service_io.dart' as platform;

class WorkoutPlatformService {
  Future<bool> speak(
    String text, {
    double rate = 1,
    String? voiceName,
  }) {
    return platform.speak(text, rate: rate, voiceName: voiceName);
  }

  Future<void> stopSpeech() {
    return platform.stopSpeech();
  }

  Future<bool> setScreenAwake(bool enabled) {
    return platform.setScreenAwake(enabled);
  }
}
