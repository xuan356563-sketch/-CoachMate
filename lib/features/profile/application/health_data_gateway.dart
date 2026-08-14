import 'health_data_gateway_contract.dart';
import 'health_data_gateway_stub.dart'
    if (dart.library.io) 'health_data_gateway_io.dart' as implementation;

export 'health_data_gateway_contract.dart';

HealthDataGateway createHealthDataGateway() =>
    implementation.createHealthDataGateway();
