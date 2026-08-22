# 移动端 UI 改造计划（mobile-ui-change-plan）

> 目标：在不破坏业务/接口/鉴权/数据结构/技术栈的前提下，把现有界面改造为「年轻、活力、游戏化、插画化、浅色暖灰底 + 深紫品牌 + 多色功能强调」方向。

## 1. 受影响页面（按优先级）

1. 首页（今日训练 dashboard）
2. 运动搭子对话页（已含球体欢迎页）
3. 训练计划 / 计划详情
4. 数据/成长证据 / 周报
5. 我的 / 个人中心
6. 动作库 / 动作详情
7. 登录 / 首次引导 / 设置等辅助页

## 2. 可复用组件（现有）

- `TrainFlowPage`（详情页脚手架，含作用域+主题）
- `TrainFlowCard` / `ToneBadge` / `InfoRow` / `SectionTitle` / `MetricPill`
- `TrainMateImmersiveHubPage`（主标签骨架）
- `TrainMateBottomNavigationV2`（悬浮胶囊 + 中央球体）
- `CoachMateOrb`（品牌球体）
- `TrainMateStatusStrip` / `TrainMateMetricValue` / `TrainMateProgressRail` / `TrainMateStatePanel` / `TrainMateIllustration`

## 3. 拟新增/改造组件

- 语义色 Token（深紫 + 紫/黄/粉/蓝/薄荷绿）✅ 已落地 `TrainFlowTokens`
- `ProgressRing`（环形进度）✅ `lib/core/design_system/trainmate_primitives.dart`
- `StreakBadge` / `LevelBadge` / `RewardBadge`（徽章族）✅ 同上
- `ChallengeCard`（多状态挑战卡）✅ `lib/core/design_system/trainmate_cards.dart`
- `StatCard`（数据指标卡，含趋势/对比/骨架屏）✅ 同上
- `Skeleton` / `EmptyState` / `ErrorState` ✅ `lib/core/design_system/trainmate_states.dart`
- `DateSelector`（胶囊日期选择）✅ `lib/core/design_system/trainmate_date_selector.dart`
- `Toast` ✅ 同上；`Button`/`IconButton` ✅ `trainmate_primitives.dart`
- Story 示例页 ✅ `trainmate_design_showcase.dart`

## 4. 风险点

- 全局深→浅 + 主色反转，golden 重生成量大。
- 5 Tab → 4 Tab 需业务确认，不能硬切。
- 多色语义需强 Token 约束，避免硬编码。
- 插画需原创（参考图为波斯语阅读应用，禁止照搬其插画/图标/品牌）。

## 5. 修改顺序（遵循计划阶段）

0. 审计（本文 + 附文档）✅
1. 设计 Token（颜色/字号/间距/圆角/阴影/动效）✅
2. 基础组件 ✅（`lib/core/design_system/`，含测试与 Story）
3. 导航 ⏳（保留 5 入口，视觉已切到浅色深紫）
4. 核心页面（首页 ✅ / 挑战 ✅ / 数据 ✅ / 我的 ✅ / 登录·首次引导·设置 待办）
5. 状态与动效
6. 测试与优化

## 6. 验收方式

- `flutter analyze --no-pub` 0 问题
- 全量 `flutter test --no-pub` 通过（含重生 golden）
- iOS 模拟器构建 + 启动 + 5 Tab/核心流程手测
- 320–430px 宽度、大字体、安全区、减少动效可用
- 对比度满足 WCAG AA，图标按钮有可访问名称
