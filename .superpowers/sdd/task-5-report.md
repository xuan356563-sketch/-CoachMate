# Task 5：拆分用户资料和首次引导测试报告

## 变更

- 新增 `test/support/test_harness.dart`，统一为应用测试提供带 `InMemoryLocalStorageService` 覆盖的 `ProviderScope`。
- 将资料仓库持久化和旧档案兼容测试从 `test/widget_test.dart` 移至 `test/data/repositories/user_profile_repository_test.dart`，断言语义保持不变。
- 将首次引导交互测试从 `test/widget_test.dart` 移至 `test/features/onboarding/onboarding_page_test.dart`，通过测试壳运行真实 `TrainFlowApp`。
- 保持资料桥接测试独立，未调整其文件或其余测试顺序。
- README 改为说明资料状态测试已独立，并以 `flutter test` 实际输出作为结果依据，不再写死测试数量。

## 验证

- `flutter test test/data/repositories/user_profile_repository_test.dart test/features/onboarding/onboarding_page_test.dart test/features/profile/application/user_profile_controller_test.dart test/features/profile/application/user_profile_training_bridge_test.dart --reporter compact`：9 项通过。
- `flutter analyze`：通过，无问题。
- `flutter test --reporter compact`：首次因 AppleDouble `._*` 文件无法解码而中断；清理工作树内全部 `._*` 文件后，53 项全部通过。
