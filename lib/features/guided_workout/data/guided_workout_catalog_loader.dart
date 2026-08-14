import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/guided_workout_course.dart';

const String guidedWorkoutCatalogAsset =
    'assets/training/jump_rope_courses.json';
const String functionalCircuitCatalogAsset =
    'assets/training/functional_circuits.json';

const List<String> guidedWorkoutCatalogAssets = <String>[
  guidedWorkoutCatalogAsset,
  functionalCircuitCatalogAsset,
];

final guidedWorkoutCatalogProvider =
    FutureProvider<GuidedWorkoutCatalog>((Ref ref) async {
  return GuidedWorkoutCatalogLoader().load();
});

class GuidedWorkoutCatalogLoader {
  final AssetBundle bundle;

  GuidedWorkoutCatalogLoader({AssetBundle? bundle})
      : bundle = bundle ?? rootBundle;

  Future<GuidedWorkoutCatalog> load() async {
    final List<dynamic> courses = <dynamic>[];
    for (final String asset in guidedWorkoutCatalogAssets) {
      final String source = await bundle.loadString(asset);
      final dynamic decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw FormatException('课程配置 $asset 的根节点必须是对象。');
      }
      final dynamic rawCourses = decoded['courses'];
      if (rawCourses is! List) {
        throw FormatException('课程配置 $asset 缺少 courses 列表。');
      }
      courses.addAll(rawCourses);
    }
    return GuidedWorkoutCatalog.fromJson(<String, dynamic>{'courses': courses});
  }
}
