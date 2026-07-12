# Task 1 报告：独立身体记录核心状态管理

## 实际改动

- 新增 `bodyMetricRepositoryProvider`，使用现有 `localStorageServiceProvider` 创建 `PersistedBodyMetricRepository`。
- 新增 `bodyMetricControllerProvider`、`BodyMetricState` 和 `BodyMetricController`，独立管理身体记录列表、修订、待确认指标、CSV 导入历史、状态文案和 `persistenceVersion`。
- 从 `TrainingMvpController` 的身体记录段迁入 `saveManualMetric()`、`confirmPendingMetric()`、`recognizeSnapshotText()`、`confirmDailyCheckInSameAsYesterday()`、`recordTiredDailyCheckIn()`、`importCsv()`、`clear()` 规则。
- 保留原有默认种子、状态文案、同日修订、异常阈值、CSV/截图解析行为、仓库 JSON 结构和清除后保留本次会话 CSV 导入历史。
- 每日偏累签到无历史指标时，按要求通过 `userProfileControllerProvider` 读取用户画像体重兜底。
- 新增独立控制器测试，覆盖初始种子/文案、保存与重启恢复、同日修订、异常待确认与确认、无待确认提示、截图识别成功/失败、CSV 成功/失败、两种每日签到、清除保留导入历史和版本递增规则。

## 测试命令及结果

- `find . -name '._*' -delete && flutter test test/features/data_center/application/body_metric_controller_test.dart`
  - 预期红灯：缺少 `lib/features/data_center/application/body_metric_controller.dart`、`BodyMetricState` 和 `bodyMetricControllerProvider`。
- `find . -name '._*' -delete && flutter test test/features/data_center/application/body_metric_controller_test.dart`
  - 通过，`11` 个测试全部通过。
- `find . -name '._*' -delete && flutter analyze`
  - 通过，`No issues found!`。

## 提交号

- 最终提交号见任务最终回复；Git 提交内容无法稳定包含自身哈希。

## 自检结论

- 未新增依赖。
- 未修改模型、仓库、服务、训练控制器或页面。
- 未改动数据库/存储 JSON schema，仍使用 `trainflow.body_metrics.v1`。
- `persistenceVersion` 只在仓库真实写入或清除后递增；待确认、无待确认、截图解析失败和 CSV 解析失败不递增。
- 变更范围仅限 `lib/features/data_center/application/body_metric_controller.dart`、`test/features/data_center/application/body_metric_controller_test.dart` 和 `.superpowers/sdd/task-1-report.md`。

## Concern

- 报告无法自包含最终提交哈希，否则会形成 Git 哈希自引用；最终提交号以完成回复中的 `git rev-parse HEAD` 结果为准。
