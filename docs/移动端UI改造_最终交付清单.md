# 移动端 UI 改造 · 最终交付清单

> 范围：按参考图设计语言把 CoachMate 统一为「浅色暖灰底 + 深紫品牌 + 多色游戏化」。
> 对应提交：`09d5f16`（干净设计提交，729 文件）。工作树剩余 177 项为用户既有 WIP，未纳入。
> 日期：2026-08

## 一、验证结果

| 项 | 结果 |
|---|---|
| `flutter analyze --no-pub` | `No issues found!` |
| `flutter test --no-pub` | **997 项全部通过**（含新增 emp_system 组件测试） |
| Goldens | 已 `--update-goldens` 重生成（视觉回归随色值切换同步） |
| iOS 模拟器 | `flutter build ios --simulator --no-codesign --no-pub` 通过并启动成功 |

## 二、设计系统（Token）

- `lib/core/theme/trainflow_tokens.dart`：浅色暖灰底 `#F6F6F4`、卡片 `#FFFFFF`、深紫品牌 `#191331/#6C3DF4`、白字 `#171522`、多色功能 `yellow #FFD54A / pink #F083C6 / blue #438CF5 / mint #67E6B1 / coral #FF665B`、发光 `accentGlow`、间距 4pt 网格、圆角/胶囊、动效 Token。
- `lib/core/theme/trainmate_visual_mode.dart`：`darkHubTheme` 亮度 light；`TrainMateVisualScope`。
- `lib/core/theme/tdesign_theme.dart`：基础主题 + textTheme（34/28/22/18/16/14/12、字重 700/600/400）+ Slider overlay 粉。
- `lib/core/constants/app_colors.dart`：品牌色深紫/粉 + 状态色（成功 #2DBE7F / 提醒 #F4A62A / 错误 #E84A5F）。

## 三、新增组件

- `lib/core/widgets/coach_mate_orb.dart`：品牌渐变球体（旋转锥形渐变 + 高光 + 唤醒表情 + 光环）。
- `lib/core/widgets/emp_system.dart`：
  - `EmpProgressRing`（环形进度）
  - `EmpSkeleton`（骨架屏，一次性脉冲 + 减动效静态）
  - `EmpEmptyState`（空状态：图标底 + 标题 + 说明 + 主操作）
  - `EmpBadge`（多色功能徽章：品牌/黄/粉/蓝/薄荷绿/中性）
  - `EmpStatPanel`（高亮统计面板：大数字 + 单位 + 副值 + 分段进度）
  - `EmpIllustrationCard`（插画卡：纯色底 + 原创 Flow 角色 + 标题/时间 + 动作按钮）

## 四、导航与页面

- 底部导航 v2（`lib/app/navigation/trainmate_bottom_navigation_v2.dart` + `main_shell.dart`）：悬浮白胶囊 + 图标 + **文字标签** + 中央球体（运动搭子），深紫选中高亮，1.4× 文本缩放上限。
- 首页（`today_training_page.dart` / `today_showcase_header.dart`）：今日准备度高亮统计块 + 「今日成就」插画卡（黄底）+ 成长环形进度。
- 比赛/挑战（`race_prep_page.dart`）：「下一场挑战」插画卡（蓝底 + 查看排期）+ 多色状态徽章。
- 数据·成长（`growth_evidence_page.dart` / `ability_progress_overview.dart`）：环形等级进度 + 黄色成就徽章 + 指标多色圆点 + 空态（EmpEmptyState）+ 雷达图多色数据点。
- 我的（`profile_page.dart`）：粉圈圆形头像 + 成就徽章环形进度 + 多色徽章。
- 运动搭子（`companion_feed_page.dart`）：聊天式欢迎页（大球体 + 问候 + 渐变标题 + 语音入口）+ 输入条。
- 登录/首次引导（`auth_pages.dart`）：品牌 + 简洁表单 + 首次建档步骤徽章。

## 五、动作库 AI 模特图

- `assets/images/exercises/ai-female/`（女模特，687 张→720px JPG）、`ai-male/`（男模特）。
- `lib/data/seed/seed_exercise_builder.dart`：`ExerciseDemoSet { freeDb, female, male }` + 默认 female；重叠动作用 AI 套，其余回退免费库。
- `pubspec.yaml`：新增 `ai-female/`、`ai-male/` 资源目录。

## 六、测试

- `test/core/emp_system_test.dart`（新增，6 项）。
- `test/navigation_test.dart`、`test/widget_test.dart`、`test/goldens/*`、`test/core/trainflow_visual_system_test.dart`、`test/core/trainmate_action_character_test.dart`、`test/core/trainmate_back_button_test.dart` 等同步适配（金色基线重生成、标签/尺寸/颜色断言更新）。

## 七、文档

- `docs/design/trainmate_主标签_Indore_视觉规范.md`（更新为浅色深紫 + 多色）。
- `docs/design/trainmate_参考图设计语言分析.md`（参考图设计语言规则与套用点）。
- `docs/mobile-ui-audit.md`、`docs/mobile-ui-change-plan.md`、`docs/navigation-map.md`、`docs/component-inventory.md`（阶段 0 审计产物）。

## 八、已知说明

- 未修改后端契约/业务逻辑/数据；仅视觉与相关资源。
- Flow 吉祥物品牌色、宠物物种色为锁定品牌（有测试断言），未改动。
- 骨架屏默认一次性脉冲（避免测试 settle 卡死）；接入真实列表时按加载态复用。
- 语音输入为入口占位（提示即将上线）。
- 未提交的 177 项为既有 WIP（pet/后端/运营后台/web/android/ios 等），与本设计无关。
