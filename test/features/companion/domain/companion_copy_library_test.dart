import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/companion/domain/companion_copy_library.dart';
import 'package:trainflow_ai/features/companion/domain/companion_models.dart';

void main() {
  test('文案库完整保留 94 条静态文案及 13 类选题', () {
    expect(companionCopyVariants, hasLength(94));
    expect(
      companionCopyVariants
          .where((CompanionCopyVariant item) =>
              item.kind != CompanionCopyVariantKind.dismissAck)
          .map((CompanionCopyVariant item) => item.intent)
          .toSet(),
      hasLength(13),
    );
    expect(
      companionCopyVariants.where(
        (CompanionCopyVariant item) =>
            item.kind == CompanionCopyVariantKind.injuryFixed,
      ),
      hasLength(4),
    );
  });

  test('文案静态检查禁止施压、卖萌和锁屏不安全符号', () {
    expect(lintCompanionCopyLibrary(companionCopyVariants), isEmpty);
  });

  test('变量不全的文案不参与选择，同一变体三十天内不重复', () {
    final DateTime now = DateTime(2026, 8, 11);
    final CompanionCopyVariant? missingValue = pickCompanionCopyVariant(
      intent: CompanionIntent.morningBrief,
      variables: const <String, String>{},
      usedVariantIds: const <String>{},
      now: now,
      history: const <CompanionCopyHistory>[],
      random: Random(1),
    );
    expect(missingValue, isNotNull);
    expect(missingValue!.requiredVariables, isEmpty);

    final CompanionCopyVariant? repeated = pickCompanionCopyVariant(
      intent: CompanionIntent.returning,
      variables: const <String, String>{},
      usedVariantIds: const <String>{},
      now: now,
      history: <CompanionCopyHistory>[
        CompanionCopyHistory(
          variantId: 'rt-04',
          createdAt: now.subtract(const Duration(days: 10)),
        ),
      ],
      random: Random(2),
    );
    expect(repeated?.id, isNot('rt-04'));
  });

  test('伤病文案按等级固定选择，不允许随机润色', () {
    expect(
      resolveInjuryCopyVariant(painScore: 7, hasLastedMoreThanTwoWeeks: false)
          .id,
      'ic-03',
    );
    expect(
      resolveInjuryCopyVariant(painScore: 5, hasLastedMoreThanTwoWeeks: true)
          .id,
      'ic-04',
    );
    expect(
      resolveInjuryCopyVariant(painScore: 4, hasLastedMoreThanTwoWeeks: false)
          .id,
      'ic-01',
    );
  });
}
