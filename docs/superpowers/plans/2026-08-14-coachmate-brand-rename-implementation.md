# 练搭 CoachMate 品牌改名实施计划

> **供执行代理使用：** 实施本计划时必须使用 `superpowers:executing-plans`；只有用户明确要求子代理并行执行时，才改用 `superpowers:subagent-driven-development`。所有步骤使用复选框跟踪。

**目标：** 将 App、通知、验证码邮件及 iOS／Android／Web 用户可见品牌从“智练 TrainMate／TrainMate”直接切换为“练搭 CoachMate／练搭”，并在登录品牌区显示“练，有人陪。”，同时保持既有应用身份、订阅标识和本地数据兼容。

**架构：** Flutter 端新增无业务逻辑的 `AppBrand` 常量作为唯一品牌文案来源；无法引用 Dart 常量的平台配置和 Python 邮件模板由跨端契约测试约束。现有 `TrainMate*` 类型、资产路径、Bundle ID、applicationId、数据库、HealthKit 存储键及 StoreKit 产品 ID 全部保持不变。

**技术栈：** Flutter／Dart、Riverpod、Flutter Widget Test、Python／pytest、iOS Info.plist／StoreKit、Android Manifest、Web Manifest／HTML。

## 全局约束

- [ ] 修改前保存 `git status --short` 输出，识别并避开用户已有改动；本任务不得覆盖或清理无关文件。
- [ ] 不新增依赖，不升级 Flutter、Dart、Python、Gradle、CocoaPods 或锁文件。
- [ ] 不修改 `com.zhilian.trainmate`、`trainflow_ai`、SQLite schema／迁移版本、`TrainMateHealthKit`、`TRAINMATE_*`、StoreKit `productID` 或内部 `referenceName`。
- [ ] 不删除、覆盖或重命名包含旧文字的历史图片；只停止在运行时展示旧组合标。
- [ ] 不修改图标、角色、颜色、页面结构、底部导航或业务流程。
- [ ] 不夹带“删除消息记录”“收起键盘”或其他功能修改。
- [ ] 不执行数据库迁移、SQLite／Alembic 降级、Git 提交或推送；如需提交，必须由用户另行明确授权。
- [ ] 所有失败都记录实际命令和输出；不得通过删除测试或降低断言强度制造通过结果。

---

## 任务 1：建立 Flutter 品牌常量与基础契约

**文件：**

- 新建：`lib/core/constants/app_brand.dart`
- 新建：`test/core/app_brand_contract_test.dart`

### 步骤 1：先写品牌常量失败测试

- [ ] 创建 `test/core/app_brand_contract_test.dart`，先只覆盖四个已确认值：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:trainflow_ai/core/constants/app_brand.dart';

void main() {
  group('AppBrand', () {
    test('品牌名称与口号固定为已确认值', () {
      expect(AppBrand.displayName, '练搭 CoachMate');
      expect(AppBrand.shortName, '练搭');
      expect(AppBrand.englishName, 'CoachMate');
      expect(AppBrand.tagline, '练，有人陪。');
    });

    test('Web 描述体现本地优先与长期陪伴定位', () {
      expect(
        AppBrand.webDescription,
        '练搭 CoachMate：本地优先的 AI Coach agent 与运动搭子，陪你长期训练。',
      );
    });
  });
}
```

- [ ] 运行：

```bash
scripts/run_flutter_tests_clean_copy.sh test/core/app_brand_contract_test.dart --reporter compact
```

预期：因 `app_brand.dart` 尚不存在而失败；失败原因只能是缺少品牌常量文件或符号。

### 步骤 2：实现最小品牌常量

- [ ] 新建 `lib/core/constants/app_brand.dart`：

```dart
abstract final class AppBrand {
  static const String displayName = '练搭 CoachMate';
  static const String shortName = '练搭';
  static const String englishName = 'CoachMate';
  static const String tagline = '练，有人陪。';
  static const String webDescription =
      '练搭 CoachMate：本地优先的 AI Coach agent 与运动搭子，陪你长期训练。';
}
```

- [ ] 重新运行任务 1 测试，预期全部通过。
- [ ] 运行 `dart format lib/core/constants/app_brand.dart test/core/app_brand_contract_test.dart`，确保格式化没有触及其他文件。
- [ ] 检查 `git diff -- lib/core/constants/app_brand.dart test/core/app_brand_contract_test.dart`，确认只有品牌契约与测试。

---

## 任务 2：切换 Flutter 应用标题、登录品牌区和协议展示

**文件：**

- 修改：`lib/app/trainflow_app.dart`
- 修改：`lib/core/widgets/trainmate_branding.dart`
- 修改：`lib/features/auth/presentation/auth_pages.dart`
- 修改：`lib/features/auth/data/authenticated_api_client.dart`
- 修改：`test/core/trainflow_visual_system_test.dart`
- 修改：`test/features/auth/auth_controller_test.dart`

### 步骤 1：先更新登录与组合标测试

- [ ] 在 `test/features/auth/auth_controller_test.dart` 的未登录拦截用例中，将断言改为：

```dart
expect(find.text('登录练搭 CoachMate'), findsOneWidget);
expect(find.text('登录并进入练搭 CoachMate'), findsOneWidget);
expect(find.text(AppBrand.tagline), findsOneWidget);
expect(
  tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
  AppBrand.displayName,
);
```

- [ ] 保留 `trainmate-brand-lockup`、`trainmate-brandmark` Key 的兼容断言；这些是测试与组件内部标识，不属于用户可见名称。
- [ ] 在 `test/core/trainflow_visual_system_test.dart` 将“旧组合标图片”用例改成“头像＋文本组合标”用例，断言：
  - 存在 `trainmate-brand-lockup` 和 `trainmate-brandmark`；
  - 显示 `AppBrand.displayName` 和 `AppBrand.tagline`；
  - 393px 宽度下无溢出；
  - 组合标子树中不存在使用 `TrainMateBrandAssets.lockup` 的 `Image`。
- [ ] 运行：

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/features/auth/auth_controller_test.dart \
  test/core/trainflow_visual_system_test.dart \
  --reporter compact
```

预期：旧实现仍显示“智练 TrainMate”图片和文案，因此新断言失败；原有无关断言不应新增失败。

### 步骤 2：把应用标题改为集中常量

- [ ] 在 `lib/app/trainflow_app.dart` 引入 `AppBrand`，将：

```dart
title: '智练 TrainMate',
```

替换为：

```dart
title: AppBrand.displayName,
```

### 步骤 3：将运行时组合标改为头像＋文本

- [ ] 在 `lib/core/widgets/trainmate_branding.dart` 引入 `AppBrand`。
- [ ] 保留 `TrainMateBrandAssets.lockup` 和 `legacyLockup` 常量及旧图片文件，避免破坏历史资产引用；`TrainMateBrandLockup.build` 不再读取二者。
- [ ] `TrainMateBrandLockup` 使用已有 `TrainMateBrandmark` 和 Flutter 文本组合，保持现有类名、构造参数和 Key：

```dart
return Semantics(
  label: '${AppBrand.displayName}，${AppBrand.tagline}',
  child: SizedBox(
    key: const ValueKey<String>('trainmate-brand-lockup'),
    height: height,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TrainMateBrandmark(size: height * 0.56),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(AppBrand.displayName),
              Text(AppBrand.tagline),
            ],
          ),
        ],
      ),
    ),
  ),
);
```

- [ ] 文字样式只复用当前主题的 `titleLarge`／`bodyMedium` 和现有品牌色，不引入新字体、阴影或布局体系。
- [ ] 将 `TrainMateBrandmark` 的无障碍名称改为“练搭 CoachMate 品牌头像”；加载失败时继续回退至不含旧文字的头像资源。

### 步骤 4：更新登录、协议和连接错误文案

- [ ] `lib/features/auth/presentation/auth_pages.dart` 统一使用：
  - 页面标题：`登录${AppBrand.displayName}`；
  - 登录按钮：`登录并进入${AppBrand.displayName}`；
  - 协议内部测试说明：`本协议仅用于${AppBrand.displayName}内部测试……`；
  - 协议页 eyebrow：`AppBrand.displayName`；
  - 登录组合标内显示 `AppBrand.tagline`，不在页面其他位置重复添加口号。
- [ ] `lib/features/auth/data/authenticated_api_client.dart` 的服务连接错误改为“无法连接练搭 CoachMate 服务，请检查后端是否已启动”，网络错误类型和处理流程保持不变。
- [ ] 重新运行任务 2 的两个测试文件，预期全部通过且 393px 组合标无溢出。
- [ ] 运行：

```bash
dart format \
  lib/app/trainflow_app.dart \
  lib/core/widgets/trainmate_branding.dart \
  lib/features/auth/presentation/auth_pages.dart \
  lib/features/auth/data/authenticated_api_client.dart \
  test/core/trainflow_visual_system_test.dart \
  test/features/auth/auth_controller_test.dart
```

---

## 任务 3：切换 Flutter 其余用户可见文案与本地通知

**文件：**

- 修改：`lib/core/widgets/trainmate_action_character.dart`
- 修改：`lib/services/system_training_notification_service.dart`
- 修改：`lib/services/four_week_plan_generator.dart`
- 修改：`lib/features/first_run_onboarding/presentation/first_run_pages.dart`
- 修改：`lib/features/data_center/data_center_page.dart`
- 修改：`lib/features/training_plan/plan_generation_page.dart`
- 修改：`lib/features/workout_player/application/workout_player_assist_controller.dart`
- 修改：`lib/features/companion/application/companion_controller.dart`
- 修改：`lib/features/companion/application/companion_notification_scheduler.dart`
- 修改：`lib/app/startup/local_storage_recovery_page.dart`
- 修改：`test/services/system_training_notification_service_test.dart`
- 修改：`test/features/companion/application/companion_notification_scheduler_test.dart`
- 修改：`test/features/first_run_onboarding/membership_welcome_page_test.dart`
- 修改：`test/features/training_plan/plan_generation_page_test.dart`
- 修改：`test/features/workout_player/application/workout_player_assist_controller_test.dart`

### 步骤 1：先补齐通知和页面文案断言

- [ ] 在 `test/services/system_training_notification_service_test.dart` 的调度成功用例增加：

```dart
expect(gateway.requests.first.body, '打开练搭查看今日安排。');
```

- [ ] 将伙伴通知测试中的 L0 标题从 `TrainMate` 改为 `AppBrand.shortName`，保留“你的运动搭子有一条新消息。”和深链断言不变。
- [ ] 在会员欢迎页测试断言 `练搭 CoachMate 月度会员`。
- [ ] 在计划生成页测试断言提示包含“练搭 CoachMate 不复制 PAR-Q+ 题目”。
- [ ] 在常亮不支持测试中断言状态文案包含“使用练搭 CoachMate App”。
- [ ] 运行：

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/services/system_training_notification_service_test.dart \
  test/features/companion/application/companion_notification_scheduler_test.dart \
  test/features/first_run_onboarding/membership_welcome_page_test.dart \
  test/features/training_plan/plan_generation_page_test.dart \
  test/features/workout_player/application/workout_player_assist_controller_test.dart \
  --reporter compact
```

预期：品牌相关新断言失败；通知权限、隐私、深链、调度及训练安全的既有断言继续通过。

### 步骤 2：按场景使用正式名称或短名称

- [ ] 引入 `AppBrand` 并逐项替换用户可见字符串：

| 文件／场景 | 新文案规则 |
| --- | --- |
| 动作人物默认无障碍名称 | `${AppBrand.displayName} ${action.label}动作人物` |
| 系统训练通知正文 | `打开${AppBrand.shortName}查看今日安排。` |
| 四周计划安全说明 | `动作、负荷与安全边界均由${AppBrand.displayName}决定。` |
| 首次引导年龄提示 | `${AppBrand.displayName}目前仅向18岁以上用户开放` |
| 会员 eyebrow | `${AppBrand.displayName}月度会员` |
| 数据删除警告 | `这会删除${AppBrand.displayName}本地保存的身体记录和修订历史，且无法撤销。` |
| PAR-Q+ 说明 | `${AppBrand.displayName}不复制 PAR-Q+ 题目……` |
| 屏幕常亮提示 | `……或使用${AppBrand.displayName} App。` |
| 伙伴 L0 通知标题 | `AppBrand.shortName` |
| 伙伴通知回退正文 | `打开${AppBrand.shortName}查看搭子消息。` |
| 本地存储诊断标题 | `${AppBrand.displayName}本地存储诊断` |

- [ ] 同步把 `trainmate_action_character.dart` 中描述当前用户品牌的注释改为“练搭 CoachMate 固定动作资产”；类名、枚举名和资源目录继续保留 `TrainMate`。
- [ ] `companion_controller.dart` 生成的中性通知标题改为 `AppBrand.shortName`；角色自行命名的非敏感通知仍使用“衡衡狸”等伙伴名，不改变隐私仲裁。
- [ ] 不修改通知 ID、权限请求、时区、取消重排、L0/L1/L2 或深链逻辑。
- [ ] 不修改训练计划、安全阈值、PAR-Q+ 外链、数据删除范围或屏幕常亮平台调用。
- [ ] 重新运行任务 3 的五个测试文件，预期全部通过。

### 步骤 3：加入用户可见源码残留保护

- [ ] 扩展 `test/core/app_brand_contract_test.dart`，对任务 2、任务 3 的用户可见源码文件逐个读取，断言不再包含以下旧展示文案：
  - `智练 TrainMate`；
  - 单引号或双引号内的 `TrainMate` 用户文案；
  - `打开 TrainMate`；
  - `使用 TrainMate App`。
- [ ] 白名单保留类名、Key、文件名、资产路径、算法名和注释中的内部兼容标识；禁止写成“全仓不含 TrainMate”的破坏性断言。
- [ ] 运行任务 1 品牌契约测试和任务 3 聚焦测试，预期全部通过。

---

## 任务 4：同步 iOS、Android、Web 和 StoreKit 元数据

**文件：**

- 修改：`ios/Runner/Info.plist`
- 修改：`ios/StoreKit/TrainMate.storekit`
- 修改：`android/app/src/main/AndroidManifest.xml`
- 修改：`web/manifest.json`
- 修改：`web/index.html`
- 修改：`test/core/ios_release_identity_test.dart`
- 修改：`test/core/app_brand_contract_test.dart`

### 步骤 1：先写跨端元数据失败测试

- [ ] 在 `test/core/ios_release_identity_test.dart` 保留现有 Bundle ID 次数、RunnerTests ID 和签名团队断言，并新增：
  - `CFBundleDisplayName` 为“练搭 CoachMate”；
  - `CFBundleName` 为“练搭 CoachMate”；
  - `project.pbxproj` 仍有三处 `com.zhilian.trainmate` 和三处 `com.zhilian.trainmate.RunnerTests`。
- [ ] 在 `test/core/app_brand_contract_test.dart` 使用 `dart:io`／`dart:convert` 读取平台配置并断言：
  - Android `android:label="练搭 CoachMate"`；
  - Android `applicationId = "com.zhilian.trainmate"` 与 namespace 不变；
  - Web Manifest `name` 为正式名称、`short_name` 为“练搭”、描述为 `AppBrand.webDescription`；
  - Web HTML 的 description、Apple Web App title 和 `<title>` 全部为新品牌；
  - StoreKit 中文会员名为“练搭 CoachMate 会员”，组名为“CoachMate Membership”；
  - StoreKit `productID` 仍为 `com.zhilian.trainmate.membership.monthly`，`referenceName` 仍为 `TrainMate Monthly`。
- [ ] 运行：

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/core/app_brand_contract_test.dart \
  test/core/ios_release_identity_test.dart \
  --reporter compact
```

预期：用户可见元数据仍为旧品牌，因此新断言失败；兼容标识保护断言通过。

### 步骤 2：修改平台展示值

- [ ] `ios/Runner/Info.plist`：`CFBundleDisplayName` 和 `CFBundleName` 改为“练搭 CoachMate”。
- [ ] `ios/StoreKit/TrainMate.storekit`：
  - `displayName` 改为“练搭 CoachMate 会员”；
  - 订阅组 `name` 改为“CoachMate Membership”；
  - 不修改 `productID`、`referenceName`、内部 ID、价格或周期。
- [ ] `android/app/src/main/AndroidManifest.xml`：只把 `android:label` 改为“练搭 CoachMate”。
- [ ] `web/manifest.json`：
  - `name` 改为“练搭 CoachMate”；
  - `short_name` 改为“练搭”；
  - `description` 改为确认后的 Web 描述。
- [ ] `web/index.html`：同步 description、Apple Web App title 和 `<title>`，不修改 base href、脚本、图标或缓存配置。
- [ ] 重新运行任务 4 两个测试文件，预期全部通过。
- [ ] 分别执行：

```bash
plutil -lint ios/Runner/Info.plist
python3 -m json.tool ios/StoreKit/TrainMate.storekit >/dev/null
python3 -m json.tool web/manifest.json >/dev/null
```

预期：三个配置文件语法检查均返回退出码 0。

---

## 任务 5：切换登录验证码邮件品牌

**文件：**

- 修改：`backend/app/services/email_provider.py`
- 修改：`backend/tests/test_email_provider.py`

### 步骤 1：先写邮件品牌失败断言

- [ ] 在 `test_smtp_provider_uses_starttls_and_sends_plain_text_code` 中新增：

```python
assert client.sent_message["Subject"] == "练搭 CoachMate 登录验证码"
content = client.sent_message.get_content()
assert "你正在登录练搭 CoachMate。" in content
assert "智练 TrainMate" not in content
```

- [ ] 运行：

```bash
backend/.venv/bin/python -m pytest backend/tests/test_email_provider.py -q
```

预期：新主题或正文断言失败；SMTP TLS、账号、收件人和供应商错误脱敏断言继续通过。

### 步骤 2：实现邮件模板最小替换

- [ ] 在 `backend/app/services/email_provider.py` 定义文件内私有常量并复用：

```python
_PRODUCT_DISPLAY_NAME = "练搭 CoachMate"
```

- [ ] 邮件主题使用 `f"{_PRODUCT_DISPLAY_NAME} 登录验证码"`，正文使用 `f"你正在登录{_PRODUCT_DISPLAY_NAME}。\n\n"`。
- [ ] 不修改发件人、认证接口、验证码有效期、SMTP 配置、错误码或异常脱敏。
- [ ] 重新运行任务 5 测试，预期全部通过。

---

## 任务 6：格式化、静态扫描与聚焦回归

**文件：** 本计划全部 Dart／Python 修改文件及其测试。

### 步骤 1：只格式化任务文件

- [ ] 对本任务修改的 Dart 文件显式运行 `dart format <文件列表>`；不得运行覆盖全仓的机械格式化。
- [ ] 运行 Python 格式检查而不自动改写无关文件：

```bash
backend/.venv/bin/python -m ruff check \
  --config backend/pyproject.toml \
  backend/app/services/email_provider.py \
  backend/tests/test_email_provider.py
```

预期：退出码 0；若为既有规则问题，只修复这两个任务文件。

### 步骤 2：执行全部品牌聚焦测试

- [ ] 运行：

```bash
scripts/run_flutter_tests_clean_copy.sh \
  test/core/app_brand_contract_test.dart \
  test/core/ios_release_identity_test.dart \
  test/core/trainflow_visual_system_test.dart \
  test/features/auth/auth_controller_test.dart \
  test/services/system_training_notification_service_test.dart \
  test/features/companion/application/companion_notification_scheduler_test.dart \
  test/features/first_run_onboarding/membership_welcome_page_test.dart \
  test/features/training_plan/plan_generation_page_test.dart \
  test/features/workout_player/application/workout_player_assist_controller_test.dart \
  --reporter compact
```

预期：全部通过；报告实际测试数量和耗时，不使用历史结果替代。

- [ ] 运行后端聚焦测试：

```bash
backend/.venv/bin/python -m pytest backend/tests/test_email_provider.py -q
```

预期：全部通过。

### 步骤 3：执行品牌残留和兼容标识复核

- [ ] 执行用户可见范围扫描：

```bash
rg -n "智练 TrainMate|打开 TrainMate|使用 TrainMate App" \
  lib/app \
  lib/core/widgets \
  lib/features/auth \
  lib/features/first_run_onboarding \
  lib/features/data_center \
  lib/features/training_plan \
  lib/features/workout_player \
  lib/features/companion \
  lib/services \
  ios/Runner/Info.plist \
  ios/StoreKit/TrainMate.storekit \
  android/app/src/main/AndroidManifest.xml \
  web/index.html \
  web/manifest.json \
  backend/app/services/email_provider.py
```

预期：没有用户可见旧品牌匹配；若出现内部注释或类型名，逐项确认其不进入 UI 后加入明确白名单，不做批量替换。

- [ ] 执行兼容标识扫描并人工核对：

```bash
rg -n "com\.zhilian\.trainmate|TrainMateHealthKit|TRAINMATE_|TrainMate Monthly" \
  ios android lib backend
```

预期：既有 Bundle／applicationId、HealthKit／安全存储键、环境变量和 StoreKit 内部 referenceName 仍存在，且没有被替换成新名称。

- [ ] 运行 `git diff --check`，预期没有尾随空格或补丁格式错误。
- [ ] 运行 `git diff --stat` 和逐文件 `git diff -- <任务文件>`，确认没有数据库、路由、业务规则、图标、锁文件或无关功能改动。

---

## 任务 7：完整检查、构建与 iOS 模拟器验收

**文件：** 不再新增业务文件；只生成临时构建产物和模拟器截图。

### 步骤 1：静态分析与完整测试

- [ ] 运行外置卷安全的完整检查：

```bash
scripts/run_flutter_analyze_clean_copy.sh
scripts/run_flutter_tests_clean_copy.sh --reporter compact
backend/.venv/bin/python -m pytest backend/tests --disable-warnings -q
```

预期：以本次真实输出为准。若存在任务前已知失败，记录测试名、错误和与品牌改名无关的证据；不得修改无关功能掩盖失败。

### 步骤 2：Web 构建验证

- [ ] 运行：

```bash
flutter build web --no-pub
```

预期：构建成功，`build/web/index.html` 与 `build/web/manifest.json` 使用新品牌；若环境缺少 Web 工具链，如实记录阻塞，不声称通过。

### 步骤 3：iOS 模拟器构建与安装

- [ ] 确认已启动设备：

```bash
xcrun simctl list devices booted
```

- [ ] 构建并检查应用身份：

```bash
flutter build ios --simulator --no-pub
plutil -p build/ios/iphonesimulator/Runner.app/Info.plist | \
  rg "CFBundleDisplayName|CFBundleName|CFBundleIdentifier"
```

预期：显示名称／Bundle 名为“练搭 CoachMate”，Bundle ID 仍为 `com.zhilian.trainmate`。

- [ ] 安装并启动同一 Bundle ID：

```bash
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted com.zhilian.trainmate
```

预期：安装和启动成功，没有生成第二个应用身份。

### 步骤 4：人工视觉与功能复核

- [ ] 在登录页确认：
  - 标题为“登录练搭 CoachMate”；
  - 品牌区显示不含旧文字的头像、“练搭 CoachMate”和“练，有人陪。”；
  - 页面没有“智练 TrainMate”旧组合标；
  - 393px 宽度无溢出，中文字体未截断。
- [ ] 进入本地体验，依次打开“伙伴／今日／动作库／我的”，确认路由、内容、本地数据和四栏导航均未因改名受影响。
- [ ] 验证服务协议和隐私政策可访问，品牌名称已更新，内容边界没有改变。
- [ ] 通过现有调试入口触发训练提醒与伙伴 L0 通知，确认标题为“练搭”，隐私正文与深链行为不变。
- [ ] 保存截图：

```bash
xcrun simctl io booted screenshot /tmp/coachmate-brand-rename.png
```

预期：截图可用于人工核对，但截图本身不替代自动化测试或构建证据。

### 步骤 5：最终交付报告

- [ ] 按“修改了什么／修改文件／验证命令与结果／剩余风险”汇报。
- [ ] 明确区分：聚焦测试、完整测试、Web 构建、iOS 模拟器、Android 静态契约和外部发布系统。
- [ ] 提醒外部人工事项仍未执行：App Store Connect 展示名、正式商标检索、域名、邮件发件人名称和商店素材。
- [ ] 不自动提交或推送；如用户要求提交，先仅暂存本计划列出的品牌文件并再次展示 `git diff --cached --stat` 供审核。

## 完成标准

- [ ] Flutter、iOS、Android、Web、通知和验证码邮件的用户可见品牌符合已确认命名契约。
- [ ] 登录品牌区显示“练搭 CoachMate／练，有人陪。”且不再渲染旧文字组合标。
- [ ] 所有紧凑通知标题使用“练搭”，通知隐私、调度和深链逻辑保持不变。
- [ ] Bundle ID、applicationId、Dart 包名、数据库、HealthKit／安全存储键和 StoreKit 产品 ID 保持不变。
- [ ] 聚焦测试全部通过；完整测试、静态分析、构建和模拟器结果均按真实输出报告。
- [ ] 没有混入数据库迁移、导航改造、消息删除、键盘处理或用户工作区中的其他改动。
