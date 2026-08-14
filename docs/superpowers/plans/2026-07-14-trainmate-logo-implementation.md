# 智练 TrainMate Logo 制作与接入实施计划

> **面向智能体执行者：** 必须使用子技能：建议使用 `superpowers:subagent-driven-development`，或使用 `superpowers:executing-plans`，逐项执行本计划。使用复选框（`- [ ]`）追踪步骤。

**目标：** 按用户正式确认的 C“角色字标同频”方向，保留深墨有机脑袋、桃色运动头带、纸白软胶囊、胶囊内 B1 左眼点／右弯眼、胶囊正下方且与胶囊保持明显留白的桃色短嘴、原创圆润中英文字标，以及桃色软结和两条不等长短飘带，完成头像、细线手脚完整角色、组合标、确定性导出链路，并在第二次矢量确认后以最小改动接入 iOS、Android 和 Web 图标。

**架构：** 采用“已封存的方向确认 + 第二次矢量确认 + 单一矢量源稿 + 确定性多平台导出”的流程。第一道方向门已由用户选择 C 并追加细线手脚与软结短飘带要求后关闭，不再运行 Logo Explorer 重新选方向；第二道门在纯净矢量主稿之后，确认完整角色、准确字标、小尺寸、飘带和单色表现。第二道门通过前，生成脚本不得覆盖现有平台图标。营销颗粒层与核心 Logo 永久分离，平台图标只从无纹理 SVG 生成。

**技术栈：** SVG、PNG、PDF、Python 3 标准库、Pillow 12.2.0、macOS `/usr/bin/sips`、Flutter 3.44.5、Dart 3.12.2、iOS Asset Catalog、Android Adaptive Icon、Web App Manifest。

## 全局约束

- 以 `docs/superpowers/specs/2026-07-14-trainmate-logo-design.md` 为唯一设计规范；核心固定元素是深墨有机头型、桃橙运动头带、纸白软胶囊、胶囊内 B1 眼点与弯眼、与胶囊下缘保持明显留白的桃色短嘴、桃色软结和两条不等长短飘带。
- 四张参考图只提供抽象风格方向，不描摹角色、字形、首字母副标、具体构图、色值或颗粒分布。
- 第一轮生成图只用于方向判断；正式字标、图形、平台图标必须来自确定性 SVG，不直接使用生成图中的文字或像素。
- 正式 SVG、App 图标、favicon 和产品内标志不含颗粒、磨损、套印偏差、阴影、发光、渐变或滤镜；营销纹理单独保存。
- 允许最小修改 `lib/core/widgets/flow_mascot.dart` 与对应的 `test/core/trainflow_visual_system_test.dart`，仅为所有现有 `FlowMascotMood` 同步桃色软结和两条短飘带；不得借机修改公开 Widget API、既有身体、面罩、双眼、配件、语义或其他动作。
- 不修改 `lib/core/theme/trainflow_tokens.dart`；应用内飘带复用现有桃色令牌。
- 不修改 Dart 包名、Bundle ID、Android application ID、存储键、应用显示名称或 Web Manifest 名称；品牌命名迁移另立任务。
- 不新增或升级 Flutter/Dart 依赖，不修改 `pubspec.yaml`、锁文件、Pod 配置、签名配置或权限配置。
- 仓库已有大量用户未提交改动。每个任务开始前检查限定路径状态，只修改本任务列出的文件；禁止 `git reset`、`git checkout --`、全项目格式化、自动提交或推送。
- 所有新增文档、代码注释、命令错误提示使用中文。
- Android SDK 当前缺失，完整 Xcode 当前未启用；不得把资源校验通过表述为 Android/iOS 原生构建通过。Web 构建是当前可完成的运行验证。
- 仓库没有 macOS、Windows 或 Linux 平台目录；本次不接入桌面图标，只在交付文档保留未来清单。

## 预期文件范围

### 新增品牌源稿与交付物

```text
assets/branding/source/
├── trainmate-flow-brandmark.svg
├── trainmate-flow-brandmark-small.svg
├── trainmate-flow-submark.svg
├── trainmate-flow-wordmark.svg
├── trainmate-flow-lockup.svg
├── trainmate-flow-character.svg
├── trainmate-flow-character-lockup.svg
├── trainmate-flow-app-icon.svg
├── trainmate-flow-app-icon-maskable.svg
└── trainmate-flow-marketing-texture.svg

assets/branding/exports/
├── png/
└── pdf/

outputs/logos/trainmate-flow/
├── reference-manifest.md
├── concepts/
├── selection.md
├── data/
│   ├── selected-logo-route.json
│   └── handoff.md
├── vector-review/
│   ├── character-128.png
│   └── character-lockup.png
└── brand-sheet.png

scripts/
├── brand_assets_manifest.json
├── generate_brand_assets.py
├── verify_brand_assets.py
└── tests/test_brand_assets.py

docs/brand/trainmate-logo-usage.md
```

`assets/branding` 不加入 Flutter `assets` 声明；它是设计源稿与发布资源的生产目录，不由运行时加载。

### 允许的应用内角色最小修改

```text
lib/core/widgets/flow_mascot.dart
test/core/trainflow_visual_system_test.dart
```

该修改遵守 `.superpowers/sdd/flow-ribbon-brief.md`：所有情绪共用同一生产几何来源，软结与两条
不等长短飘带位于深墨身体后层；跑动向后拉开，静态短幅垂落；无文字、无火焰、无尖锐长尾，
且不得产生忍者感。品牌矢量任务与应用内角色任务可以分别验证，但最终交付必须保持同一识别规则。

### 第二次矢量确认后才允许修改的平台文件

以下路径仅属于后续平台接入阶段。本轮方向文档与交接记录任务不修改其中任何文件；用户完成
第二次矢量确认前，即使通用源稿校验通过，也禁止覆盖平台资源。

```text
ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png

android/app/src/main/res/mipmap-mdpi/ic_launcher.png
android/app/src/main/res/mipmap-hdpi/ic_launcher.png
android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png
android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png
android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png
android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png
android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png
android/app/src/main/res/values/colors.xml

web/favicon.png
web/icons/Icon-192.png
web/icons/Icon-512.png
web/icons/Icon-maskable-192.png
web/icons/Icon-maskable-512.png
web/manifest.json
```

保持 `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` 和 `android/app/src/main/AndroidManifest.xml` 内容不变；实现 Android Adaptive Icon 时沿用既有 `@mipmap/ic_launcher` 名称，不增加 `roundIcon`。

---

## 任务 1：封存 C 方向确认并建立生产交接

**状态：已完成。** 用户已于 2026-07-14 选择 C“角色字标同频”，并追加细线手脚与桃色软结
短飘带要求。以下方向探索步骤仅保留为历史完成记录，不得重新运行 Logo Explorer 或回到
A/B/C 选择阶段；后续直接进入确定性矢量制作。

**文件：**

- 新建：`outputs/logos/trainmate-flow/reference-manifest.md`
- 新建：`outputs/logos/trainmate-flow/concepts/01-warm-handmade-companion.png`
- 新建：`outputs/logos/trainmate-flow/concepts/02-bold-print-companion.png`
- 新建：`outputs/logos/trainmate-flow/concepts/03-character-wordmark-family.png`
- 新建：`outputs/logos/trainmate-flow/selection.md`
- 新建：`outputs/logos/trainmate-flow/data/selected-logo-route.json`
- 新建：`outputs/logos/trainmate-flow/data/handoff.md`

**输入参考图：**

- `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.56.18.png`
- `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.57.38.png`
- `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.58.27.png`
- `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.58.59.png`

- [x] **步骤 1：确认输入完整并记录来源（历史完成记录）**

运行：

```bash
for file in \
  "/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.56.18.png" \
  "/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.57.38.png" \
  "/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.58.27.png" \
  "/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.58.59.png"; do
  test -f "$file" || { echo "缺少参考图：$file" >&2; exit 1; }
  shasum -a 256 "$file"
done
```

在 `reference-manifest.md` 记录文件名、绝对路径、SHA-256、用途“仅作风格参考”和禁止复制说明。不把参考截图复制进仓库或品牌交付目录。

- [x] **步骤 2：生成三张精修方向板（历史完成记录，不得重跑）**

使用 `creative-production:logo-explorer` 和图像生成工具，四张参考图全部作为风格输入。三个方向共用以下约束提示：

```text
为“智练 TrainMate”探索原创品牌系统。固定角色是 Flow AI 训练伙伴头像：深墨色有机头型、
桃橙色运动头带、纸白智能面罩、两只深墨眼睛；不得改成动物、食物、水果、人脸、机器人
头盔或字母图标。只吸收参考图共有的圆润手绘感、角色亲和力、有限配色和品牌系统方法；
不得复制任何参考角色轮廓、字形、首字母副标、构图、配色数值或颗粒分布。白色检查背景，
同一画面展示 Brandmark、Logotype、Lockup、Submark 和颜色关系。只使用 #19172C、
#11101F、#FFFDFC、#FFB27D、#FFE2B8。文字只作方向预览，正式字标后续确定性绘制。
```

以上提示词是历史方向生成记录，不得重跑。历史稿中的两只圆点眼已被最新规则取代：保留软胶囊，
胶囊内改用 B1 左眼点与右弯眼，桃色短嘴独立位于胶囊正下方并与胶囊下缘保持明显留白。

分别追加：

1. `01-warm-handmade-companion`：手绘感最克制，轮廓柔和、略不对称，字标圆润紧凑，推荐优先。
2. `02-bold-print-companion`：强化单色块与复古丝网印刷展示感，但核心图形区域保持干净可矢量化。
3. `03-character-wordmark-family`：强化头像与中英文字标的性格统一，角色不能替换字母或嵌入单词内部。

保存生成结果、提示词和生成时间。不得把其他品牌名称或参考图中的可颂、泪滴人物、羊、水果角色带入结果。

- [x] **步骤 3：按固定检查表淘汰不合格稿（历史完成记录）**

逐张检查：

- 不看文字时，能否理解为“AI 训练伙伴”。
- 头带、头型、软胶囊、B1 眼点与弯眼是否一眼可见。
- 是否仍属于现有 `FlowMascot` 家族。
- 是否误用了器械、箭头、对勾、心电图、`T`、`M`、`TM`。
- 是否出现与四张参考图近似的角色轮廓、字形连接或副标结构。
- 是否能在去掉纹理后形成纯色矢量主稿。

不合格方向直接重生成，不进入用户评审。

- [x] **步骤 4：封存用户第一次确认和追加要求**

用户已经选中 `C｜角色字标同频`，机器可读 ID 固定为 `character-wordmark-family`。在
`selection.md`、`selected-logo-route.json` 和 `handoff.md` 同步记录日期、保留项、需要修正项
及以下确认原文：

- `c`
- `给这个脑袋安装一样的细线手脚动作`
- `桃色头带 后面要加上感觉有一种奋斗 努力的样式`
- `flow角色上也要带着桃色软结短飘带，表达奋斗、努力`
- `主品牌上的flow角色也添加桃色软结短飘带`

选择记录必须明确：生成图中的中文字形、渐变和柔光不是正式稿；主品牌 Brandmark、Lockup、
标准角色、完整动作角色和应用内 `Flow` 都必须保留桃色软结与两条不等长短飘带。

- [x] **步骤 5：验证选择记录并做限定路径自检**

```bash
python3 -m json.tool outputs/logos/trainmate-flow/data/selected-logo-route.json
git status --short -- \
  outputs/logos/trainmate-flow/selection.md \
  outputs/logos/trainmate-flow/data/selected-logo-route.json \
  outputs/logos/trainmate-flow/data/handoff.md
git diff --check -- \
  outputs/logos/trainmate-flow/selection.md \
  outputs/logos/trainmate-flow/data/selected-logo-route.json \
  outputs/logos/trainmate-flow/data/handoff.md
```

预期：JSON 合法；本步骤只新增三份选择与交接记录，不出现平台图标变化。

---

## 任务 2：建立品牌资产契约和验证器

**文件：**

- 新建：`scripts/brand_assets_manifest.json`
- 新建：`scripts/verify_brand_assets.py`
- 新建：`scripts/tests/test_brand_assets.py`

**接口：**

- `python3 scripts/verify_brand_assets.py --platform source|exports|ios|android|web|all`
- 校验失败时返回非零退出码，并输出中文错误。

- [ ] **步骤 1：先编写会失败的验证器测试**

使用 `unittest` 和临时目录覆盖：缺少文件、PNG 尺寸错误、iOS 含 Alpha、Web Maskable 背景透明、SVG 含 `<image>`、`<filter>`、`linearGradient` 或 `<text>`、小尺寸错误引用标准源稿、平台目标引用营销纹理。

核心断言示例：

```python
def test_正式_svg_禁止嵌入位图文字滤镜和渐变(self):
    issues = validate_svg(self.svg_path)
    self.assertIn("正式 SVG 不得包含嵌入位图", issues)
    self.assertIn("正式 SVG 不得保留可变文字", issues)

def test_ios_图标必须无_alpha(self):
    issues = validate_png(self.icon_path, 1024, 1024, allow_alpha=False)
    self.assertIn("iOS 图标不得包含 Alpha 通道", issues)
```

- [ ] **步骤 2：运行测试并确认失败**

```bash
python3 -m unittest discover -s scripts/tests -p 'test_brand_assets.py'
```

预期：因 `scripts/verify_brand_assets.py` 尚不存在而失败；不得删除断言或降低校验强度。

- [ ] **步骤 3：写入单一资产清单**

`brand_assets_manifest.json` 至少包含：

```json
{
  "colors": {
    "ink": "#19172C",
    "deepInk": "#11101F",
    "paper": "#FFFDFC",
    "peach": "#FFB27D",
    "peachLight": "#FFE2B8"
  },
  "exportSizes": [24, 32, 48, 64, 128, 256, 512, 1024],
  "smallSourceMaxSize": 32,
  "androidLegacy": {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192
  },
  "androidAdaptiveForeground": {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432
  },
  "web": {
    "favicon.png": 16,
    "icons/Icon-192.png": 192,
    "icons/Icon-512.png": 512,
    "icons/Icon-maskable-192.png": 192,
    "icons/Icon-maskable-512.png": 512
  }
}
```

iOS 尺寸与文件名直接读取现有 `Contents.json`，避免维护第二份重复映射；验证器必须确认其中 19 个文件均存在、像素尺寸等于 `size × scale` 且无 Alpha。

- [ ] **步骤 4：实现验证器**

使用 Python 标准库解析 JSON/XML/SVG，使用 Pillow 读取 PNG 尺寸、模式和透明度。启动时若 Pillow 不可用，输出“缺少本机图像校验工具 Pillow；请先恢复已安装环境，不要自动修改项目依赖。”并退出，不自动安装依赖。

验证器必须：

- 校验正式 SVG 的 `viewBox`、颜色白名单，并拒绝位图、文字、滤镜、渐变和营销纹理引用。
- 校验 `brandmark-small.svg` 不包含嘴部和四肢节点；标准稿与小尺寸稿均包含 `ai-visor`、头带、
  眼点、弯眼、`headband-knot`、`ribbon-long` 和 `ribbon-short` 节点。标准稿的 `face-mouth`
  必须位于 `ai-visor` 正下方，小尺寸稿不得包含 `face-mouth`。只有 `16px` 原始像素实测出现粘连或
  裁切并留下证据时，导出器才允许生成隐藏飘带的专用 favicon。
- 校验 `character.svg` 包含 `arm-left`、`arm-right`、`leg-left`、`leg-right` 及全部飘带节点；
  `character-lockup.svg` 同时保留完整角色节点和确定性路径字标。
- 校验所有 PNG 的尺寸和 Alpha 规则。
- 校验 iOS `Contents.json`、Android 密度映射、Adaptive Icon XML 和 Web Manifest 引用。
- 校验 Web Maskable 图标为完整不透明背景，并在文档检查表中要求核心元素位于中央 80% 安全区。
- 确认平台输出哈希不等于营销纹理文件哈希，并且生成清单中没有营销纹理输入。

- [ ] **步骤 5：运行测试并做限定路径自检**

```bash
python3 -m unittest discover -s scripts/tests -p 'test_brand_assets.py'
python3 scripts/verify_brand_assets.py --help
git diff --check -- scripts/brand_assets_manifest.json scripts/verify_brand_assets.py scripts/tests/test_brand_assets.py
```

预期：单元测试通过，命令行帮助正常显示，新增脚本无空白错误。真实源稿验证留到任务 3，避免以预期失败结束本任务。

---

## 任务 3：确定性制作正式矢量品牌家族与第二次确认

**文件：**

- 新建：`assets/branding/source/trainmate-flow-brandmark.svg`
- 新建：`assets/branding/source/trainmate-flow-brandmark-small.svg`
- 新建：`assets/branding/source/trainmate-flow-submark.svg`
- 新建：`assets/branding/source/trainmate-flow-wordmark.svg`
- 新建：`assets/branding/source/trainmate-flow-lockup.svg`
- 新建：`assets/branding/source/trainmate-flow-character.svg`
- 新建：`assets/branding/source/trainmate-flow-character-lockup.svg`
- 新建：`assets/branding/source/trainmate-flow-app-icon.svg`
- 新建：`assets/branding/source/trainmate-flow-app-icon-maskable.svg`
- 新建：`assets/branding/source/trainmate-flow-marketing-texture.svg`
- 新建：`outputs/logos/trainmate-flow/vector-review/brandmark-1024.png`
- 新建：`outputs/logos/trainmate-flow/vector-review/brandmark-48.png`
- 新建：`outputs/logos/trainmate-flow/vector-review/brandmark-32.png`
- 新建：`outputs/logos/trainmate-flow/vector-review/brandmark-24.png`
- 新建：`outputs/logos/trainmate-flow/vector-review/brandmark-16.png`
- 新建：`outputs/logos/trainmate-flow/vector-review/lockup.png`
- 新建：`outputs/logos/trainmate-flow/vector-review/character-128.png`
- 新建：`outputs/logos/trainmate-flow/vector-review/character-lockup.png`

- [ ] **步骤 1：制作纯净 Brandmark 主稿**

以任务 1 已确认的 C 方向为视觉参考，从零重建 SVG 路径。使用 `viewBox="0 0 1024 1024"`；
关键元素设置稳定节点 ID：`flow-head`、`training-headband`、`headband-knot`、`ribbon-long`、
`ribbon-short`、`ai-visor`、`face-eye-dot`、`face-eye-arc`、`face-mouth`。其中 `ai-visor`
表示纸白软胶囊面部显示区，`face-mouth` 必须在胶囊正下方并保持明显垂直间隔。轮廓允许受控不对称，但不得使用
随机抖线。主品牌 Brandmark 和 Lockup 中的 `Flow` 必须保留软结及两条不等长短飘带。

标准稿只使用设计规范白名单色值。`brandmark-small.svg` 从同一结构重绘，移除 `smile`、细描边、
四肢和装饰线，放大眼点与弯眼，并保留简化软结和短飘带；不能仅依赖缩放标准稿。只有 `16px`
原始像素实测粘连或裁切时才允许隐藏飘带，并必须在选择记录中附上实测结论。

- [ ] **步骤 2：制作细线手脚完整角色**

`trainmate-flow-character.svg` 使用同一固定头像结构，并增加 `arm-left`、`arm-right`、
`leg-left` 和 `leg-right` 四个圆端细线节点。完整角色建议用于 `96px` 以上；必须保留
`headband-knot`、`ribbon-long` 和 `ribbon-short`。跑动时两条飘带向后拉开，静态时短幅垂落；
不得使用文字、火焰、尖锐长尾或会产生忍者感的姿态。

- [ ] **步骤 3：制作原创字标和两类组合标**

确定性绘制“智练 TrainMate”圆润手绘字标，所有字符转换为 SVG path：

- 中文结构不得变形为错字。
- 英文必须精确拼写 `TrainMate`，重点检查大写 `T`、`M` 与两个小写 `a`、`e`。
- 单字允许轻微宽度、高低和笔画变化，整体阅读基线与重心稳定。
- 不嵌入字体文件，不保留 `<text>` 节点，不描摹参考图字标。

`lockup.svg` 使用左头像、右字标结构；头像与文字的最小间距为头像宽度的 `0.22`，四周安全区
不小于头像宽度的 `0.18`。`trainmate-flow-character-lockup.svg` 使用左侧细线手脚完整角色和
右侧同一确定性字标，角色不得替换、嵌入或遮挡任何字符，并须保留完整软结短飘带。

- [ ] **步骤 4：制作副标、App 图标和营销纹理**

- `submark.svg` 使用完整简化头像、简化胶囊、B1 眼点与弯眼、软结和双短飘带，不使用字母或第二角色。
- `app-icon.svg` 使用浅桃完整方形底图，不预切圆角；带简化胶囊的无四肢头像及简化软结短飘带位于中央安全区。
- `app-icon-maskable.svg` 使用完整不透明浅桃背景，无四肢头像及简化软结短飘带位于中央直径
  80% 的安全圆内。
- `marketing-texture.svg` 使用原创程序化或手工颗粒，不从截图采样；文件名和元数据明确标记“不得用于平台图标”。

- [ ] **步骤 5：运行源稿契约检查**

```bash
python3 scripts/verify_brand_assets.py --platform source
```

预期：全部正式 SVG 通过；营销纹理单独通过“仅营销用途”规则，且没有被正式源稿引用。

- [ ] **步骤 6：导出小尺寸与完整角色检查图并逐一查看**

```bash
mkdir -p outputs/logos/trainmate-flow/vector-review
/usr/bin/sips -s format png -z 1024 1024 assets/branding/source/trainmate-flow-brandmark.svg --out outputs/logos/trainmate-flow/vector-review/brandmark-1024.png
/usr/bin/sips -s format png -z 48 48 assets/branding/source/trainmate-flow-brandmark.svg --out outputs/logos/trainmate-flow/vector-review/brandmark-48.png
/usr/bin/sips -s format png -z 32 32 assets/branding/source/trainmate-flow-brandmark-small.svg --out outputs/logos/trainmate-flow/vector-review/brandmark-32.png
/usr/bin/sips -s format png -z 24 24 assets/branding/source/trainmate-flow-brandmark-small.svg --out outputs/logos/trainmate-flow/vector-review/brandmark-24.png
/usr/bin/sips -s format png -z 16 16 assets/branding/source/trainmate-flow-brandmark-small.svg --out outputs/logos/trainmate-flow/vector-review/brandmark-16.png
/usr/bin/sips -s format png assets/branding/source/trainmate-flow-lockup.svg --out outputs/logos/trainmate-flow/vector-review/lockup.png
/usr/bin/sips -s format png -z 128 128 assets/branding/source/trainmate-flow-character.svg --out outputs/logos/trainmate-flow/vector-review/character-128.png
/usr/bin/sips -s format png assets/branding/source/trainmate-flow-character-lockup.svg --out outputs/logos/trainmate-flow/vector-review/character-lockup.png
```

使用图像查看工具按原始像素检查 `16/24/32/48/128/1024px`，不能只查看浏览器放大图。检查
深浅背景、单色版、胶囊边界、B1 两种眼形是否粘连、胶囊下方短嘴位置、两条飘带是否短且不等长，以及完整角色细线手脚
是否清楚。若 `16px` 隐藏飘带，必须记录粘连或裁切的原始像素证据。

- [ ] **步骤 7：请求用户完成第二次确认并暂停**

展示：App 图标 1024px、48px、32px、24px、16px favicon、独立字标、头像横向组合标、
`character-128.png`、`character-lockup.png`、副标和单色反白版。明确说明营销颗粒不会进入
平台图标，主品牌 Brandmark/Lockup 与完整角色均保留软结短飘带。

用户未确认矢量轮廓、字标拼写与小尺寸表现前，不得覆盖 iOS、Android 或 Web 现有图标。

- [ ] **步骤 8：限定路径自检**

```bash
git status --short -- assets/branding/source outputs/logos/trainmate-flow/vector-review
git diff --check -- assets/branding/source outputs/logos/trainmate-flow/vector-review
```

---

## 任务 4：实现确定性导出器与品牌交付包

**文件：**

- 新建：`scripts/generate_brand_assets.py`
- 新建：`assets/branding/exports/png/*`
- 新建：`assets/branding/exports/pdf/*`
- 新建：`outputs/logos/trainmate-flow/brand-sheet.png`

**接口：**

- `python3 scripts/generate_brand_assets.py --targets exports`
- `python3 scripts/generate_brand_assets.py --targets ios,android,web`
- `python3 scripts/generate_brand_assets.py --targets exports,ios,android,web --dry-run`

- [ ] **步骤 1：先为导出器补充失败测试**

在 `scripts/tests/test_brand_assets.py` 增加：

- `16px` favicon、`24px`、`32px` 必须选用带简化短飘带的 `brandmark-small.svg`；仅 `16px`
  有粘连或裁切实测证据时可使用隐藏飘带的专用导出。
- `48px` 及以上选用标准 Brandmark。
- `marketing-texture.svg` 不能出现在任何平台生成任务。
- `--dry-run` 只打印目标，不写文件。
- 未通过源稿验证时拒绝覆盖平台资源。

运行并确认测试先失败：

```bash
python3 -m unittest discover -s scripts/tests -p 'test_brand_assets.py'
```

- [ ] **步骤 2：实现导出器**

导出器读取 `brand_assets_manifest.json`，使用 `/usr/bin/sips` 将 SVG 栅格化，并使用 Pillow 确保颜色模式、透明度与平台规则正确。所有错误提示中文；不自动安装工具或改依赖。

执行顺序必须是：源稿验证 → 写入临时目录 → 输出文件复验 → 原子替换目标。任一输出失败时删除临时文件并保留原平台图标。

- [ ] **步骤 3：只生成通用交付物**

```bash
python3 scripts/generate_brand_assets.py --targets exports
python3 scripts/verify_brand_assets.py --platform exports
```

通用 PNG 尺寸：`24、32、48、64、128、256、512、1024px`。PDF 至少包含 Brandmark、
Wordmark、头像 Lockup、Character、Character Lockup 和 Submark。`brand-sheet.png` 展示标准版、
反白版、单色版、App 图标、字标、完整细线手脚角色、两类组合标、副标、颜色、飘带姿态和
最小尺寸；可使用独立营销纹理展示区，但必须同时展示无纹理主稿。

- [ ] **步骤 4：运行单元测试和限定路径自检**

```bash
python3 -m unittest discover -s scripts/tests -p 'test_brand_assets.py'
git diff --check -- scripts/generate_brand_assets.py scripts/tests/test_brand_assets.py assets/branding/exports outputs/logos/trainmate-flow/brand-sheet.png
```

预期：导出器测试与通用交付物校验通过，平台目录仍未变化。

---

## 任务 5：接入 iOS App Icon（第二次矢量确认后的后续阶段）

**文件：**

- 修改：`ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`（现有 19 个同名文件）
- 不修改：`ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **步骤 1：确认限定路径没有待保护的用户修改**

```bash
git status --short -- ios/Runner/Assets.xcassets/AppIcon.appiconset
git diff -- ios/Runner/Assets.xcassets/AppIcon.appiconset
```

若现有 19 个 PNG 或 `Contents.json` 已有不属于本计划的改动，停止并请求用户处理，不覆盖。

- [ ] **步骤 2：生成并验证 iOS 图标**

```bash
python3 scripts/generate_brand_assets.py --targets ios
python3 scripts/verify_brand_assets.py --platform ios
plutil -lint ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json
```

验收：19 个槽位文件齐全；像素尺寸等于 `size × scale`；全部无 Alpha；底图无预切圆角；`Contents.json` 无内容变化。

- [ ] **步骤 3：按工具链能力运行原生检查**

```bash
xcode-select -p
xcodebuild -version
```

仅当开发目录指向完整 Xcode 且 `xcodebuild -version` 成功时运行：

```bash
flutter build ios --simulator
```

当前已知开发目录为 `/Library/Developer/CommandLineTools`，预计原生构建被完整 Xcode 门槛阻塞。不得擅自切换开发目录；如实记录“图标契约通过，iOS 构建未验证”。

- [ ] **步骤 4：限定路径自检**

```bash
git diff --check -- ios/Runner/Assets.xcassets/AppIcon.appiconset
git diff --stat -- ios/Runner/Assets.xcassets/AppIcon.appiconset
git diff -- ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json
```

预期：仅 19 个 PNG 内容变化，`Contents.json` 无差异。

---

## 任务 6：接入 Android 旧式与 Adaptive Icon（第二次矢量确认后的后续阶段）

**文件：**

- 修改：五个 `mipmap-*/ic_launcher.png`
- 新建：`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- 新建：五个 `drawable-*/ic_launcher_foreground.png`
- 新建或最小追加：`android/app/src/main/res/values/colors.xml`
- 不修改：`android/app/src/main/AndroidManifest.xml`

- [ ] **步骤 1：确认限定路径没有待保护的用户修改**

```bash
git status --short -- android/app/src/main/res android/app/src/main/AndroidManifest.xml
git diff -- android/app/src/main/res android/app/src/main/AndroidManifest.xml
```

若同名图标、`colors.xml` 或 Manifest 已有不属于本计划的改动，停止并请求用户处理。

- [ ] **步骤 2：创建 Adaptive Icon 配置**

`mipmap-anydpi-v26/ic_launcher.xml` 内容固定为：

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
```

`colors.xml` 只新增：

```xml
<color name="ic_launcher_background">#FFE2B8</color>
```

若文件已存在，保留所有现有资源，只追加该唯一颜色；不要格式化其他节点。

- [ ] **步骤 3：生成并验证 Android 图标**

```bash
python3 scripts/generate_brand_assets.py --targets android
python3 scripts/verify_brand_assets.py --platform android
xmllint --noout android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
xmllint --noout android/app/src/main/AndroidManifest.xml
```

旧式图标尺寸必须是 `48、72、96、144、192px`；Adaptive 前景尺寸必须是 `108、162、216、324、432px`，透明画布内的核心固定元素处于安全区。继续沿用 `@mipmap/ic_launcher`，不新增 `roundIcon`。

- [ ] **步骤 4：按工具链能力运行原生检查**

```bash
command -v adb
command -v sdkmanager
printf '%s\n' "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
```

仅当 Android SDK、构建工具和许可均可用时运行：

```bash
flutter build apk --debug
```

当前预计因 Android SDK 缺失而阻塞。不得下载 SDK、升级 Gradle 或改构建配置；如实记录“图标契约通过，Android 构建未验证”。

- [ ] **步骤 5：限定路径自检**

```bash
git diff --check -- android/app/src/main/res android/app/src/main/AndroidManifest.xml
git diff -- android/app/src/main/AndroidManifest.xml
```

预期：Manifest 无差异；仅列出的图标和 Adaptive Icon 资源变化。

---

## 任务 7：接入 Web 图标与品牌色（第二次矢量确认后的后续阶段）

**文件：**

- 修改：`web/favicon.png`
- 修改：`web/icons/Icon-192.png`
- 修改：`web/icons/Icon-512.png`
- 修改：`web/icons/Icon-maskable-192.png`
- 修改：`web/icons/Icon-maskable-512.png`
- 修改：`web/manifest.json`

- [ ] **步骤 1：确认限定路径没有待保护的用户修改**

```bash
git status --short -- web/favicon.png web/icons web/manifest.json
git diff -- web/favicon.png web/icons web/manifest.json
```

若已有不属于本计划的改动，停止并请求用户处理。

- [ ] **步骤 2：生成 Web 图标并最小修改 Manifest**

```bash
python3 scripts/generate_brand_assets.py --targets web
```

只把 `web/manifest.json` 的颜色更新为：

```json
"background_color": "#FFE2B8",
"theme_color": "#19172C"
```

保持 `name`、`short_name`、`description`、图标路径和其他字段不变。Maskable 图标使用完整不透明浅桃底色；核心固定元素位于中央 80% 安全区。

- [ ] **步骤 3：验证 Web 资源与构建**

```bash
python3 -m json.tool web/manifest.json >/dev/null
python3 scripts/verify_brand_assets.py --platform web
flutter build web
```

预期：JSON 合法、五个图标尺寸和透明度规则通过、Web 构建成功。构建输出在 `build/web`，不纳入源文件变更总结。

- [ ] **步骤 4：限定路径自检**

```bash
git diff --check -- web/favicon.png web/icons web/manifest.json
git diff -- web/manifest.json
```

预期：Manifest 只有两处颜色值变化，名称和描述没有变化。

---

## 任务 8：完整验证、品牌使用文档与交付

**文件：**

- 新建：`docs/brand/trainmate-logo-usage.md`
- 更新：`outputs/logos/trainmate-flow/selection.md`（补充最终矢量确认与平台状态）

- [ ] **步骤 1：编写品牌使用文档**

文档必须包含：

- Brandmark、Character、Logotype、头像 Lockup、Character Lockup、Submark 的用途边界。
- 深墨、纸白、桃橙、浅桃色值。
- 头像、完整角色与两类组合标安全区，以及 `16/24/32/48/96/128px` 简化规则。
- 主品牌 Brandmark/Lockup、完整角色和应用内 `Flow` 均保留桃色软结与两条不等长短飘带；
  跑动向后拉开、静态短幅垂落的姿态规则。
- `16px` 只有原始像素实测粘连或裁切时才可隐藏飘带，并须记录证据。
- 浅色、深色、单色和错误用法。
- 营销纹理只能作为独立展示层的规则。
- 四张参考图的来源文件名、仅作风格参考说明、生成提示词记录位置。
- iOS、Android、Web 接入状态和原生工具链阻塞项。
- 桌面端仅列未来接入清单，不声称已经接入。
- 商标近似检索与法律审查尚未完成，不得表述为可直接注册。

- [ ] **步骤 2：运行资产与代码回归验证**

```bash
python3 -m unittest discover -s scripts/tests -p 'test_brand_assets.py'
python3 scripts/verify_brand_assets.py --platform all
plutil -lint ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json
xmllint --noout android/app/src/main/AndroidManifest.xml
xmllint --noout android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
python3 -m json.tool web/manifest.json >/dev/null
flutter analyze
flutter test test/core/trainflow_visual_system_test.dart --reporter compact
flutter test --reporter compact
flutter build web
git diff --check
```

只有实际运行并成功的命令才能记录为“通过”。Android/iOS 原生构建若仍被 SDK/Xcode 阻塞，单独列为“未验证”，不能混入通过项。

- [ ] **步骤 3：完成视觉验收矩阵**

逐项使用真实导出文件查看，不用浏览器缩放替代：

| 场景 | 尺寸 | 必查项 |
| --- | --- | --- |
| favicon | `16px` | 最小胶囊、眼点与弯眼不粘连；默认保留简化短飘带，仅有粘连或裁切证据时隐藏 |
| 小标 | `24px` | 使用小尺寸源稿，保留简化胶囊，无嘴部、无四肢、无纹理，简化短飘带可辨识 |
| 小标 | `32px` | 头带、简化胶囊、眼点、弯眼与简化短飘带可辨识 |
| 常用图标 | `48px` | 标准主轮廓与胶囊边界不糊，胶囊下方短嘴清楚，短飘带不裁切 |
| 完整角色 | `128px` | 细线手脚清楚，软结与两条不等长短飘带完整、圆润 |
| 角色组合标 | 原始导出 | 角色与确定性字标不遮挡，名称准确，主品牌飘带完整 |
| iPhone 图标 | `120/180px` | 安全区稳定，无预切圆角和 Alpha |
| Web 图标 | `192/512px` | 标准版与 Maskable 版均不裁切 |
| 商店主图 | `1024px` | 无多余细节，轮廓和字标风格统一 |
| 单色反白 | `128px` 以上 | 胶囊边界、B1 两种眼形、胶囊下方短嘴和头带层级不消失 |

- [ ] **步骤 4：审查最小修改边界**

```bash
git status --short
git diff --name-only
git diff --stat
git diff -- docs/superpowers/specs/2026-07-14-trainmate-logo-design.md \
  docs/superpowers/plans/2026-07-14-trainmate-logo-implementation.md \
  docs/brand/trainmate-logo-usage.md \
  lib/core/widgets/flow_mascot.dart \
  test/core/trainflow_visual_system_test.dart \
  scripts \
  web/manifest.json \
  android/app/src/main/AndroidManifest.xml \
  ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json
```

确认 `FlowMascot` 只包含已授权的软结短飘带最小修改及对应测试，没有改动公开 Widget API、
既有身体、面罩、双眼、配件、语义或其他动作；继续确认品牌令牌、包名、显示名称、权限、签名、
依赖和锁文件没有因本计划被修改。发现无关问题只记录，不顺手修复。

- [ ] **步骤 5：最终交付说明**

按以下结构汇报：

1. 最终采用的 C 角色轮廓、细线手脚、软结短飘带、字标气质和参考风格转译结果。
2. 新增与修改文件，以及每个文件的原因。
3. 实际运行的测试与结果。
4. iOS/Android 原生构建是否受工具链阻塞。
5. 原创性检查和商标近似检索仍需完成的风险。
6. 明确说明未自动提交、未推送、未修改应用技术名称，并区分本轮方向文档交接与第二次确认后
   才允许执行的平台图标替换。

本计划完成后停止，不自动执行商标注册、应用商店发布、包名迁移、应用显示名称迁移或生产部署。
