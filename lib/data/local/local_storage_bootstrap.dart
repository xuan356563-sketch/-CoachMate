import 'package:trainflow_ai/data/local/local_storage_bootstrap_coordinator.dart';
import 'package:trainflow_ai/data/local/local_storage_bootstrap_stub.dart'
    if (dart.library.io) 'package:trainflow_ai/data/local/local_storage_bootstrap_io.dart'
    as platform;

Future<LocalStorageBootstrapResult> initializeLocalStorage() {
  return platform.initializeLocalStorage();
}
