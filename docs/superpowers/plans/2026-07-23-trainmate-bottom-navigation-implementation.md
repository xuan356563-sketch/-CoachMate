# TrainMate 底部导航 4+1 复刻实施计划

> **供智能执行者使用：** 必须使用 `superpowers:executing-plans`，按任务逐项实施。每个步骤使用复选框跟踪。

**目标：** 将现有五项底部导航和独立 AI 浮动按钮改为参考图的左右 2+2 图标与中央悬浮 AI 按钮，同时保留全部现有功能入口。

**架构：** 新建独立 `TrainMateBottomNavigation` 组件，负责胶囊底座、四个侧边入口、中央 AI 按钮、选中状态和无障碍语义。`MainShell` 继续负责路由映射与跳转，比赛功能从一级导航迁移到训练计划页内入口。

**技术栈：** Flutter、Material 3、GoRouter、Flutter Widget Test。

## 全局约束

- 底部导航严格采用左 2 项、中央 AI、右 2 项的 4+1 结构。
- 四个侧边入口依次为今日成长、训练计划、动作库、我的。
- 胶囊高度 64pt、圆角 32pt；中央按钮直径 72pt，上浮 28pt。
- 视觉仅显示图标，但必须保留中文语义标签、Tooltip、选中状态和不小于 48pt 的点击区。
- 使用现有深海军蓝、纸白、蜜桃橙品牌色，不新增依赖。
- 不修改赛事路由或数据逻辑；比赛入口迁移至训练计划页。
- 不覆盖当前工作区已有未提交改动，不提交 Git commit。

---

### 任务 1：定义导航组件契约和几何测试

**文件：**
- 新建：`lib/app/navigation/trainmate_bottom_navigation.dart`
- 修改：`lib/core/theme/trainflow_tokens.dart`
- 修改测试：`test/navigation_test.dart`

**接口：**
- 产出：`TrainMateBottomNavigation`
- 构造参数：
  - `List<NavigationItem> items`
  - `int? selectedIndex`
  - `bool aiSelected`
  - `ValueChanged<int> onDestinationSelected`
  - `VoidCallback onAiPressed`

- [ ] 先在 `test/navigation_test.dart` 增加失败测试，断言 4 个侧边入口、中央 AI、64pt 胶囊、72pt 中央按钮、2+2 对称结构和无障碍标签。
- [ ] 运行导航测试，确认因 `TrainMateBottomNavigation` 或组件 Key 不存在而失败。
- [ ] 在设计令牌中加入导航尺寸常量，并实现最小自定义组件。
- [ ] 再次运行导航测试，确认组件结构与几何断言通过。

### 任务 2：接入主壳层和路由选中状态

**文件：**
- 修改：`lib/app/navigation/main_shell.dart`
- 修改测试：`test/navigation_test.dart`

**接口：**
- `MainShell` 向自定义导航传入四项导航、可空选中索引和 AI 激活状态。
- `/races` 映射至训练计划索引 1。
- `/ai-center` 与 `/ai-coach` 激活中央 AI，四项侧边入口均不选中。

- [ ] 先增加失败测试，覆盖四项跳转、AI 激活态、比赛映射、动作检测映射和健康相关页面映射。
- [ ] 运行导航测试，确认旧五项 `NavigationBar` 行为导致失败。
- [ ] 用 `TrainMateBottomNavigation` 替换 `NavigationBar` 与独立浮动按钮。
- [ ] 运行导航测试，确认路由和选中状态通过。

### 任务 3：迁移比赛备战入口

**文件：**
- 修改：`lib/features/training_plan/plan_list_page.dart`
- 修改测试：`test/navigation_test.dart`

**接口：**
- 训练计划页在“生成新的四周计划”之后显示“比赛备战”卡片。
- 点击后调用 `context.go(AppRoutes.races)`。

- [ ] 先增加失败测试，确认训练计划页必须展示比赛入口并能进入现有赛事页面。
- [ ] 运行导航测试，确认入口缺失导致失败。
- [ ] 添加最小紧凑卡片，不改赛事页面和数据逻辑。
- [ ] 运行导航及训练计划页相关测试，确认入口可达且首页不出现比赛入口。

### 任务 4：完整验证

**文件：**
- 检查本任务全部差异。

- [ ] 在不含 AppleDouble 文件的 APFS 临时副本运行导航、训练计划和首页相关测试。
- [ ] 运行 `flutter analyze --no-pub`，记录实际错误或通过结果。
- [ ] 检查 `git diff`，确认未修改无关文件、未新增依赖。
- [ ] 在 393×852 iPhone 模拟器运行并截图，核对胶囊比例、中央上浮、安全区和选中态。
