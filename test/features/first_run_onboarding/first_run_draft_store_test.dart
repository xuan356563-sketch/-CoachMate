import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/features/first_run_onboarding/data/first_run_draft_store.dart';
import 'package:trainflow_ai/features/first_run_onboarding/domain/first_run_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('安全存储可恢复未过期的结构化草稿', () async {
    final SecureFirstRunDraftStore store = SecureFirstRunDraftStore(
      now: () => DateTime.utc(2026, 7, 5),
    );
    final FirstRunDraft draft = FirstRunDraft.initial(DateTime.utc(2026, 7, 1));

    await store.save(draft);

    expect((await store.load())?.stage, OnboardingStage.personal);
  });

  test('超过七天的草稿自动删除', () async {
    final SecureFirstRunDraftStore writer = SecureFirstRunDraftStore(
      now: () => DateTime.utc(2026, 7, 1),
    );
    await writer.save(FirstRunDraft.initial(DateTime.utc(2026, 7, 1)));
    final SecureFirstRunDraftStore reader = SecureFirstRunDraftStore(
      now: () => DateTime.utc(2026, 7, 9),
    );

    expect(await reader.load(), isNull);
    expect(await reader.load(), isNull);
  });
}
