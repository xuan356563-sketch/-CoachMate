# TrainMate Flow V2 高饱和精修实施计划

> **执行代理要求：** 使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务执行；所有素材写入前均先保留校验值，不自动提交、推送或创建分支。

**目标：** 将旧版深蓝软团 Flow 恢复为全 App 主形象，在不改变轮廓和 20 个动作语义的前提下增强高饱和色彩、表情和器材细节。

**架构：** 新建独立 `flow-v2-color-detail` 素材包，运行时主路径切换到 V2，旧 Flow 作为第一回退，Flow Dog 原文件保留但退出主路径。图像编辑负责视觉层，确定性脚本负责 Alpha 轮廓锁定、尺寸归一化、manifest 和验收。

**技术栈：** Flutter、Dart、原生 iOS/Android 资源、PNG/RGBA、现有 Python/Pillow 图片脚本、Flutter Widget/Golden 测试。

## 全局约束

- 不改变 `TrainMateAction`、`FlowMascotAction`、`FlowMascotExpression`、路由或业务状态接口。
- 不新增第三方依赖，不升级 Flutter、Dart、Gradle、Pods 或锁文件。
- 不覆盖或删除旧 Flow、Flow Dog、用户现有未提交/未跟踪文件。
- 只使用旧 Flow 内部资产作为编辑输入，不使用第三方角色参考图。
- 动作素材固定为 20 个动作 × 2 个背景版本，`512×512` RGBA。

---

### 任务 1：建立可回滚素材契约

**文件：**
- 新建：`assets/branding/flow-v2-color-detail/manifest.json`
- 新建：`scripts/tests/test_flow_v2_assets.py`
- 修改：`pubspec.yaml`

**接口：**
- manifest 每项包含 `id`、`sourcePath`、`outputPath`、`variant`、`width`、`height`、`sha256`、`sourceSha256`、`alphaIou`、`reviewStatus`。
- `reviewStatus` 初始为 `pending`，人工通过后才允许改为 `approved`。

- [ ] 保存品牌相关目标文件的 `git status`、定向 diff 和 SHA-256，不处理无关脏文件。
- [ ] 先写失败测试：验证 V2 manifest 架构、调色板、旧 Flow 源文件基线及逐文件源 SHA-256。
- [ ] 运行 `python3 -m pytest scripts/tests/test_flow_v2_assets.py -q`，确认因 V2 manifest 尚不存在而失败。
- [ ] 建立 manifest 契约并在 `pubspec.yaml` 注册 V2 运行时目录；旧 Flow 继续注册用于回退，Flow Dog 文件不删除。此阶段测试必须独立通过，不提前要求任务 3 才会产生的 40 张输出图。

### 任务 2：锁定视觉母版与代表动作

**文件：**
- 新建：`assets/branding/flow-v2-color-detail/source/`
- 新建：`assets/branding/flow-v2-color-detail/review/flow-v2-style-contact-sheet.png`

**接口：**
- 主头像保持旧版 `trainmate-flow-character-1024.png` 的外轮廓。
- 联系表包含主头像、6 种表情、指引/跑步/冥想/哑铃弯举 4 个代表动作。

- [ ] 使用图像编辑工具仅重绘旧 Flow 轮廓内部，应用规格中锁定的 11 色调色板。
- [ ] 以原图 Alpha 蒙版裁掉外溢像素，统一透明画布、安全区和中心。
- [ ] 生成联系表并检查：无动物特征、无新增肢体、无文字/水印、脸板和头带比例不变。
- [ ] 人工确认联系表前，不生成其余 16 个动作，也不切换运行时代码。

### 任务 3：批量完成品牌与动作素材

**文件：**
- 新建：`assets/branding/flow-v2-color-detail/action-characters/{navy,peach-light}/`
- 新建：`assets/branding/flow-v2-color-detail/exports/png/`
- 新建：`assets/branding/flow-v2-color-detail/review/flow-v2-action-set-overview.png`

**接口：**
- 文件名严格复用 `TrainMateAction.fileName`。
- 浅色页面使用 `navy`，深色页面使用 `peach-light`；两版姿态和表情必须一致。

- [ ] 在代表动作通过后，逐张编辑其余动作，保持原姿态与器械。
- [ ] 生成品牌头像多尺寸、角色多尺寸、组合标、1024 图标和 20 动作总览。
- [ ] 扩展资产测试，验证品牌导出、40 张动作图、逐文件 manifest、尺寸、透明通道和安全区。
- [ ] 写入每个源图和输出图的真实尺寸、SHA-256 与 Alpha IoU。
- [ ] 运行资产测试；任何 IoU `<0.985`、边界偏移 `>2px`、触边或缺 Alpha 的文件单独退回重做。

### 任务 4：切换 Flutter 运行时与原生图标

**文件：**
- 修改：`lib/core/widgets/trainmate_branding.dart`
- 修改：`lib/core/widgets/trainmate_action_character.dart`
- 修改：`lib/core/widgets/flow_mascot.dart`
- 修改：iOS、Android、Web 图标配置与资源

**接口：**
- `TrainMateBrandAssets` 对外字段名保持不变，值改为 V2 路径；错误回退指向旧 Flow 导出。
- `TrainMateActionAssets.path()` 返回 V2，`legacyPath()` 返回旧 Flow；现有构造参数与背景自动选色行为不变。

- [ ] 先更新路径、回退和背景版本契约测试，确认旧代码失败。
- [ ] 切换品牌头像、组合标与动作主路径；Flow Dog 不再作为任一页面的首选或回退。
- [ ] 将 `FlowMascotPalette.brand` 同步为规格色值，但不改变现有动效与状态映射。
- [ ] 新建 `FlowV2Icon.appiconset` 与 Android `ic_trainmate_flow_v2`，更新平台配置；保留原 Flow Dog 图标文件。
- [ ] 更新 Web favicon/manifest 图标，确认透明和遮罩安全区。

### 任务 5：页面、可访问性与回归验收

**文件：**
- 修改：`test/core/trainmate_action_character_test.dart`
- 修改：`test/core/trainflow_visual_system_test.dart`
- 新建或更新：品牌头像、动作总览、登录页、今日深色页和 App 图标 Golden

- [ ] 覆盖 20 动作双版本路径、旧 Flow 回退、中文语义、背景自动选色和关闭动效静态态。
- [ ] 覆盖 `320×568`、`393×852`、`430×932`、两倍文字缩放及 `16/24/32/48px` 品牌图标。
- [ ] 运行 `flutter test --no-pub` 的品牌/Flow 定向测试与 Golden。
- [ ] 运行 `flutter analyze --no-pub` 和完整 `flutter test --no-pub`；区分本次问题与既有失败。
- [ ] 运行 `flutter build ios --simulator --no-codesign --no-pub` 与 Android Debug 构建。
- [ ] 安装到 `TrainMate Character QA`，逐页检查登录、引导、今日、计划、动作、比赛、我的和播放器；截图与旧 Flow/V2 联系表并排验收。

## 完成定义

- App 全系统使用精修后的旧 Flow，且不存在 Flow Dog 首选路径。
- 新旧轮廓差异满足量化阈值，40 张动作图和品牌导出均有真实 manifest 记录。
- 相关测试、静态分析和双平台构建均有实际执行结果；人工视觉审核状态明确。
- 原始旧 Flow、Flow Dog 和工作区其他改动均未被删除或覆盖。
