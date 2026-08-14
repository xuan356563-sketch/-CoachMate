# TrainMate 高频交互动效改进计划

审计模式：`improve-animations quick`

基线 commit：`3b541ff`

> 注意：审计时工作树已有大量用户未提交修改。执行者必须以各计划内的 current excerpt 为准核对漂移，只修改计划明确列出的文件，不覆盖其他改动。

## 快速审计结论

技术栈为 Flutter + Material 3 + GoRouter，无第三方动效库。共享动效集中在 `TrainFlowMotion`、`TrainFlowPage`、`OrganicPageHeader`、`TrainFlowCard` 和 `MainShell`。产品气质是可信、清晰、带轻量陪伴感的训练工具；高频导航应清脆，品牌趣味应留给一次性 mascot 状态反馈和低频里程碑。

| # | Severity | Category | Location | Finding | Fix summary |
| --- | --- | --- | --- | --- | --- |
| 001 | HIGH | Purpose & frequency | `lib/app/navigation/main_shell.dart:119` | Material 3 `NavigationBar` 未传时长，使用 SDK 500ms 默认值 | 复用 160ms `selection` token，并接入 reduced motion |
| 002 | HIGH | Purpose & frequency | `lib/core/widgets/trainflow_widgets.dart:33,71-81,287-298` | 约 35 个页面默认重复播放 child 入场，最大总时长 320ms | 默认关闭，高频页静态出现；仅 onboarding/毕业页 opt-in，最大 280ms |
| 003 | HIGH | Performance | `lib/core/widgets/trainflow_widgets.dart:123-170,701-734` | 五个一级页每次进入都进行 6 秒 ClipPath 逐帧重绘 | 波形改为静态，保留 mascot 的一次 transform 动效 |
| 004 | HIGH | Physicality | `lib/core/widgets/trainflow_widgets.dart:341-430` | 共享可点击卡片只有水波纹，没有即时压感 | 对可点击卡片增加 0.97/120ms 缩放反馈 |

复核时没有把 `app_router.dart:272` 的 `reverseCurve: Curves.easeInCubic` 列为问题：Flutter 的 reverse curve 输入会从 1 递减到 0，该配置在视觉上形成快速起始的退出，不应仅凭曲线名称误判。

## 计划索引

| 编号 | 标题 | Severity | Status | 依赖 |
| --- | --- | --- | --- | --- |
| 001 | [缩短底部导航选中动画](001-shorten-bottom-navigation-selection.md) | HIGH | DONE | 无 |
| 002 | [停止高频页面重复播放分区入场](002-stop-replaying-page-entrances.md) | HIGH | DONE | 无 |
| 003 | [将高频 organic header 波形改为静态](003-make-organic-header-static.md) | HIGH | DONE | 无 |
| 004 | [为可点击训练卡片增加即时按压反馈](004-add-card-press-feedback.md) | HIGH | DONE | 002（共享 ease-out token） |

## 推荐执行顺序

1. **001**：最小改动，直接修复最频繁的 500ms 导航拖尾。
2. **002**：消除高频页面的重复入场，并建立共享强 ease-out 曲线。
3. **003**：停止一级页 6 秒持续重绘，降低动效噪声和 raster 压力。
4. **004**：在前面“减法”完成后补充必要的即时按压反馈。

每完成一个计划都应单独运行其中列出的测试，不要把四项合成一次大改。

## 暂不纳入 quick 计划的机会

- 首次完成训练、达成连续训练或计划毕业时，可使用已有 mascot 做一次 420–520ms 的点赞/庆祝反馈；不要扩展到每次 tab 切换。
- 对加载完成后的数值替换可评估 150–200ms 淡入，但必须先确认真实页面是否存在明显跳变；当前仅凭代码不足以判断体感。
- 若未来加入底部抽屉或手势 dismiss，应使用可中断 spring 和速度阈值；当前高频路径没有足够证据需要新增这类交互。
