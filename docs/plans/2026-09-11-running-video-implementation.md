# 跑姿视频工具链实施与验证记录

日期：2026-09-11。结论：工程实现已接入，真实识别与测量效果尚未验收；正式入口保持关闭。

## 实现范围

已接通拍摄声明、相册选择、顺序解码、关键点进度、三项测量、中文解释、证据时间轴与骨架、手动保存和核心历史。支持任务取消、页面退出、后台取消、插件启停、账号域失效及保存失败重试。新流程不调用旧照片Mock，不生成综合评分，不修改训练计划。

动作分析拥有三项真实注册的本地技能，马拉松、越野跑、HYROX提供可选引用。报告最多20份、每份最多60帧，保存结构化数据，不保存视频／缩略图，不改数据库表结构，不进入云同步。细节与限制见[ADR-0007](../architecture/ADR-0007-跑姿视频本机工具链.md)。

开始时工作区已有337条Git状态记录。本次使用修改前文件快照区分既有改动；未重置、提交、推送或创建分支，未修改依赖清单、锁文件和后端。

## 验证结果

|检查|实测结果|边界|
|---|---|---|
|Flutter动作分析、插件、能力管理集合|393项通过、1项既有失败|本次新增25项全部通过|
|Flutter新增视频测试最终复查|25项通过|包括最后补充的异常帧时间／尺寸解析断言|
|Flutter静态分析|无问题|使用项目clean-copy脚本|
|iOS模拟器Debug构建|成功|启用预览参数，不代表识别成功|
|iOS RunnerTests|24项通过、2项失败，共26项|新增8项中6项通过；真实Vision请求的2项失败|
|真机、真人样本精度和全程网络观测|未验证|当前无可访问真机及授权跑步样本|

Flutter既有失败：`核心历史读取旧计划版本、日志和三类报告且不写存储`，滚动查找抛出 `Bad state: No element`。已在本次修改前源码快照的独立副本上复现，保留原断言，没有为本任务修复无关历史布局。

原生失败：`testBlackVideoKeepsTimestampsAndDoesNotInventPerson` 在 `VNDetectHumanBodyPoseRequest` 初始化时返回 Vision Code 9；`testCancellationStopsDecodingBeforeNextFrame` 同一路径在首帧回调之前失败，因此处理帧数为0，未达到期望的1。没有跳过或弱化这两项测试。另有独立解码／时间戳／取消测试通过注入空检测结果隔离模型运行环境，只证明基础工具链，不能证明真实识别。旋转与镜像、任务目录清理及清理边界测试通过。

## 可复现命令与证据

```bash
scripts/run_flutter_tests_clean_copy.sh test/features/motion_check test/plugins test/features/capabilities --reporter expanded --timeout 45s
scripts/run_flutter_tests_clean_copy.sh test/features/motion_check/running --reporter expanded --timeout 45s
scripts/run_flutter_analyze_clean_copy.sh
flutter build ios --simulator --debug --no-pub --dart-define=TRAINMATE_RUNNING_VIDEO_PREVIEW=true
```

原生在本机干净副本的 `ios` 目录执行 `xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=iOS Simulator,id=87D93C36-F5AE-4A65-A45A-94C15CBCBAC0' -derivedDataPath /tmp/trainmate-running-native-derived CODE_SIGNING_ALLOWED=NO test`。模拟器为iOS26.5；不将本机失败推断为所有模拟器均不支持，也不假设真机一定通过。

以下为本机临时证据，不随仓库分发，系统可能清理：

- `/tmp/trainmate-running-flutter-final.log`：相关集合结果。
- `/tmp/trainmate-running-parser-final.log`：新增25项最终复查。
- `/tmp/trainmate-running-analyze-final.log`：静态分析。
- `/tmp/trainmate-running-baseline-history.log`：修改前历史失败复现。
- `/tmp/trainmate-running-ios-build.log`：模拟器构建。
- `/tmp/trainmate-running-native-acceptance.log`：完整原生测试输出。
- `/tmp/trainmate-running-native-derived/Logs/Test/Test-Runner-2026.09.11_21-29-55--0700.xcresult`：24通过／2失败原始结果。
- `/tmp/trainmate-running-current.txt`：修改前快照与本次差异证据目录指针。

## 文件归属与修改原因

本次31个源码／测试文件以及3份文档，按责任列出如下；路径相对项目根目录。

|文件|原因|
|---|---|
|`ios/Runner/RunningVideoPoseCoordinator.swift`|新增任务网关、AVFoundation顺序读取、Vision检测、证据图和资源清理|
|`ios/Runner/AppDelegate.swift`|注册独立视频通道|
|`ios/Runner.xcodeproj/project.pbxproj`|纳入原生编译源文件|
|`ios/RunnerTests/RunnerTests.swift`|新增8项原生验证，保留失败证据|
|`lib/features/motion_check/running/running_pose_models.dart`|独立视频序列与输入校验|
|`lib/features/motion_check/running/running_video_pose_gateway.dart`|平台调用、进度、取消、迟到事件过滤及发行门槛|
|`lib/features/motion_check/running/running_metrics_service.dart`|纯计算几何、周期、独立数据质量判定|
|`lib/features/motion_check/running/running_form_assessment_service.dart`|分项报告、规则来源和代表帧选择|
|`lib/features/motion_check/running/running_form_report_repository.dart`|本机限额保存、持久化等待及失败恢复|
|`lib/features/motion_check/running/running_video_controller.dart`|拍摄确认、任务生命周期、账号隔离和手动提交|
|`lib/features/motion_check/running/running_report_view.dart`|指标、置信度、证据时间轴及骨架|
|`lib/features/motion_check/running/running_video_page.dart`|新分析流程、取消重试及报告管理|
|`lib/features/motion_check/motion_check_page.dart`|受发行开关控制的入口|
|`lib/features/capabilities/running_history_page.dart`|只读本机报告历史|
|`lib/features/capabilities/history_page.dart`|核心历史导航入口|
|`lib/features/capabilities/capabilities_page.dart`|展示拥有可选流程引用的运动详情|
|`lib/features/capabilities/plugin_skills_dialog.dart`|展示技能归属、共享引用和验收状态|
|`lib/app/router/app_router.dart`|分析与核心历史路由及访问门槛|
|`lib/plugins/features/motion_check_plugin.dart`|三项本地技能真实装配和网关清理|
|`lib/plugins/assembly/built_in_distribution.dart`|委托动作分析插件实现|
|`lib/plugins/features/built_in_features.dart`|保留委托元数据与新路由归属|
|`lib/plugins/core/plugin_descriptor.dart`|可选流程引用契约及基本校验|
|`lib/plugins/history/core_history.dart`|纯读取视频报告，不创建分析任务|
|`lib/plugins/sports/marathon_plugin.dart`|马拉松可选跑姿流程引用|
|`lib/plugins/sports/trail_running_plugin.dart`|平整场地越野跑训练可选引用|
|`lib/plugins/sports/hyrox_plugin.dart`|HYROX跑步部分可选引用|
|`lib/services/local_storage_service.dart`|SharedPreferences业务白名单增加报告键|
|`test/features/motion_check/running/running_video_gateway_test.dart`|解析、平台边界和重复取消|
|`test/features/motion_check/running/running_metrics_test.dart`|已知角度、时间序列及反例|
|`test/features/motion_check/running/running_repository_test.dart`|两种存储、限额、回滚和同步边界|
|`test/features/motion_check/running/running_controller_test.dart`|生命周期、保存、账号、历史与技能集成|
|`docs/architecture/ADR-0007-跑姿视频本机工具链.md`|维护契约、规则及验收门槛|
|`docs/plans/2026-09-04-trainmate-plugin-maintenance-guide.md`|新增视频工具链维护入口|
|`docs/plans/2026-09-11-running-video-implementation.md`|本次变更清单与实测证据|

## 剩余验收与回滚

尚未满足阶段一真实模型路径与阶段四效果验收门槛，不能视为全计划验收完成。工程隔离测试支持继续完善计算和集成代码，但不能替代这两个门槛。

需要用户授权的侧面跑步样本、静止／黑屏／遮挡／多人反例，以及可连接Xcode的iPhone。每份有效样本至少标注六个周期、十个可见膝角度，验证周期中位相对误差不超过10%、膝角中位绝对误差不超过10°，并实际观测取消、临时清理、界面响应和视频不上传。完整验收项沿用ADR，不降低要求。

入口目前默认关闭，且Release构建不能仅用编译参数启用。回滚保留旧照片流程、新报告只读能力和本地数据，只关闭新分析装配；不恢复整库快照。
