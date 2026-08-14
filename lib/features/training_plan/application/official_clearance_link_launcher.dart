import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/pre_exercise_clearance.dart';

final officialClearanceLinkLauncherProvider =
    Provider<OfficialClearanceLinkLauncher>(
  (Ref ref) => const UrlOfficialClearanceLinkLauncher(),
);

abstract class OfficialClearanceLinkLauncher {
  Future<bool> open();
}

class UrlOfficialClearanceLinkLauncher
    implements OfficialClearanceLinkLauncher {
  const UrlOfficialClearanceLinkLauncher();

  @override
  Future<bool> open() {
    return launchUrl(
      Uri.parse(PreExerciseClearance.officialSourceUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}
