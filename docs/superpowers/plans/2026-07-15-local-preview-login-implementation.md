# TrainFlow 本地体验登录 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在短信服务不可用时，为 Flutter Debug 构建提供安全的本地体验入口。

**Architecture:** 由可覆盖的 `localPreviewEnabledProvider` 控制能力；`AuthController` 负责安全校验和本地认证状态，登录页只负责协议确认与触发。既有 GoRouter 继续只读取 `AuthStatus.authenticated`，无需新增路由旁路。

**Tech Stack:** Flutter、Dart、Riverpod、GoRouter、flutter_test

## Global Constraints

- 只在 `kDebugMode` 下启用。
- 不新增依赖，不修改后端、数据库、token 存储和生产短信认证。
- 所有新增文案、注释与错误提示使用中文。
- 保留当前工作区已有改动，不自动提交。

---

### Task 1: 本地体验认证状态

**Files:**
- Modify: `lib/features/auth/application/auth_controller.dart`
- Test: `test/features/auth/auth_controller_test.dart`

**Interfaces:**
- Produces: `localPreviewEnabledProvider`、`AuthState.isLocalPreview`、`AuthController.enterLocalPreview()`

- [x] **Step 1: 写失败测试**

增加测试覆盖：开关开启时进入本地体验并保持无 token；开关关闭时返回失败；本地体验收到 `handleSessionExpired()` 后仍保持登录。

- [x] **Step 2: 验证测试失败**

Run: `flutter test test/features/auth/auth_controller_test.dart`

Expected: 因本地体验接口尚不存在而失败。

- [x] **Step 3: 实现最小认证能力**

```dart
final localPreviewEnabledProvider = Provider<bool>((Ref ref) => kDebugMode);

Future<bool> enterLocalPreview() async {
  if (!ref.read(localPreviewEnabledProvider)) {
    _setState(_currentState.copyWith(message: '当前构建不支持本地体验'));
    return false;
  }
  _setState(const AuthState(
    status: AuthStatus.authenticated,
    user: AuthUser(
      userId: 'local-preview-user',
      sessionId: 'local-preview-session',
      phoneLast4: '本地',
      hasRequiredConsents: true,
    ),
    isLocalPreview: true,
    message: '已进入本地体验，云端功能暂不可用',
  ));
  return true;
}
```

`handleSessionExpired()` 在 `isLocalPreview` 时直接返回；`copyWith` 必须保留该字段。

- [x] **Step 4: 验证认证测试通过**

Run: `flutter test test/features/auth/auth_controller_test.dart`

Expected: 所有认证测试通过。

### Task 2: 登录页入口与路由验收

**Files:**
- Modify: `lib/features/auth/presentation/auth_pages.dart`
- Test: `test/features/auth/auth_controller_test.dart`

**Interfaces:**
- Consumes: `localPreviewEnabledProvider`、`AuthController.enterLocalPreview()`

- [x] **Step 1: 写失败 Widget 测试**

增加测试覆盖：入口可见；未勾选协议时显示错误；勾选后点击进入 `/dashboard`；覆盖开关为 `false` 时入口不可见。

- [x] **Step 2: 验证 Widget 测试失败**

Run: `flutter test test/features/auth/auth_controller_test.dart`

Expected: 因入口尚不存在而失败。

- [x] **Step 3: 实现登录页入口**

在主登录按钮下方仅当 `ref.watch(localPreviewEnabledProvider)` 为真时显示：

```dart
OutlinedButton.icon(
  key: const ValueKey<String>('local-preview-login'),
  onPressed: authState?.isBusy == true ? null : _enterLocalPreview,
  icon: const Icon(Icons.phone_iphone),
  label: const Text('进入本地体验（不含云端功能）'),
)
```

`_enterLocalPreview()` 先校验 `_agreed`；通过后调用控制器。路由重定向由现有 `AuthStatus.authenticated` 自动完成。

- [x] **Step 4: 运行局部和全量验证**

Run:

```bash
flutter test test/features/auth/auth_controller_test.dart
flutter analyze
flutter test
git diff --check
```

Expected: 测试、静态检查与空白检查全部通过。

## 执行结果

- 认证局部测试：10 项通过。
- 认证目录静态检查：0 问题。
- iPhone 17 Pro 模拟器：入口可见，协议门槛有效，点击后成功进入 Today Mission。
- 全量静态检查仍被既有 `local_storage_bootstrap_stub.dart` 缺少 `growthEvidenceRepository` 参数拦住。
- 全量测试运行 186 项，只有既有首页标题断言失败；本次认证测试全部通过。
