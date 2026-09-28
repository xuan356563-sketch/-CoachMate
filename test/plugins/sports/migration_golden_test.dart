import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/services/plan_context_digest_service.dart';
import 'package:trainflow_ai/services/four_week_plan_generator.dart';
import 'migration_cases.dart';

void main() {
  final expected = jsonDecode(
      File('test/fixtures/plugins/migration_golden.json')
          .readAsStringSync()) as Map;
  for (final c in migrationCases()) {
    test('迁移等价：${c.id}', () {
      final g = FourWeekPlanGenerator(structureEnabled: true).generate(
          profile: c.profile,
          startsOn: DateTime(2026, 7, 13),
          race: c.race,
          preferences: c.preferences);
      final digest = const PlanContextDigestService().buildCanonicalDigest({
        'plan': g.plan.toJson(),
        'phases': g.weeks.map((w) => w.phase.jsonValue).toList(),
        'race': g.appliedRace?.id
      });
      expect(digest, expected[c.id]);
    });
  }
}
