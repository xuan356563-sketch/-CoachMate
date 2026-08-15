# 练搭 CoachMate 上架前 Pre-flight 检查清单

> 版本：1.0（待上线）
> 用途：提交 App Store / Google Play 审核前的最终自查
> 规则：**所有阻断项（🔴）必须全部通过**才能提交；警告项（🟡）建议通过。

---

## 一、代码与构建（🔴 阻断）

- [ ] `flutter analyze` 无问题（当前：✅ 0 issues）
- [ ] `flutter test` 全绿（当前：✅ 961 通过）
- [ ] 后端 `pytest` 全绿（当前：✅ 257 通过）
- [ ] iOS Release 构建成功（`flutter build ipa --release --dart-define=TRAINFLOW_API_BASE_URL=https://真实域名`）
- [ ] Android Release 构建成功（`flutter build appbundle --release`，正式签名）
- [ ] Web 构建成功（`flutter build web --release`，如上架 Web）
- [ ] 版本号已设置（pubspec version 与商店一致，如 `1.0.0+1`）
- [ ] 当前 Git 提交已推送，构建产物可复现（绑定提交号）

## 二、资质与账号（🔴 阻断）

- [ ] Apple Developer 账号有效（团队 `4XKF438CG2`）
- [ ] App Store Connect 已注册 App + Bundle ID `com.zhilian.trainmate`
- [ ] **ICP 备案已完成**（中国大陆上架必需，App Store Connect 需填写备案号）
- [ ] Google Play 开发者账号已注册（如需上架 Android）
- [ ] Android 正式签名 keystore 已生成并安全备份（本机已配置 gradle 逻辑，见 `scripts/generate_android_release_keystore.sh`）
- [ ] 生成式 AI 备案/深度合成备案已启动（中国大陆 AI 功能必需，见备注）

## 三、法务文档（🔴 阻断，需公网 URL）

- [ ] 隐私政策已发布到公网 URL（文本：`docs/legal/release/privacy-policy-zh.md` / `-en.md`）
- [ ] 服务条款已发布到公网 URL（`terms-of-service-zh.md` / `-en.md`）
- [ ] 订阅 EULA 已发布到公网 URL（`subscription-eula-zh.md` / `-en.md`）
- [ ] 健康免责声明已在 App 内展示（`health-disclaimer-zh.md`）
- [ ] AI 内容说明与举报渠道已在 App 内展示（`ai-content-policy-zh.md`）
- [ ] 上述文档中的占位符（[公司名称]/[联系邮箱]/[公司地址]/[ICP备案号]）已替换为真实信息

## 四、商店元数据（🔴 阻断）

- [ ] App 名称/副标题已填写（建议：练搭 CoachMate / 练，有人陪）
- [ ] 描述（中英）已填写（`app-store-metadata.md`）
- [ ] 关键词已填写（≤100 字符）
- [ ] 截图已上传（6.7"/6.5" 各 ≥2-3 张，与 App 实际 UI 一致）
- [ ] App 图标已上传（1024×1024，无透明通道）
- [ ] 分类已选择（健康健美/体育）
- [ ] 年龄分级已填写（建议 12+，含 AI 生成内容如实申报）
- [ ] 隐私营养标签已填写并提交（`privacy-nutrition-labels.md`）
- [ ] 出口合规已勾选豁免
- [ ] 审核备注已填写（演示账号/安全机制/健康数据边界/AI 说明）

## 五、后端与联调（🔴 阻断，依据 V1.1 外部依赖表）

- [ ] 生产环境已部署（HTTPS 域名 + TLS）
- [ ] PostgreSQL / Redis 生产就绪，`/readyz` 返回 200
- [ ] SMTP 真实邮件验证码可发送
- [ ] 腾讯云短信（如启用）可发送
- [ ] DeepSeek 生产密钥联调通过（超时/限流降级正常）
- [ ] MiniMax 生产密钥联调通过
- [ ] 服务端密钥均从环境注入，不入库、不进构建日志

## 六、真机验收（🔴 阻断）

- [ ] TestFlight 真机验收全部通过（`testflight-acceptance-checklist.md`）
- [ ] 14 天自用验收 Gate A 通过
- [ ] 权限拒绝降级验证通过
- [ ] 订阅沙箱验证通过（如启用订阅）

## 七、发布前收尾（🟡 警告）

- [ ] 移除调试输出/临时日志（print、debugPrint）
- [ ] 确认无 TODO/FIXME 阻断项（`grep -rn "TODO" lib/` 人工复核）
- [ ] 确认 Release 构建不包含本地/测试环境地址（`grep -rn "127.0.0.1\|localhost" lib/ --include="*.dart"` 检查非测试文件）
- [ ] 素材清权确认（`docs/legal/flow-dog-v1-素材清权包.md`）
- [ ] 无障碍基础检查（动态字体、对比度）
- [ ] 冷启动性能抽查（Release 构建首屏 < 3s）

---

## 附：生成式 AI 备案提醒（中国大陆）

如 App 在中国大陆提供生成式 AI 功能（AI Trainer/AI Motion/AI Recovery），需按《生成式人工智能服务管理暂行办法》完成：

1. **算法备案**：向网信办提交算法备案（如适用"具有舆论属性或社会动员能力"）。
2. **深度合成备案**：AI 生成文本/图片属于深度合成服务，需备案。
3. **安全评估**：新上线生成式 AI 服务需通过安全评估。
4. **主体要求**：需有中国境内运营主体。

> 建议：上线前咨询专业合规顾问，或在首版先**关闭 AI 联网功能**（本地规则 Mock 已具备降级能力），完成备案后再开启，以降低上线风险。

---

*本文件最后更新：[日期]*
