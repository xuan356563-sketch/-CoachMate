# 001 — 缩短底部导航选中动画

- **Status**: DONE
- **Commit**: `3b541ff`
- **Severity**: HIGH
- **Category**: Purpose & frequency / Easing & duration
- **Estimated scope**: 2 files，约 10–20 行

## Problem

五个一级分区属于每天会触发数十次的高频交互。`NavigationBar` 没有显式传入 `animationDuration`，因此使用当前 Flutter SDK 的 500ms 默认值；页面已经完成切换后，蜜桃色选中指示器仍可能继续移动，显得拖沓。

```dart
// lib/app/navigation/main_shell.dart:119 — current
child: NavigationBar(
  height: 70,
  elevation: 0,
  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
  selectedIndex: currentIndex,
```

```dart
// /opt/homebrew/share/flutter/packages/flutter/lib/src/material/navigation_bar.dart:308 — SDK default
duration: animationDuration ?? const Duration(milliseconds: 500),
```

项目已经定义了专用于选择反馈的 160ms token，但当前没有被底部导航使用：

```dart
// lib/core/theme/trainflow_tokens.dart:29 — current
static const Duration selection = Duration(milliseconds: 160);
```

## Target

让底部导航选中动画使用已有的 `TrainFlowMotion.selection`，正常动态效果为 160ms；系统开启“减少动态效果”时为 `Duration.zero`。

```dart
// target
child: NavigationBar(
  animationDuration: TrainFlowMotion.resolve(
    context,
    TrainFlowMotion.selection,
  ),
  height: 70,
  elevation: 0,
  // 其余属性保持不变
)
```

不要修改导航结构、标签、图标、路由或选中颜色。

## Repo conventions to follow

- 动效时长集中在 `lib/core/theme/trainflow_tokens.dart` 的 `TrainFlowMotion`。
- 减少动态效果统一通过 `TrainFlowMotion.resolve(context, duration)` 处理。
- `lib/app/navigation/main_shell.dart` 已经导入 `trainflow_tokens.dart`，不需要新增 import。

## Steps

1. 在 `lib/app/navigation/main_shell.dart:119` 的 `NavigationBar` 上增加 `animationDuration`，值严格使用上面的 target 代码。
2. 在 `test/navigation_test.dart` 增加断言：正常 `MediaQuery` 下 `navigationBar(tester).animationDuration == TrainFlowMotion.selection`。
3. 在同一测试文件增加减少动态效果场景，确认 `animationDuration == Duration.zero`；复用现有 `TrainFlowApp` 和 `TestHarness`，不要新建测试框架。

## Boundaries

- Do NOT 修改五个一级分区、路由路径或 `selectedIndex` 逻辑。
- Do NOT 修改 Flutter SDK 文件。
- Do NOT 新增依赖。
- Do NOT 顺带修改路由页转场或页面卡片入场；它们由其他计划负责。
- 如果代码与上述 excerpt 不一致，STOP 并报告漂移，不要自行改造。

## Verification

- **Mechanical**:
  - `flutter test --no-pub test/navigation_test.dart`
  - `flutter analyze --no-pub`
  - 预期均以退出码 0 完成。
- **Feel check**:
  - 在 393×852 模拟器上连续点击“今日成长 → 训练计划 → 动作库 → 比赛 → 我的”。
  - 选中指示器必须在 160ms 内跟上点击，不能在页面稳定后继续滑动。
  - 快速来回点击两个 tab，动画应重定向到新目标，不能出现明显尾随。
  - 开启 iOS“减少动态效果”后，指示器立即更新，但颜色和选中状态仍清晰可辨。
- **Done when**: `NavigationBar.animationDuration` 在正常模式为 160ms、减少动态效果时为 0ms，导航测试与静态检查通过。
