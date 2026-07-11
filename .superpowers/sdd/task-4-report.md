# Task 4：TrainingMvpState 兼容桥报告

## RED

- 新增 `test/features/profile/application/user_profile_training_bridge_test.dart`。
- 首次执行 `flutter test test/features/profile/application/user_profile_training_bridge_test.dart --reporter compact` 失败。
- 预期失败：通过 `userProfileControllerProvider` 保存资料后，旧 `trainingMvpProvider` 的 `profileCompleted` 仍为 `false`，证明训练状态没有监听独立资料状态。

## GREEN

- `TrainingMvpController` 将资料与完成标记投影到既有 `TrainingMvpState` 字段。
- 删除训练控制器内部资料 Repository 实例、getter 与 `saveProfile()`。
- 引导页和今日训练“使用当前资料”改用 `userProfileControllerProvider.notifier.save()`。
- 资料页使用 `select` 读取资料，训练相关数据仍读取 `trainingMvpProvider`。
- 桥接测试验证完成标记、资料名称及教练建议会随新资料保存同步更新。

## 验证

- `flutter test test/features/profile/application/user_profile_controller_test.dart test/features/profile/application/user_profile_training_bridge_test.dart --reporter compact`：6 项通过。
- `flutter analyze`：通过，无问题。
- 初次完整测试因 AppleDouble 文件 `._user_profile_training_bridge_test.dart` 无法解析而中断；已清理工作树内全部 `._*` 文件。
- `flutter test --reporter compact`：53 项通过。

## 会话保留修复

### RED

- 扩展桥接测试：先启动并推进 `workout-week1-day2` 的跟练，再通过资料控制器保存资料。
- 旧实现失败：活动训练日预期为 `workout-week1-day2`，实际为 `null`，证明 `ref.watch` 触发的控制器重建清空了会话状态。

### GREEN

- `build()` 改为 `ref.read(userProfileControllerProvider)` 读取初始资料。
- 使用 `ref.listen` 监听后续资料保存，仅通过 `copyWith` 更新资料、完成标记和教练建议。
- 每日策略继续从当前 `state.profile` 派生；资料切换为无器械时，策略同步输出无器械环境，同时保留当天上下文与跟练会话。

### 验证

- 资料控制器与桥接测试：6 项通过。
- `flutter analyze`：通过，无问题。
- `flutter test --reporter compact`：53 项通过。
