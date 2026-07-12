# Task 1：独立每日调整与提醒状态管理报告

## RED

- 新增每日调整和提醒设置控制器单元测试，使用 `InMemoryLocalStorageService` 覆盖本地存储。
- 执行 `flutter test test/features/daily_adjustment/application/daily_adjustment_controller_test.dart test/features/reminders/application/reminder_settings_controller_test.dart --reporter compact`。
- 首次失败：两个目标 controller 尚未创建，测试无法导入对应文件，证明测试先于实现建立。
- 外接工作树中的 AppleDouble `._*` 文件会让 Flutter native-assets 缓存清理失败；已在每次 Flutter 测试前清理这些临时文件及空的 `build/native_assets` 缓存目录。

## GREEN

- 新增 `DailyAdjustmentController` 与 `dailyContextRepositoryProvider`，默认通过 `PersistedDailyContextRepository` 使用 `localStorageServiceProvider`。
- 初始每日调整状态在不存在本地上下文时读取用户资料的 `dailyAvailableMinutes`；已有本地上下文时以仓库持久化内容为准。
- 可分别更新可训练时长、工作压力、训练场地、天气，并可应用 `DailyAdjustmentDecision`；每次写入均使用仓库返回值更新状态，状态文案与原 `TrainingMvpController` 保持一致。
- 新增 `ReminderSettingsController` 与 `reminderSettingsRepositoryProvider`，默认通过 `PersistedReminderSettingsRepository` 使用 `localStorageServiceProvider`。
- 提醒开关和固定时间设置均保留原有持久化、规范化与用户可见状态文案。
- 单元测试覆盖资料默认值、本地优先、写入规范化、重新读取、全部每日约束操作、应用决策，以及提醒设置的初始值、切换、时间规范化和恢复。

## 验证

- `flutter test test/features/daily_adjustment/application/daily_adjustment_controller_test.dart test/features/reminders/application/reminder_settings_controller_test.dart --reporter compact`：6 项通过。
- `flutter analyze`：通过，无问题。
- `flutter test --reporter compact`：60 项通过。
