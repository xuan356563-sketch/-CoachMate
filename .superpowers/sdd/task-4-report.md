# Task 4：TrainingMvpState 兼容桥报告

## RED

- 新增 `test/features/profile/application/user_profile_training_bridge_test.dart`。
- 首次执行 `flutter test test/features/profile/application/user_profile_training_bridge_test.dart --reporter compact` 失败。
- 预期失败：通过 `userProfileControllerProvider` 保存资料后，旧 `trainingMvpProvider` 的 `profileCompleted` 仍为 `false`，证明训练状态没有监听独立资料状态。

## GREEN

- `TrainingMvpController.build()` 监听 `userProfileControllerProvider`，并将资料与完成标记投影到既有 `TrainingMvpState` 字段。
- 删除训练控制器内部资料 Repository 实例、getter 与 `saveProfile()`。
- 引导页和今日训练“使用当前资料”改用 `userProfileControllerProvider.notifier.save()`。
- 资料页使用 `select` 读取资料，训练相关数据仍读取 `trainingMvpProvider`。
- 桥接测试验证完成标记、资料名称及教练建议会随新资料保存同步更新。

## 验证

- `flutter test test/features/profile/application/user_profile_controller_test.dart test/features/profile/application/user_profile_training_bridge_test.dart --reporter compact`：6 项通过。
- `flutter analyze`：通过，无问题。
- 初次完整测试因 AppleDouble 文件 `._user_profile_training_bridge_test.dart` 无法解析而中断；已清理工作树内全部 `._*` 文件。
- `flutter test --reporter compact`：53 项通过。
