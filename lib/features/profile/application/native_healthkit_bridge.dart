import 'health_data_gateway_contract.dart';
import 'native_healthkit_bridge_stub.dart'
    if (dart.library.io) 'native_healthkit_bridge_io.dart' as implementation;

NativeHealthKitBridge createNativeHealthKitBridge() =>
    implementation.createNativeHealthKitBridge();
