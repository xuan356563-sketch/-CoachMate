# 练搭 CoachMate iOS 分发证书 / Provisioning Profile 配置指引

> 版本：1.0（待上线）
> 前置：已完成 App Store Connect 注册 App + Bundle ID（`com.zhilian.trainmate`，Apple Team `4XKF438CG2`）
> 本文件指导你在 Apple Developer 后台完成签名配置。**此步骤需在装有 Xcode 的 Mac 上操作，且需要开发者账号权限。**

---

## 一、所需材料清单

| 材料 | 状态 | 说明 |
| --- | --- | --- |
| Apple Developer Program 账号 | 🟡 团队已有 `4XKF438CG2` | 确认角色为 Admin 或 App Manager |
| Xcode（建议 16+） | ❌ 需确认 | 用于签名、归档、上传 |
| Mac（macOS 14+） | ❌ 需确认 | 与项目文档"iOS 真机、签名、TestFlight 未验证"一致 |
| Apple 开发者账号的双重认证 | ✅ | 已在系统层面 |

---

## 二、证书与 Profile 创建步骤

### 2.1 证书类型

| 证书 | 用途 | 数量 |
| --- | --- | --- |
| Apple Development 证书 | 真机调试 | 1 个（可多 Mac 复用） |
| **Apple Distribution 证书** | **TestFlight / App Store 分发** | **1 个（必需）** |

### 2.2 操作路径（developer.apple.com → Certificates, Identifiers & Profiles）

1. **Identifiers → App IDs**：确认 `com.zhilian.trainmate` 已创建，且勾选以下 Capabilities：
   - HealthKit ✅（项目已在 entitlements 声明 `com.apple.developer.healthkit` 与 `healthkit.background-delivery`）
   - Push Notifications（如需系统通知；当前项目是本地 Mock，未接 APNs，**本轮可不勾**）
   - In-App Purchase ✅（项目已实现订阅）
2. **Keys / Certificates → 创建 Apple Distribution 证书**：
   - 在 Mac 上用钥匙串生成 CSR（钥匙串访问 → 证书助理 → 从证书颁发机构请求证书）
   - 上传 CSR → 下载 `.cer` → 双击安装到钥匙串
3. **Profiles → Distribution → App Store Connect**：
   - 选择 App ID `com.zhilian.trainmate`
   - 选择刚创建的 Distribution 证书
   - 下载 `.mobileprovision`，双击安装
4. **（可选）Development Profile**：真机调试用 `iOS App Development` Profile + Development 证书。

### 2.3 本地验证命令

```bash
# 确认 Xcode 已识别证书与 Profile
security find-identity -v -p codesigning
# 应看到 1 个 Apple Development 与 1 个 Apple Distribution 身份

# 无签名编译验证（项目文档已有此门禁）
cd zhuque-flutter-main
flutter build ios --release --no-codesign --no-pub
```

---

## 三、Xcode 工程签名配置

1. 打开 `ios/Runner.xcworkspace`（注意：是 xcworkspace，不是 xcodeproj）。
2. Runner target → **Signing & Capabilities**：
   - Team：选择 `4XKF438CG2`
   - Bundle Identifier：`com.zhilian.trainmate`
   - **Automatically manage signing**：勾选（Xcode 自动选 Profile）
3. 确认 **Capabilities** 面板包含：HealthKit（含后台投递）、In-App Purchase、Keychain Sharing（如需要）。
4. **Runner.entitlements**（项目已有）：
   - `com.apple.developer.healthkit` = true
   - `com.apple.developer.healthkit.background-delivery` = true
   - `com.apple.developer.default-data-protection` = NSFileProtectionCompleteUntilFirstUserAuthentication
   - ⚠️ 如果不需要 HealthKit 后台投递，可在 App ID 和 entitlements 中移除 `background-delivery`（苹果对 HealthKit 后台能力审核更严，**默认建议去掉**，除非确实需要）。

---

## 四、TestFlight 上传

### 4.1 归档

```bash
cd zhuque-flutter-main
# 使用生产后端地址（真实 HTTPS，不得 localhost）
flutter build ipa --release \
  --dart-define=TRAINFLOW_API_BASE_URL=https://你的生产域名 \
  --export-method=app-store-connect
```

> 若用 Xcode 归档：Product → Archive，然后 Distribute App → App Store Connect。

### 4.2 上传与内测

1. Xcode Organizer / `xcrun altool` 上传后，进入 App Store Connect → TestFlight。
2. 添加测试员（Internal：团队成员邮箱；External：外部测试邮箱，需过 Beta App Review）。
3. **首次外测前**需完成：
   - 隐私政策 URL ✅（已准备：`docs/legal/release/privacy-policy-zh.md`）
   - 出口合规 ✅（已准备申报表）
   - Beta App Review 信息（如使用外部测试员）

### 4.3 真机验证清单

上传后必须在**真实 iPhone**（非模拟器）验证以下流程（引用项目 docs/qa 真机阻断项）：

- [ ] 邮箱验证码登录、刷新令牌、退出、重新登录、账号切换
- [ ] HealthKit 权限**拒绝**后 App 安全降级（不崩溃）
- [ ] 相机/相册/麦克风/语音权限拒绝后安全降级
- [ ] SQLite 升级不丢数据、不清库进入
- [ ] 今日训练、计划生成/激活、跟练记录、数据中心、云端 AI 核心流程
- [ ] 订阅：沙箱环境购买、恢复购买、权益校验（StoreKit 2）
- [ ] 14 天自用验收无阻断问题

---

## 五、常见问题

| 问题 | 处理 |
| --- | --- |
| "No profiles for 'com.zhilian.trainmate' were found" | App ID 未创建或 Capabilities 未匹配，回 2.2 检查 |
| "Provisioning profile doesn't include HealthKit" | App ID 需勾选 HealthKit 并重新生成 Profile |
| 上传报 "Invalid Bundle" | 确认用 `flutter build ipa` 产物；检查 `--export-method` |
| 订阅沙箱不可用 | 在 App Store Connect → 订阅中配置产品；用沙箱账号（不是 Apple ID）测试 |

---

*本文件最后更新：[日期]*
