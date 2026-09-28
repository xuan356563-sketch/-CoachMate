import '../../data/models/user_profile.dart';
import '../../data/models/race.dart';
import '../../plugins/sports/sport_capability_directory.dart';
import '../../services/four_week_plan_generator.dart';
import 'resource_catalog.dart';

/// 只编译候选，不读取仓储，不写有效计划。
class ResourcePlanPreview {
  ResourcePlanPreview({void Function()? checkActive})
      : _checkActive = checkActive;
  final void Function()? _checkActive;
  FourWeekPlanGeneration generate(
      {required TrainingPlanResource resource,
      required UserProfile profile,
      required DateTime startsOn,
      required SportCapabilityDirectory sports,
      RacePlan? race}) {
    _checkActive?.call();
    if (!resource.executable ||
        profile.mainSports.isEmpty ||
        profile.mainSports.first != resource.sport) {
      throw StateError('请先在个人档案中确认与模板一致的主运动');
    }
    if (sports.require(resource.sport).definition.pluginRef.id !=
        resource.ownerPluginId) {
      throw StateError('模板的运动策略不可用');
    }
    return FourWeekPlanGenerator(sportDirectory: sports)
        .generate(profile: profile, startsOn: startsOn, race: race, bindResourceExercises: true);
  }
}
