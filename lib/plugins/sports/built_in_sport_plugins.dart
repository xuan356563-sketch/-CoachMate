import 'marathon_plugin.dart';
import 'trail_running_plugin.dart';
import 'strength_plugin.dart';
import 'hyrox_plugin.dart';
import 'fat_loss_plugin.dart';
import 'general_fitness_plugin.dart';
import 'rehab_plugin.dart';
import 'sport_strategy_plugin.dart';

/// 唯一正式发行工厂：四项运动、两项目标及一项支持能力。
List<SportStrategyPlugin> builtInSportPlugins() => [
      MarathonPlugin(),
      TrailRunningPlugin(),
      StrengthPlugin(),
      HyroxPlugin(),
      FatLossPlugin(),
      GeneralFitnessPlugin(),
      RehabPlugin(),
    ];
