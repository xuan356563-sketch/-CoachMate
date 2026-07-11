import '../models/motion_check.dart';
import '../seed/seed_motion_checks.dart';

abstract class MotionCheckRepository {
  List<MotionCheckRule> listMotionChecks();

  MotionCheckRule? findById(String id);
}

class InMemoryMotionCheckRepository implements MotionCheckRepository {
  final List<MotionCheckRule> _motionChecks;

  InMemoryMotionCheckRepository({List<MotionCheckRule>? initialMotionChecks})
      : _motionChecks =
            List<MotionCheckRule>.from(initialMotionChecks ?? seedMotionChecks);

  @override
  List<MotionCheckRule> listMotionChecks() {
    return List<MotionCheckRule>.unmodifiable(_motionChecks);
  }

  @override
  MotionCheckRule? findById(String id) {
    for (final MotionCheckRule rule in _motionChecks) {
      if (rule.id == id) {
        return rule;
      }
    }
    return null;
  }
}
