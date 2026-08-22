# 移动端 UI 审计（mobile-ui-audit）

> 生成日期：2026-08-18 · 审计对象：zhuque-flutter-main（练搭 CoachMate / 智练 TrainMate）

## 1. 技术栈

| 项 | 现状 |
| --- | --- |
| 框架 | Flutter（Material 3），单工程 iOS + Android + Web |
| 语言 | Dart（无代码生成器，纯手写） |
| 路由 | `go_router`（`lib/app/router/app_router.dart` + `app_routes.dart`），`MainShell` 承接底部导航 |
| 状态管理 | `flutter_riverpod`（大量 `ConsumerWidget` / `StateNotifier` Provider） |
| 屏幕适配 | `flutter_screenutil`（designSize 375×812） |
| 样式方案 | 自定义主题 + 语义 Token，非 CSS |
| 组件库 | 自研 `TrainFlow*` / `TrainMate*` 组件族，非第三方 UI 库 |
| 图标库 | Material Icons（`Icons.*` 线性/描边风格） |
| API 层 | `lib/features/**/data/*_api.dart`（Dio/HTTP），`authenticated_api_client.dart` 鉴权客户端 |
| 鉴权 | `auth_controller` + `session_token_store` + `account_binding_service`，登录态经 Riverpod 分发 |
| 国际化 | 无 i18n 框架，中文硬编码字符串 |
| 主题 | `TDesignTheme.lightTheme`（旧深蓝橙基础）+ `TrainFlowTokens` + `TrainMateVisualScope` + `darkHubTheme` |
| 测试 | `flutter_test` + golden（969 项） |
| 构建 | `flutter build ios --simulator --no-codesign --no-pub`；后端 pytest、运营后台 npm build |

## 2. 当前视觉基线

- 主标签（5 Tab）与推入详情页均走**暖黑作用域**：背景 `#181814` 暖黑、卡片 `#1E1E1B`、抬升 `#262622`，强调色荧光绿 `#D4FF00`，次文字 `#C5CDB8`。
- 底部导航 v2：悬浮白玻璃胶囊 + 中央 64pt「运动搭子」渐变球体 + 4 角图标。
- 主操作按钮为荧光绿胶囊 + 霓虹发光；返回按钮为白底圆形图标钮。
- 旧「深蓝橙」仅保留为 `TDesignTheme.lightTheme` 基础主题（供 darkHubTheme 派生）。

## 3. 页面与目录

- 一级 Tab（`main_shell.dart`）：训练计划 / 今日训练 / 运动搭子（中央球体）/ 动作库 / 我的。
- 推入页（35 个 `TrainFlowPage` 页面）：计划详情、动作详情、跟练播放器、签到、周报、成长证据、AI 中心、动作检测、数据中心、比赛、康复、知识库、提醒、设置等。
- 目录：`lib/features/**` 按业务域分层（application/data/presentation/domain）。

## 4. 关键问题（相对新设计方向）

1. 现状为**纯深色**，与计划「白色/暖灰底 + 深紫品牌」方向相反。
2. 一级导航 5 个（含中央球体），计划建议 4 个（首页/挑战/数据/我的）。
3. 强调色单一（荧光绿），计划要求紫/黄/粉/蓝/薄荷绿多色功能语义。
4. 游戏化元素（等级/徽章/挑战/连续打卡/排行榜）在部分页已存在，但未形成统一视觉语言。
5. 大量业务页面仍复用旧「深蓝橙」语意的 `TrainFlowCard` 色调枚举（paper/ink/peach/outline），与暖黑作用域是两套语义并存。
6. 中文硬编码，无国际化框架。

## 5. 风险

- 深→浅 + 荧光绿→深紫 是全局视觉反转，golden 全部失效需重生成，改动面约 40+ 文件。
- 导航 5→4 会改变信息架构，需与业务对齐，不能只做视觉。
- 多色语义若不做 Token 约束，易出现颜色硬编码回潮。
