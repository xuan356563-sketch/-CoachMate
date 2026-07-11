import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:trainflow_ai/services/local_storage_service.dart';

class TestHarness {
  TestHarness({InMemoryLocalStorageService? storageService})
      : storageService = storageService ?? InMemoryLocalStorageService();

  final InMemoryLocalStorageService storageService;

  Widget buildApp(Widget child) {
    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storageService),
      ],
      child: child,
    );
  }
}
