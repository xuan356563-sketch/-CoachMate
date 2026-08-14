import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/onboarding/conversational_profile_card.dart';
import 'package:trainflow_ai/features/onboarding/data/sensitive_profile_draft_store.dart';

class _MemorySensitiveDraftStore implements SensitiveProfileDraftStore {
  ProfileSensitiveDraft? value;
  int saveCount = 0;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    value = null;
  }

  @override
  Future<ProfileSensitiveDraft?> load() async => value;

  @override
  Future<void> save(ProfileSensitiveDraft draft) async {
    saveCount += 1;
    value = draft;
  }
}

void main() {
  testWidgets('本地画像提议只有点击确认后才写入页面草稿', (tester) async {
    ProfileDraftPatch? confirmed;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConversationalProfileCard(
                onConfirmed: (ProfileDraftPatch patch) {
                  confirmed = patch;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('profile-conversation-input')),
      '我是跑步初学者，目标减脂，每周3天，每次45分钟，使用哑铃。',
    );
    await tester.tap(find.byKey(const Key('profile-conversation-analyze')));
    await tester.pump();

    expect(confirmed, isNull);
    expect(find.text('待你确认'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('profile-conversation-confirm')),
    );
    await tester.tap(find.byKey(const Key('profile-conversation-confirm')));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.weeklyTrainingDays, 3);
    expect(confirmed!.availableMinutes, 45);
  });

  testWidgets('敏感字段先加密留在本机并在确认后写入页面草稿', (tester) async {
    final _MemorySensitiveDraftStore store = _MemorySensitiveDraftStore();
    ProfileDraftPatch? confirmed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensitiveProfileDraftStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConversationalProfileCard(
                onConfirmed: (ProfileDraftPatch patch) => confirmed = patch,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('profile-conversation-input')),
      '我32岁，身高175cm，体重70kg，膝盖疼。'
      '我是跑步初学者，目标减脂，每周3天，每次45分钟，使用哑铃。',
    );
    await tester.tap(find.byKey(const Key('profile-conversation-analyze')));
    await tester.pumpAndSettle();

    expect(store.saveCount, 1);
    expect(store.value?.declaredAge, 32);
    expect(find.textContaining('仅保存在本机'), findsWidgets);
    expect(confirmed, isNull);

    await tester.ensureVisible(
      find.byKey(const Key('profile-conversation-confirm')),
    );
    await tester.tap(find.byKey(const Key('profile-conversation-confirm')));
    await tester.pumpAndSettle();

    expect(confirmed?.declaredAge, 32);
    expect(confirmed?.heightCm, 175);
    expect(confirmed?.weightKg, 70);
    expect(confirmed?.injuryHistory, contains('膝盖疼'));
    expect(store.clearCount, 1);
  });

  testWidgets('缺失字段显示紧凑追问且仍不自动修改草稿', (tester) async {
    final _MemorySensitiveDraftStore store = _MemorySensitiveDraftStore();
    ProfileDraftPatch? confirmed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensitiveProfileDraftStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConversationalProfileCard(
                onConfirmed: (ProfileDraftPatch patch) => confirmed = patch,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('profile-conversation-input')),
      '想开始运动。',
    );
    await tester.tap(find.byKey(const Key('profile-conversation-analyze')));
    await tester.pumpAndSettle();

    expect(find.text('还需要确认'), findsOneWidget);
    expect(find.byKey(const Key('profile-follow-up-goal')), findsOneWidget);
    expect(
      find.byKey(const Key('profile-follow-up-primary_sport')),
      findsOneWidget,
    );
    expect(confirmed, isNull);
  });
}
