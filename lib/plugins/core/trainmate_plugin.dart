import 'plugin_context.dart';
import 'plugin_descriptor.dart';

abstract class TrainMatePlugin {
  PluginDescriptor get descriptor;
  Future<void> initialize(PluginContext context);
}
