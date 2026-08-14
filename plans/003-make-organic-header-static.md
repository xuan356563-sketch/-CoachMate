# 003 — 将高频 organic header 波形改为静态

- **Status**: DONE
- **Commit**: `3b541ff`
- **Severity**: HIGH
- **Category**: Purpose & frequency / Performance
- **Estimated scope**: 2 files，约 35–55 行净删除

## Problem

五个一级页面都使用 `OrganicPageHeader`。每次页面创建时，header 都启动 6 秒 controller，并在每一帧重建 `ClipPath`；波形只移动约 3px，目的不清晰，却持续触发 path 计算和重绘。它还会与 520ms 左右的 mascot 变换同时运行，使高频 tab 的动效层次过多。

```dart
// lib/core/widgets/trainflow_widgets.dart:123-143 — current
class _OrganicPageHeaderState extends State<OrganicPageHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: TrainFlowMotion.headerBreath,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TrainFlowMotion.isEnabled(context)) {
      _controller.value = 0;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }
```

```dart
// lib/core/widgets/trainflow_widgets.dart:159-170 — current
return AnimatedBuilder(
  animation: _controller,
  builder: (context, child) {
    // ...
    ClipPath(
      clipper: _OrganicHeaderClipper(_controller.value),
      child: const ColoredBox(color: AppColors.primary),
    ),
```

```dart
// lib/core/widgets/trainflow_widgets.dart:707-734 — current
final double breath = math.sin(progress * math.pi * 2) * 3;
// ...
bool shouldReclip(covariant _OrganicHeaderClipper oldClipper) {
  return oldClipper.progress != progress;
}
```

## Target

保留 organic 波形的静态品牌轮廓，删除 6 秒 header controller 和逐帧 ClipPath 变化。保留 mascot 自己的一次短 `transform` 动效，因为它是品牌状态反馈，并且已有减少动态效果处理。

```dart
// target shape
class OrganicPageHeader extends StatelessWidget {
  // 现有字段和构造函数保持不变

  @override
  Widget build(BuildContext context) {
    // ...
    return SizedBox(
      key: const ValueKey<String>('trainflow-organic-header'),
      height: 170,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: const _OrganicHeaderClipper(),
              child: const ColoredBox(color: AppColors.primary),
            ),
          ),
          // 现有标题、action、artwork 布局原样保留
        ],
      ),
    );
  }
}
```

`_OrganicHeaderClipper` 不再接收 progress；使用当前 `progress == 0` 的稳定轮廓，即 `breath = 0`。`shouldReclip` 固定返回 `false`。

## Repo conventions to follow

- 角色短动效仍由 `FloatingFlowMascot` 管理，代码位于 `lib/core/widgets/flow_mascot.dart`，不要合并 controller。
- 视觉尺寸、颜色和 `trainflow-organic-header` key 保持不变，以保护现有 393×852 布局测试。
- reduced motion 对 mascot 的现有处理保持不变。

## Steps

1. 将 `OrganicPageHeader` 从 `StatefulWidget` 改为 `StatelessWidget`，删除 `_OrganicPageHeaderState`、header 的 `AnimationController`、生命周期方法和 `AnimatedBuilder`。
2. 保持 `effectiveArtwork`、170 高度、标题、subtitle、action 和 artwork 的布局完全不变。
3. 将 `_OrganicHeaderClipper` 改为无参数 `const` clipper，删除 `progress` 字段与 `sin()` 计算，令 `breath` 等效为 0，并让 `shouldReclip` 返回 `false`。
4. 从 `lib/core/theme/trainflow_tokens.dart` 删除不再使用的 `TrainFlowMotion.headerBreath`。
5. 在 `test/core/trainflow_visual_system_test.dart` 的 393×852 header 测试中，在 mascot 预期结束后的 700ms 断言 `tester.hasRunningAnimations == false`；同时保留 header key、尺寸和无布局异常断言。

## Boundaries

- Do NOT 修改 header 高度、ClipPath 控制点、颜色或人物位置。
- Do NOT 删除或减弱 `FloatingFlowMascot` 的一次性状态动效。
- Do NOT 把静态波形改成图片资源。
- Do NOT 修改其他页面组件或业务代码。
- Do NOT 新增依赖。
- 如果 header 已经有文档化的持续运动产品要求，STOP 并请求确认，不要覆盖该决策。

## Verification

- **Mechanical**:
  - `flutter test --no-pub test/core/trainflow_visual_system_test.dart test/navigation_test.dart`
  - `flutter analyze --no-pub`
  - 预期均以退出码 0 完成。
- **Feel check**:
  - 在 393×852 模拟器打开“今日成长、训练计划、动作库、比赛、我的”。
  - 波形轮廓始终稳定，不应出现 3px 上下漂移。
  - mascot 仍只播放一次短动作，约 700ms 后页面不再有持续 ticker。
  - 使用 Flutter Performance Overlay 确认切换 tab 后 raster 活动不会因 header 持续 6 秒。
  - 开启“减少动态效果”后，header 视觉构图与普通模式一致，mascot 直接显示最终帧。
- **Done when**: organic header 无 controller、无逐帧 reclip，静态轮廓与原始 `progress == 0` 完全一致，mascot 和布局测试保持通过。
