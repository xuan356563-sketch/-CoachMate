import 'package:flutter/foundation.dart';

final AuthRouteRefreshNotifier authRouteRefreshNotifier =
    AuthRouteRefreshNotifier();

class AuthRouteRefreshNotifier extends ChangeNotifier {
  void refresh() {
    notifyListeners();
  }
}
