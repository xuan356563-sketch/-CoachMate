# 002 — 停止高频页面重复播放分区入场

- **Status**: DONE
- **Commit**: `3b541ff`
- **Severity**: HIGH
- **Category**: Purpose & frequency / Cohesion & tokens
- **Estimated scope**: 4 files，约 35–60 行

## Problem

`TrainFlowPage` 默认对每一个 child 播放淡入和 12px 上移入场。项目内约 35 个页面使用该组件，并且没有页面显式关闭 `animateChildren`。一级 tab 和常用详情页每次重建都会重播装饰性入场，高频导航因此像演示页而不是快速工具。

```dart
// lib/core/widgets/trainflow_widgets.dart:31-33 — current
this.headerVariant = TrainFlowHeaderVariant.organic,
this.includeDisclaimer = true,
this.animateChildren = true,
```

```dart
// lib/core/widgets/trainflow_widgets.dart:71-81 — current
for (int index = 0; index < children.length; index++)
  Padding(
    // ...
    child: animateChildren
        ? MotionEntrance(index: index, child: children[index])
        : children[index],
  ),
```

当前时长还把硬编码 stagger 加到 controller 总时长上；第 4 个及后续 child 的总时长达到 320ms，超过高频 UI 应保持在 300ms 内的预算。

```dart
// lib/core/widgets/trainflow_widgets.dart:287-298 — current
final int delayMs = math.min(widget.index * 40, 100);
final int totalMs = TrainFlowMotion.entrance.inMilliseconds + delayMs;
// entrance 当前为 220ms，因此 totalMs 最大为 320ms
curve: Interval(
  totalMs == 0 ? 0 : delayMs / totalMs,
  1,
  curve: Curves.easeOutCubic,
),
```

## Target

高频页面默认不播放 child 入场；只有低频、首次或庆祝页面显式开启。保留 `MotionEntrance` 作为可选能力，并把它的最大总时长控制在 280ms。

```dart
// lib/core/theme/trainflow_tokens.dart — target
static const Duration entrance = Duration(milliseconds: 200);
static const Duration cardStagger = Duration(milliseconds: 40);
static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);
```

```dart
// lib/core/widgets/trainflow_widgets.dart — target default
this.animateChildren = false,
```

```dart
// lib/core/widgets/trainflow_widgets.dart — target MotionEntrance timing
final int delayMs = math.min(
  widget.index * TrainFlowMotion.cardStagger.inMilliseconds,
  80,
);
final int totalMs = TrainFlowMotion.entrance.inMilliseconds + delayMs;
// Interval 中使用 curve: TrainFlowMotion.easeOut
```

仅在以下低频页面显式开启：

```dart
// lib/features/onboarding/onboarding_page.dart — target
animateChildren: true,

// lib/features/starter_program/starter_graduation_page.dart — target
animateChildren: true,
```

## Repo conventions to follow

- 所有时长和共享曲线放在 `lib/core/theme/trainflow_tokens.dart`。
- 减少动态效果继续使用现有 `TrainFlowMotion.isEnabled(context)`，不要另建开关。
- `MotionEntrance` 已经只动画 `Opacity` 和 `Transform.translate`，保留这一性能正确的实现方式。
- 低频页面通过已有 `TrainFlowPage.animateChildren` 参数显式选择，不创建新的页面基类。

## Steps

1. 在 `lib/core/theme/trainflow_tokens.dart` 把 `entrance` 改为 200ms；保留 `cardStagger` 为 40ms；新增 `static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);`。
2. 在 `lib/core/widgets/trainflow_widgets.dart:33` 把 `TrainFlowPage.animateChildren` 默认值改为 `false`。
3. 在 `MotionEntrance.initState()` 中用 `TrainFlowMotion.cardStagger.inMilliseconds` 代替硬编码 `40`，把 delay 上限从 100ms 改为 80ms，并把曲线改为 `TrainFlowMotion.easeOut`。
4. 在 `lib/features/onboarding/onboarding_page.dart` 的 `TrainFlowPage` 上显式设置 `animateChildren: true`。
5. 在 `lib/features/starter_program/starter_graduation_page.dart` 的 `TrainFlowPage` 上显式设置 `animateChildren: true`。
6. 在 `test/core/trainflow_visual_system_test.dart` 增加两类测试：默认 `TrainFlowPage` 不创建 `MotionEntrance`；显式 `animateChildren: true` 时会创建，并在 280ms 后结束动画。
7. 保留并运行现有“减少动态效果时内容直接显示最终状态”测试。

## Boundaries

- Do NOT 删除 `MotionEntrance`。
- Do NOT 给其他业务页面批量添加 `animateChildren: true`。
- Do NOT 改变页面 children 顺序、padding、文本或业务状态。
- Do NOT 修改路由转场、底部导航或 mascot 动效。
- Do NOT 新增依赖。
- 如果 onboarding 或 graduation 已不再使用 `TrainFlowPage`，STOP 并报告，不要寻找替代页面扩展范围。

## Verification

- **Mechanical**:
  - `flutter test --no-pub test/core/trainflow_visual_system_test.dart test/features/onboarding/onboarding_page_test.dart test/navigation_test.dart`
  - `flutter analyze --no-pub`
  - 预期均以退出码 0 完成。
- **Feel check**:
  - 在 393×852 模拟器连续切换五个一级 tab；正文应立即可读，不再逐块从下方浮入。
  - 首次进入 onboarding，children 仍以 40ms 间隔依次出现，最后一项最迟在 280ms 完成。
  - 进入毕业/庆祝页时保留一次短入场；返回再进入高频 tab 不播放装饰性 stagger。
  - 使用 Flutter Inspector 的慢速动画确认位移只有 12px，没有双重入场。
  - 开启“减少动态效果”时所有内容直接在最终位置出现。
- **Done when**: 高频页面默认静态出现，只有两个指定低频页面 opt-in，任何 child 入场总时长不超过 280ms，相关测试通过。
