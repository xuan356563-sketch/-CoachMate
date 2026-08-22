# TrainMate 全 App「Indore」暖黑 + CycleGo 荧光绿视觉规范

> **2026-08 混合方案决策（方案 B）**  
> 主强调色：`#D4FF00`（CycleGo 荧光绿）  
> 底色分层：`#181814` 暖黑系（Indore 原规范，保留陪伴感）  
> 形状语言：CycleGo 胶囊 / 大圆角 / 白图标钮 / 荧光绿发光  
> 决策依据：暖黑底承载温度感，荧光绿强化 CTA 信号；**不加 FAB**，底部导航 v2 采用
> 「悬浮白玻璃胶囊 + 中央 hero 球体（运动搭子 / AI 入口）」：槽位顺序为
> 训练计划 · 今日训练 · **中央球体（运动搭子）** · 动作库 · 我的。

## 一、分层定位

| 层级 | 体系 | 底色 | 强调色 |
| --- | --- | --- | --- |
| 五个主标签（运动搭子 / 训练计划 / 今日训练 / 动作库 / 我的） | Indore 暖黑 | 暖黑 `#181814` | 荧光绿 `#D4FF00` |
| 详情 / 表单 / 播放器 / 统计 / 设置 / AI / 宠物等推入页 | Indore 暖黑 | 暖黑 `#181814` | 荧光绿 `#D4FF00` |

- 主标签通过 `TrainMateImmersiveHubPage` 进入 `TrainMateVisualScope(darkTraining)`。
- 详情页通过 `TrainFlowPage`、`TrainMateImmersivePage`、`TrainMateShowcasePage`
  自动建立同样的暖黑作用域并套用 `TrainMateVisualScope.darkHubTheme(context)`。

## 二、核心令牌（`TrainFlowTokens`，混合方案精确色值）

| 角色 | 令牌 | 色值 | 用途 |
| --- | --- | --- | --- |
| 交互强调 | `accent` | `#D4FF00` | 主操作、选中态、关键进度、图标强调 |
| 强调按压 | `accentDark` | `#A8CC00` | 主按钮按压态 |
| 强调高亮 | `accentLight` | `#E5FF66` | 高亮态 |
| 强调发光 | `accentGlow` | `rgba(212,255,0,0.4)` | 按钮/选中态霓虹发光 |
| 强调反白 | `onAccent` | `#181814` | 青柠底上的深字与图标（跟随暖黑底） |
| 页面底色 | `darkTrainingSurface` | `#181814` | 主标签滚动画布与场景头底色 |
| 卡片 | `darkTrainingCard` | `#1E1E1B` | 普通卡片 |
| 抬升 | `darkTrainingRaised` | `#262622` | 输入框、次级胶囊、轨道底色 |
| 最高层级 | `darkTrainingHighest` | `#2E2E29` | 重点卡、选中徽标底 |
| 前景 | `darkTrainingOnSurface` | `#FFFFFF` | 主文字 |
| 次级文字 | `darkTrainingMuted` | `#C5CDB8` | 说明、时间、副标题 |
| 辅助文字 | `darkTrainingTextTertiary` | `#8B9484` | 标签、次要导航图标 |
| 背景渐变 | `darkTrainingGradientTop → Bottom` | `#1C1C19 → #101010` | 场景头 180deg 渐变 |
| 状态色 | `AppColors.success / warning / danger` | `#4ADE80 / #FFB020 / #FF4D4F` | 完成 / 提醒 / 错误 |

主色与深字组合对比度 ≥ 16:1（AAA），仅用于需要强调的交互元素；卡片底色层级用
`darkTrainingCard → darkTrainingRaised → darkTrainingHighest` 逐级抬升，不再使用
深蓝、蜜桃或 CycleGo 绿调分层。

## 三、主标签作用域规则

1. 卡片圆角使用 `mainTabCardRadius = 16`（方案包 radius-md），页面留白
   `mainTabPageGutter = 20`，卡片间距 `mainTabCardGap = 12`，卡片内边距
   `mainTabCardPadding = 16`；主操作按钮为胶囊形（`pillRadius`）并带青柠霓虹发光
   （elevation + `accent` 阴影色）。
2. 返回等图标钮采用 CycleGo「白图标钮」：白色圆形底 + 深色图标，在暖黑界面上形成
   清晰锚点（`TrainMateBackButton` 已按此实现）。
3. `TrainFlowCard` / `ToneBadge` / `SectionTitle` / `MetricPill` / `InfoRow` /
   `TrainFlowExpandable` / `TrainFlowMedicalDisclaimer` 全部读取
   `TrainMateVisualScope`：暖黑作用域内自动改用青柠强调、抬升底色与暖黑文字层级，
   不依赖调用方传色。
4. 图标强调统一使用 `TrainFlowTokens.accent`；次级说明文字统一使用
   `darkTrainingMuted`（作用域内），主文字使用 `TrainFlowTokens.darkTrainingOnSurface`。
5. 红 / 黄 / 绿仅表达疼痛风险、训练警告与完成状态（`AppColors.danger / warning / success`），
   不作为品牌主色进入暖黑作用域。
6. 自定义绘制（如能力进步迷你趋势线、训练轨道）通过构造参数或令牌注入颜色，避免在
   painter 内直接引用旧深蓝 / 蜜桃令牌。

## 四、页面映射（主标签）

- 今日训练：场景头（问候 + 日期 + 今日任务进度）+ 状态胶囊 + 概览网格 + 成长 / 签到 /
  训练内容 / 完成记录 / AI 建议。
- 训练计划：场景头 + 计划状态 + 概览网格 + 生成入口 + 四周阶段 + 本周节奏 + 训练方案。
- 动作库：场景头 + 筛选状态 + 动作检测入口 + 部位筛选 + 双列动作卡。
- 运动搭子：场景头（伙伴形象）+ 关系状态 + 消息流 + 本地教练输入。
- 我的：档案、健康统计、康复、身体数据、营养与训练负荷入口。

## 五、本次收敛（2026-08 中文版 UI 调整）

在既有 Indore 令牌之上，清除五个主标签中残留的深蓝 / 蜜桃 / 深灰直写色，使暖黑作用域
整体一致：

- 共享组件 `InfoRow`、`TrainFlowExpandable`、`TrainFlowMedicalDisclaimer` 增加暖黑
  作用域感知，修复深色卡片上的近黑 / 深灰文字对比度问题。
- 今日训练、训练计划、动作库页面的图标、进度条、步骤圆点、周节奏标记与迷你趋势线
  改为青柠强调 + 抬升底色；说明文字改用暖黑次级文字。
- `AbilityProgressOverview`（能力进步总览）改为作用域感知，趋势线在暖黑作用域内使用
  青柠，浅色作用域保留深蓝 + 蜜桃。
- 语义状态色（红 / 黄 / 绿）与 Flow 角色品牌色保持不变。

## 六、验收尺寸

- `393 × 852`：主要手机验收尺寸。
- `430 × 932`：大屏手机验收尺寸。
- `1200px` 桌面：移动画布限制 `430px` 居中，外围为暖黑 `darkTrainingSurface`。
