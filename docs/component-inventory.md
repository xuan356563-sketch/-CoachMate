# 组件清单（component-inventory）

## 主题与 Token

| 文件 | 说明 |
| --- | --- |
| `lib/core/theme/trainflow_tokens.dart` | 颜色/间距/圆角/动效 Token（`TrainFlowTokens` / `TrainFlowMotion`） |
| `lib/core/theme/trainmate_visual_mode.dart` | 暖黑作用域 `TrainMateVisualScope` + `darkHubTheme` |
| `lib/core/theme/tdesign_theme.dart` | 基础 Material 主题 + textTheme |
| `lib/core/constants/app_colors.dart` | 旧扁平色 + 状态色 |

## 布局骨架

- `TrainFlowPage`（详情页：头部 + 内容 + 免责）
- `TrainMateImmersiveHubPage`（主标签沉浸骨架）
- `TrainMateImmersivePage` / `TrainMateShowcasePage`（播放器/展示页）

## 导航

- `TrainMateBottomNavigation`（v1，滑动圆盘，保留回退）
- `TrainMateBottomNavigationV2`（悬浮胶囊 + 中央球体，当前启用）
- `TrainMateBackButton`（白图标钮）

## 卡片与容器

- `TrainFlowCard`（tone: paper/ink/peach/outline）
- `ToneBadge` / `SectionTitle` / `InfoRow` / `MetricPill`
- `TrainMateStatusStrip` / `TrainMateMetricValue` / `TrainMateOverviewGrid`
- `TrainMateProgressRail` / `TrainMateRecordTile` / `TrainMateMetricCapsule`

## 品牌与插画

- `CoachMateOrb` / `CoachMateOrbPainter`（品牌球体）
- `TrainMateActionCharacter` / `FlowMascot` / `TrainMateBrandmark`
- `TrainMateIllustration`（插画 + 回退）
- `IllustratedPetRenderer`（宠物形象）

## 状态组件

- `TrainMateStatePanel`（统一状态面板）
- `TrainFlowExpandable` / `TrainFlowMedicalDisclaimer`

## 设计系统基础组件（阶段 2，已新增 `lib/core/design_system/`）

| 文件 | 组件 |
| --- | --- |
| `trainmate_primitives.dart` | `TrainMateButton`（primary/secondary/tertiary/destructive，含 loading/disabled）、`TrainMateIconButton`（neutral/filled/outline）、`TrainMateBadge`（紫/黄/粉/珊瑚/蓝/薄荷/中性）+ `TrainMateStreakBadge`/`TrainMateLevelBadge`/`TrainMateRewardBadge`、`TrainMateProgressRing`、`TrainMateProgressBar` |
| `trainmate_cards.dart` | `TrainMateStatCard`（含骨架屏态）、`TrainMateChallengeCard`（available/active/completed/expired/locked/failed 六状态） |
| `trainmate_states.dart` | `TrainMateSkeleton` / `TrainMateSkeletonListTile`、`TrainMateEmptyState`、`TrainMateErrorState`、`TrainMateToast` + `showTrainMateToast` |
| `trainmate_date_selector.dart` | `TrainMateDateSelector`（胶囊日期、今/标记圆点、日历入口） |
| `trainmate_design_showcase.dart` | `TrainMateDesignShowcase`（全部组件的 Story 示例页） |

测试：`test/core/design_system/trainmate_ui_test.dart`（22 项）。

## 待新增（按改造计划）

- 阶段 3 导航重构（保留 5 入口，视觉已切到位）
- 阶段 4 核心页面（首页 / 挑战 / 数据 / 我的 / 登录引导）逐页接入上述组件与游戏化卡片、多色功能语义、原创插画
- 阶段 5 状态与动效（骨架屏 / 空态 / 错误态接入业务页、减少动效）
