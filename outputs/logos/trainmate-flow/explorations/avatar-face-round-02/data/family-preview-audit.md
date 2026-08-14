# B1 胶囊脸与奋斗飘带品牌家族质检

## 需求范围

- 当前品牌家族图：`outputs/logos/trainmate-flow/generated/character-wordmark-family.png`
- 当前推荐预览：`generated/b1-capsule-family-ribbon-preview.png`
- 更新顶部主头像、App Icon、副标和反白组合中的脸部与头带身份元素。
- 中间独立字标、全部文字、版式、头像外轮廓与正式品牌资产不在修改范围内。

## 处理说明

原生图像生成未返回可保存的图片文件，因此没有使用失败结果。为避免中文与英文字标被生成模型重画，最终预览采用确定性局部重绘：保留四处原有机胶囊像素轮廓，只清除胶囊内的旧双圆眼；胶囊内加入 B1 左眼点与右弯眼，桃色短嘴独立放在胶囊正下方，并依据正式 SVG 的角色语法补齐桃色奋斗头带、软结和两条不等长短飘带。

## 验证结果

- 旧版品牌家族图已备份到 `outputs/logos/trainmate-flow/generated/archive/character-wordmark-family-before-b1-face.png`，SHA-256 为 `cddac56fd25c66541e68c67e852faa6632ae53d96f67c371ca23decbf391646f`。
- 无胶囊奋斗飘带历史稿已备份到 `outputs/logos/trainmate-flow/generated/archive/character-wordmark-family-before-capsule-restoration.png`，SHA-256 为 `f207fc7518007415b24478df01feca6e755f9d94b58dad12cdcce3e3ccc74ba8`。
- 嘴部下移前版本已备份到 `outputs/logos/trainmate-flow/generated/archive/character-wordmark-family-before-mouth-lower.png`，SHA-256 为 `f1c3d4d03fdb828f60044596e16b8876b60d6e05f38ac99ebed57033593b8bc0`。
- 当前品牌家族图、当前推荐预览和评审页引用的 `outputs/logos/trainmate-flow/concepts/03-character-wordmark-family.png` 已逐字节同步，SHA-256 均为 `5fdc89e03882588c2a60f3997ebd1e7757eb6314e32c7af2ad53b31faba6b56a`。
- 评审概念图旧版保存在 `outputs/logos/trainmate-flow/concepts/archive/03-character-wordmark-family-before-b1-face.png`。
- 当前品牌家族图尺寸为 `1254×1254` PNG，对应 `720×720` 评审缩略图也已同步更新。
- 允许的四个角色区域之外，像素变化数量为 `0`，因此文字、版式和右下纸张样片未变化。
- 主标、App Icon、副标和反白组合均完整保留原有胶囊轮廓，并已移除旧双圆眼残影。
- 四处胶囊内部都只包含 B1 左点眼与右弯眼；桃色短嘴全部位于胶囊外并进一步下移。主标、App Icon、Submark、Reverse 与胶囊下缘的最小间隔分别为 `16px`、`16px`、`15px`、`14px`。
- 四处均保留桃色奋斗头带、软结、上扬长尾与下垂短尾；两尾长短差清晰，没有碰撞字标或越出 App Icon 安全边。
- 反白版使用深墨胶囊、纸白眼点与弯眼、桃色胶囊下方短嘴，并保留桃色头带、软结和双短飘带。
- App Icon 已检查 `48／32／24／16px`。`24px` 仍可辨认胶囊与两种眼形；`16px` 只能作为方向缩放检查，正式生产需要单独光学校正并可移除胶囊下方短嘴。
- 原有 26 项正式 SVG、矢量评审图和品牌总表哈希校验全部通过。
- iOS、Android、Web 平台图标未修改。

## 当前边界

当前更新的是栅格品牌家族方向图，不是最终矢量资产，也没有替换应用内图标。正式 SVG、响应式小尺寸版本和平台图标仍需单独进入生产阶段。
