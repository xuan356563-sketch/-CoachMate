# 004 — 为可点击训练卡片增加即时按压反馈

- **Status**: DONE
- **Commit**: `3b541ff`
- **Severity**: HIGH
- **Category**: Physicality & origin / Missed opportunities
- **Estimated scope**: 2 files，约 45–75 行

## Problem

`TrainFlowCard` 是全局共享卡片，项目中约有 177 个调用点，其中部分通过 `onTap` 承担训练、计划、动作和数据入口。当前只有 `InkWell` 水波纹，没有按下时的物理压缩反馈；在深色描边和大面积卡片上，水波纹的即时感较弱。

```dart
// lib/core/widgets/trainflow_widgets.dart:341-361 — current
class TrainFlowCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  // ...
}
```

```dart
// lib/core/widgets/trainflow_widgets.dart:399-408 — current
final Widget card = Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Material(
    // ...
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TrainFlowTokens.cardRadius),
      child: Container(
```

项目已经定义了 120ms button token，但当前没有用于卡片按压：

```dart
// lib/core/theme/trainflow_tokens.dart:28 — current
static const Duration button = Duration(milliseconds: 120);
```

## Target

仅当 `onTap != null` 时，按压卡片缩放到 `0.97`，释放后回到 `1.0`；时长严格为 120ms，曲线使用强 ease-out `Cubic(0.23, 1, 0.32, 1)`。减少动态效果开启时不缩放，但保留 InkWell 的颜色/水波纹反馈。

```dart
// target interaction state
bool _pressed = false;

final bool motionEnabled = TrainFlowMotion.isEnabled(context);
final double scale = onTap != null && motionEnabled && _pressed ? 0.97 : 1;

AnimatedScale(
  scale: scale,
  duration: TrainFlowMotion.resolve(context, TrainFlowMotion.button),
  curve: TrainFlowMotion.easeOut,
  child: Material(
    child: InkWell(
      onTap: onTap,
      onHighlightChanged: onTap == null
          ? null
          : (bool highlighted) {
              if (_pressed != highlighted) {
                setState(() => _pressed = highlighted);
              }
            },
      // 其余现有属性保持不变
    ),
  ),
)
```

`TrainFlowMotion.easeOut` 应复用计划 002 定义的：

```dart
static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);
```

## Repo conventions to follow

- 时长使用现有 `TrainFlowMotion.button`，不要新增重复 token。
- 曲线复用 `TrainFlowMotion.easeOut`；本计划依赖计划 002。
- 保留 `Material`、`InkWell`、圆角和 clip，按压缩放是对现有触控反馈的补充，不是替代。
- 减少动态效果继续通过 `TrainFlowMotion.isEnabled/resolve` 处理。

## Steps

1. 确认计划 002 已完成并存在 `TrainFlowMotion.easeOut`；若不存在，STOP，不要在本计划重复定义。
2. 将 `TrainFlowCard` 转为 `StatefulWidget`，保持所有公开构造参数、默认值和调用方式兼容。
3. 增加私有 `_pressed` 状态；只在 `onTap != null` 时响应 `InkWell.onHighlightChanged`。
4. 在 `Material` 外包一层 `AnimatedScale`，严格使用 target 中的 0.97、120ms、`TrainFlowMotion.easeOut` 和 reduced-motion 分支。
5. 在 `didUpdateWidget` 中处理从可点击变为不可点击的情况：如果新 `onTap == null`，把 `_pressed` 重置为 `false`，避免复用 widget 时残留缩放。
6. 在 `test/core/trainflow_visual_system_test.dart` 增加测试：可点击卡片按下后 target scale 为 0.97，释放后为 1；不可点击卡片始终为 1；减少动态效果下按压仍为 1。

## Boundaries

- Do NOT 改变 `TrainFlowCard` 的公开参数、padding、颜色、边框或圆角。
- Do NOT 给不可点击卡片增加缩放或手势状态。
- Do NOT 删除 InkWell 水波纹。
- Do NOT 在业务页面逐个包裹 GestureDetector；修复必须留在共享组件。
- Do NOT 新增依赖或 spring 库。
- 如果计划 002 未提供共享曲线，STOP 并先执行依赖计划。

## Verification

- **Mechanical**:
  - `flutter test --no-pub test/core/trainflow_visual_system_test.dart test/navigation_test.dart test/features/dashboard/today_training_page_test.dart`
  - `flutter analyze --no-pub`
  - 预期均以退出码 0 完成。
- **Feel check**:
  - 在 393×852 模拟器按住一个可点击训练卡片，卡片应在 120ms 内轻微压到 0.97，文字和图标同步缩放。
  - 松手后立即回到 1.0；快速点按不会卡在缩小状态。
  - 滚动 ListView 时手指掠过卡片，不应误触或残留缩放。
  - 不可点击的信息卡片不应产生“可操作”的缩放暗示。
  - 开启“减少动态效果”后不发生位移/缩放，但 InkWell 反馈仍可见。
- **Done when**: 所有 `onTap != null` 的 `TrainFlowCard` 具有 0.97/120ms 按压反馈，不可点击和 reduced-motion 场景保持 scale 1，测试通过。
