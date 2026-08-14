# TrainMate 首次语音建档、登录与 iOS 订阅实施记录

> 日期：2026-07-31  
> 状态：代码与自动测试实施；功能开关默认关闭，真机交易、TestFlight 和 App Store 审核未完成。

## 一、已实现流程

首次流程位于独立 `first_run_onboarding` feature：

```text
个人资料确认
→ 运动能力自评
→ 邮箱或手机号验证码登录
→ 健康资料云同步范围确认
→ iOS 会员说明、购买或浏览模式
→ 应用首页
```

- 个人资料页支持文字和 iOS 本地语音转写，顶部提示可由系统 TTS 朗读。
- 原始输入只用于当前内存中的确定性解析；形成字段卡后立即清空，安全存储只保存确认后的结构化草稿。
- 草稿保存在系统安全存储，七天未完成自动删除；账号切换时拒绝把已绑定草稿静默绑定到其他账号。
- 年龄低于18岁时停留在个人资料页，不进入登录、云同步或会员页。
- 运动页使用训练环境、频率、平板支撑、谈话测试和楼梯后呼吸恢复的枚举选项，不调用模型。
- 原 `/onboarding` 保留为登录后的档案编辑入口。

## 二、隐私与云档案

新增同步实体 `user_profile` 和表 `cloud_user_profiles`。数据库只保存 AES-256-GCM 密文、12字节随机数、密钥版本、Schema版本和是否包含健康字段，不创建昵称、身高、体重或伤病明文字段。

健康同步同意使用独立接口：

```http
PUT /v1/account/consents/health-profile-cloud
```

身高、体重和伤病默认关闭。撤回同意后，服务端解密当前档案、清除三个健康字段并用新随机数重新加密。原始语音、转写稿、自由文本和健康资料均不得进入 AI、Redis、缓存键、日志或 AI 用量表。

生产环境启用健康云同步时必须配置：

- `PROFILE_ENCRYPTION_KEY`：Base64 编码的32字节密钥；
- `PROFILE_ENCRYPTION_KEY_VERSION`；
- `HEALTH_PROFILE_CONSENT_VERSION`。

密钥缺失、版本错误或密文被篡改时失败关闭，不降级到明文。

## 三、订阅与权益

Flutter 使用 `in_app_purchase 3.3.0`，产品ID固定为：

```text
com.zhilian.trainmate.membership.monthly
```

会员页只展示 StoreKit 返回的本地化价格。StoreKit 2 会查询首次优惠资格；不符合资格时不显示7天试用。购买和恢复结果先提交后端验签，后端核对 Bundle ID、产品ID、环境和绑定当前用户的 `appAccountToken`，验证成功后客户端才完成交易。

后端新增：

- `subscription_entitlements`：服务端权益裁决；
- `apple_subscription_events`：通知 UUID 和签名载荷 SHA-256 摘要，用于去重；
- `GET /v1/billing/entitlement`；
- `POST /v1/billing/apple/transactions/verify`；
- `POST /v1/billing/apple/notifications`。

允许生成的状态只有 `trial`、`active` 和 `grace_period`。会员到期、退款或撤销只阻止生成和重排，不删除已有计划或训练记录。Android不加载购买商品，只能进入浏览模式。

本地 Xcode 测试商品配置位于 `ios/StoreKit/TrainMate.storekit`。该文件只用于本地 StoreKit 测试，不证明 App Store Connect 产品、Sandbox 或生产交易已配置成功。

## 四、功能开关

Flutter 构建开关默认关闭：

```bash
--dart-define=FIRST_RUN_ONBOARDING_V2_ENABLED=true
--dart-define=HEALTH_PROFILE_CLOUD_ENABLED=true
--dart-define=IOS_SUBSCRIPTION_ENABLED=true
--dart-define=PAID_PLAN_GENERATION_GATE_ENABLED=true
```

后端对应环境变量也默认关闭：

```text
HEALTH_PROFILE_CLOUD_ENABLED=false
IOS_SUBSCRIPTION_ENABLED=false
PAID_PLAN_GENERATION_GATE_ENABLED=false
```

建议先只打开首次流程，再打开健康密文同步和Sandbox订阅，最后打开付费生成门禁。关闭门禁不会删除已有权益数据。

## 五、兼容与回滚

- 旧 API、五类旧同步实体和本地 SQLite 数据不变；`user_profile` 为新增实体。
- 现有已登录用户没有未完成首次草稿时继续进入仪表盘。
- 数据库异常时先关闭三个后端开关并回退应用版本，生产环境不自动执行降级迁移。
- `20260731_0010` 与 `20260731_0011` 的降级仅供空数据测试环境；生产应保留密文、交易和审计记录。

## 六、验收边界

自动化可证明模型、路由、加密、授权、交易状态和幂等逻辑；iOS Simulator 只能证明页面与本地 StoreKit 配置可编译。以下仍是外部门禁：

- App Store Connect 订阅组、19.9元中国区价格和7天首次优惠；
- 苹果根证书、App Apple ID 和 Server Notifications V2 地址；
- iPhone 真机语音权限；
- Sandbox购买、取消、待处理和恢复；
- TestFlight链路和首次订阅随新版本送审。

## 七、本地验收证据

2026-07-31 已完成以下可重复验证：

- 后端完整 `pytest`：216 项通过；仅有1条来自第三方 TestClient 的弃用警告；
- 后端 `ruff check app tests`：通过；
- Flutter 临时干净副本全量测试：673 项通过；
- Flutter 临时干净副本静态分析：无问题；
- `TrainMate.storekit` JSON 格式校验：通过；
- iOS Simulator 无签名构建：通过，生成 `Runner.app`。

以上证据不包含真机语音权限、App Store Connect商品配置、Sandbox交易、生产苹果通知、TestFlight或App Store审核。
