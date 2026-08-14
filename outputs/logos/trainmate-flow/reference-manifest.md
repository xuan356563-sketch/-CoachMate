# 智练 TrainMate Logo 参考来源清单

## 使用范围

本清单服务于 B1「Flow 原生头像」的第一轮风格精修。四张截图只提供抽象的视觉方法，不是
描图底稿，也不会被复制进仓库、正式 Logo 或平台图标。

本轮只产出三张真实栅格方向板，用于判断角色轮廓、手绘强度和字标气质。生成文字只作方向
预览，正式“智练 TrainMate”字标必须在用户选定方向后确定性重绘。

## 参考文件与校验值

| 文件 | SHA-256 | 风格用途 |
| --- | --- | --- |
| `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.56.18.png` | `ca424321931ed7508ad855ab0ff1ace8b96c12fa4d26577ff7b9d9c445001d09` | 圆润粗字标、角色与字标家族、独立印刷展示层 |
| `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.57.38.png` | `9733742bbeb26f4fc486a62136c07537a686c189a515283b7c5ca9cfab53f513` | 角色表情与字标同频、有限配色、软转角 |
| `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.58.27.png` | `de4a74e42ab2d8f181c8b37369b9ac31c25825a81aa51bd2e1af12fc1cadf85b` | 单色反白、多版式适配、粗印刷展示感 |
| `/Users/gaoxiaopang/Desktop/截屏2026-07-14 04.58.59.png` | `2b10b48c234ed4bf03db3b7ab93c54ec16a5b66cfe7eaa6bd756d9a61631f42a` | 角色亲和力、圆润字标、角色延展语言 |

## 必须保留的 Flow 锚点

- 非动物、单体、有机的深墨色软块头像；顶部隆起略偏左、右侧较饱满、底部宽圆。
- 桃橙色运动头带独立位于面罩上方，并且明显比面罩更宽。
- 纸白横向胶囊 AI 面罩位于头像中央。
- 两只深墨圆点眼睛只位于面罩内部。
- 三个方向统一以无嘴版本为比较基准；现有 `FlowMascot` 代码没有嘴部。
- App 图标只使用头像，不放品牌名称、口号或字母缩写。

固定颜色：

- 深墨色：`#19172C`
- 深墨描边：`#11101F`
- 纸白色：`#FFFDFC`
- 桃橙色：`#FFB27D`
- 浅桃背景：`#FFE2B8`

## 原创边界

禁止复制或近似复刻参考图中的可颂、泪滴人物、羊、水果、人物发型、四肢、首字母副标、
字形连接、角色嵌字、上下叠字、圆形徽章、具体版式、品牌色值或颗粒分布。不得在生成结果中
出现参考品牌名称。

颗粒、磨损和套印偏差只能出现在与核心 Logo 明确分开的营销展示小样中。Brandmark、App
图标、favicon 和后续正式 SVG 必须保留无纹理纯净底稿。

## 本轮方向

| ID | 名称 | 变量 | 固定不变 |
| --- | --- | --- | --- |
| `warm-handmade-companion` | A｜温暖手绘伙伴 | 克制的手绘曲率与圆润字标 | Flow 四项锚点、无嘴、固定配色 |
| `bold-print-companion` | B｜粗印训练印记 | 更强的粗实色块与单色印记 | 核心 Logo 无纹理、非动物轮廓 |
| `character-wordmark-family` | C｜角色字标同频 | 头像与中英文字标的节奏关系 | 头像完整独立，不替代任何字符 |

## 可复现信息

- Logo Explorer 规范：`data/logo-spec.json`
- 生成任务：`data/generation-jobs.jsonl`
- 生成结果状态：`concepts/codex-exec-image-results.json`
- 图像生成路径：Creative Production Codex exec 批处理器调用原生图像生成工具
- 评审背景：白色检查面
- 生成审计：`data/generation-audit.md`
- 最终评审清单：`data/review-manifest.json`
- 当前状态：三张最终方向板已通过首轮检查，等待用户选稿
