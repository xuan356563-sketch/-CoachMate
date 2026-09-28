import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_brand.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/design_system/trainmate_primitives.dart';
import '../../../core/widgets/emp_system.dart';
import '../../../core/widgets/trainmate_action_character.dart';
import '../../../core/widgets/trainmate_branding.dart';
import '../../../core/widgets/trainmate_showcase_widgets.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../first_run_onboarding/application/first_run_onboarding_controller.dart';
import '../../first_run_onboarding/domain/first_run_models.dart';
import '../application/auth_controller.dart';
import '../application/account_switch_coordinator.dart';
import '../data/auth_api.dart';

class AuthLoadingPage extends StatelessWidget {
  const AuthLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrainMateBrandmark(size: 82),
            SizedBox(height: 12),
            TrainMateActionCharacter(
              action: TrainMateAction.running,
              size: 96,
              backgroundColor: AppColors.primary,
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(color: TrainFlowTokens.accent),
            SizedBox(height: 12),
            Text(
              '正在检查登录状态',
              style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  String? _challengeId;
  String? _challengeIdentity;
  String? _localError;
  bool _agreed = false;
  int _countdown = 0;
  Timer? _timer;
  bool _usePhone = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_invalidateChallengeWhenEmailChanges);
    _phoneController.addListener(_invalidateChallengeWhenEmailChanges);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.removeListener(_invalidateChallengeWhenEmailChanges);
    _phoneController.removeListener(_invalidateChallengeWhenEmailChanges);
    _emailController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AuthState> authAsync = ref.watch(authControllerProvider);
    final AuthState? authState = switch (authAsync) {
      AsyncData<AuthState>(:final value) => value,
      _ => null,
    };
    final OnboardingStage? firstRunStage =
        ref.watch(firstRunOnboardingControllerProvider).value?.stage;

    return TrainFlowPage(
      title: '登录 ${AppBrand.displayName}',
      layout: TrainFlowPageLayout.form,
      subtitle: firstRunStage == OnboardingStage.login
          ? '3/4 · 登录失败不会丢失刚才确认的本地草稿。'
          : '训练数据留在当前设备，账号用于保护访问与赛事图片识别。',
      eyebrow: firstRunStage == OnboardingStage.login ? '首次建档' : '账号与会话',
      artwork: const SizedBox.square(
        dimension: 96,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: TrainMateIllustration(
                assetPath: 'assets/images/trainmate_onboarding_scene.png',
                semanticLabel: '首次建档与训练目标确认插画',
                fallback: TrainMateBrandmark(size: 72),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: TrainMateBrandmark(size: 28),
            ),
          ],
        ),
      ),
      includeDisclaimer: false,
      children: [
        if (firstRunStage == OnboardingStage.login)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: EmpBadge(
                label: '首次建档 · 第 3 步 / 共 4 步',
                tone: EmpBadgeTone.pink,
                icon: Icons.flag_outlined,
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Center(child: TrainMateBrandLockup(height: 168)),
        ),
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _usePhone ? '手机号登录' : '邮箱登录',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _usePhone ? '验证码会发送至手机。访问令牌只保存在内存中。' : '验证码会发送至邮箱。访问令牌只保存在内存中。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Text('邮箱验证码')),
                  ButtonSegment<bool>(value: true, label: Text('手机号验证码')),
                ],
                selected: <bool>{_usePhone},
                onSelectionChanged: (Set<bool> value) {
                  setState(() {
                    _usePhone = value.first;
                    _invalidateChallenge();
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_usePhone)
                TextField(
                  key: const ValueKey<String>('auth-phone'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: '中国大陆手机号',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                )
              else
                TextField(
                  key: const ValueKey<String>('auth-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('auth-code'),
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '验证码',
                        counterText: '',
                        prefixIcon: Icon(Icons.password),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      key: const ValueKey<String>('auth-send-code'),
                      onPressed: authState?.isBusy == true || _countdown > 0
                          ? null
                          : _requestCode,
                      child: Text(
                        _countdown > 0 ? '$_countdown 秒后重发' : '发送验证码',
                      ),
                    ),
                  ),
                ],
              ),
              if ((_usePhone
                      ? authState?.publicConfig?.smsMode
                      : authState?.publicConfig?.emailMode) ==
                  'development') ...[
                const SizedBox(height: 10),
                const ToneBadge(label: '内部测试验证码 246810'),
              ],
              const SizedBox(height: 14),
              InkWell(
                onTap: () => setState(() => _agreed = !_agreed),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _agreed,
                      onChanged: (bool? value) {
                        setState(() => _agreed = value ?? false);
                      },
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 11),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('我已阅读并同意'),
                            TextButton(
                              onPressed: () => context.push(AppRoutes.terms),
                              child: const Text('服务协议'),
                            ),
                            const Text('和'),
                            TextButton(
                              onPressed: () => context.push(AppRoutes.privacy),
                              child: const Text('隐私政策'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_localError != null || authState?.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _localError ?? authState!.message!,
                  key: const ValueKey<String>('auth-message'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _localError == null &&
                                (authState?.message?.contains('已发送') == true ||
                                    authState?.message?.contains('246810') ==
                                        true)
                            ? AppColors.success
                            : AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              TrainMateButton(
                key: const ValueKey<String>('auth-login'),
                label: '登录并进入${AppBrand.displayName}',
                icon: Icons.login,
                loading: authState?.isBusy == true,
                onPressed: authState?.isBusy == true ? null : _login,
                expand: true,
              ),
              if (ref.watch(localPreviewEnabledProvider)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('local-preview-login'),
                    onPressed:
                        authState?.isBusy == true ? null : _enterLocalPreview,
                    icon: const Icon(Icons.devices_outlined),
                    label: const Text('进入本地体验（不含云端功能）'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '仅用于当前调试版本，不发送验证码，也不会创建云端账号。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                ),
              ],
              if (authState?.publicConfig == null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: authState?.isBusy == true
                        ? null
                        : () => ref
                            .read(authControllerProvider.notifier)
                            .reloadPublicConfig(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新连接服务'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _requestCode() async {
    final String identity = _normalizedIdentity();
    if (_usePhone ? !_isValidPhone(identity) : !_isValidEmail(identity)) {
      setState(() => _localError = _usePhone ? '请输入有效的中国大陆手机号' : '请输入有效的邮箱地址');
      return;
    }
    setState(() => _localError = null);
    final EmailChallenge? challenge = _usePhone
        ? await ref
            .read(authControllerProvider.notifier)
            .requestPhoneCode(identity)
        : await ref
            .read(authControllerProvider.notifier)
            .requestEmailCode(identity);
    if (!mounted || challenge == null) {
      return;
    }
    setState(() {
      _challengeId = challenge.challengeId;
      _challengeIdentity = identity;
      _countdown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted || _countdown <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _countdown = 0);
        }
        return;
      }
      setState(() => _countdown -= 1);
    });
  }

  Future<void> _login() async {
    final String identity = _normalizedIdentity();
    final String code = _codeController.text.trim();
    if (!_agreed) {
      setState(() => _localError = '请先阅读并同意服务协议与隐私政策');
      return;
    }
    if (_challengeId == null || _challengeIdentity != identity) {
      setState(
          () => _localError = _usePhone ? '请先为当前手机号发送验证码' : '请先为当前邮箱发送验证码');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _localError = '请输入六位数字验证码');
      return;
    }
    setState(() => _localError = null);
    if (_usePhone) {
      await ref.read(authControllerProvider.notifier).loginWithPhone(
            phone: identity,
            challengeId: _challengeId!,
            code: code,
          );
    } else {
      await ref.read(authControllerProvider.notifier).login(
            email: identity,
            challengeId: _challengeId!,
            code: code,
          );
    }
  }

  Future<void> _enterLocalPreview() async {
    if (!_agreed) {
      setState(() => _localError = '请先阅读并同意服务协议与隐私政策');
      return;
    }
    setState(() => _localError = null);
    await ref.read(authControllerProvider.notifier).enterLocalPreview();
  }

  void _invalidateChallengeWhenEmailChanges() {
    final String? challengeIdentity = _challengeIdentity;
    if (challengeIdentity == null ||
        _normalizedIdentity() == challengeIdentity) {
      return;
    }
    setState(_invalidateChallenge);
  }

  void _invalidateChallenge() {
    _timer?.cancel();
    _challengeId = null;
    _challengeIdentity = null;
    _countdown = 0;
  }

  String _normalizedEmail() => _emailController.text.trim().toLowerCase();

  String _normalizedIdentity() => _usePhone
      ? _phoneController.text.trim().replaceAll(RegExp(r'[\s-]'), '')
      : _normalizedEmail();

  bool _isValidEmail(String email) {
    return email.length <= 254 &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool _isValidPhone(String phone) =>
      RegExp(r'^(?:\+86)?1[3-9]\d{9}$').hasMatch(phone);
}

class AccountSwitchPage extends ConsumerWidget {
  const AccountSwitchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState? state = switch (ref.watch(authControllerProvider)) {
      AsyncData<AuthState>(:final value) => value,
      _ => null,
    };
    final bool scopeReplaced = state?.accountScopeReplaced == true;
    return TrainFlowPage(
      title: '确认切换账号',
      layout: TrainFlowPageLayout.form,
      subtitle: scopeReplaced ? '本地账号数据已切换，正在恢复新账号功能。' : '当前设备已经绑定过其他账号。',
      eyebrow: '本地数据保护',
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_data_shield.png',
        semanticLabel: '账号切换与本地数据保护插画',
        fallback: TrainMateActionCharacter(
          action: TrainMateAction.seatedMeditation,
          backgroundColor: AppColors.primary,
        ),
      ),
      includeDisclaimer: false,
      children: [
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                '新账号 ${state?.user?.maskedAccountLabel ?? '邮箱信息不可用'}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                scopeReplaced
                    ? '旧账号本地业务数据已经清理，新账号也已完成绑定。继续只会重试功能装配，不会再次清理数据。若暂时无法恢复，请重启应用后再次登录。'
                    : '继续会清除当前设备上的训练资料、日志和比赛数据，再绑定新账号。取消会退出新会话并完整保留原数据。',
              ),
              if (state?.message != null) ...[
                const SizedBox(height: 10),
                Text(state!.message!),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state?.isBusy == true
                      ? null
                      : () async {
                          try {
                            await ref
                                .read(accountSwitchCoordinatorProvider)
                                .confirm();
                          } catch (_) {
                            if (!context.mounted) return;
                            final AuthState? latest =
                                switch (ref.read(authControllerProvider)) {
                              AsyncData<AuthState>(:final value) => value,
                              _ => null,
                            };
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  latest?.message ?? '账号切换未完成，请重试。',
                                ),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(scopeReplaced ? '重试恢复新账号功能' : '清除本地业务数据并切换'),
                ),
              ),
              if (!scopeReplaced) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: state?.isBusy == true
                        ? null
                        : () => ref
                            .read(authControllerProvider.notifier)
                            .cancelAccountSwitch(),
                    icon: const Icon(Icons.close),
                    label: const Text('取消并保留原数据'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalPage(
      title: '服务协议',
      version: 'internal-test-2026-07-13.1',
      sections: [
        (
          '内部测试说明',
          '本协议仅用于${AppBrand.displayName} 内部测试，不构成正式商业服务条款。',
        ),
        ('邮箱账号与访问', '邮箱验证码用于保护 App 访问和调用赛事图片识别服务，不代表训练数据已经云同步。'),
        ('训练建议边界', '训练建议属于决策辅助，不替代医生、康复师或持证教练的专业判断。'),
        ('账号切换', '同一设备切换不同账号前必须由用户确认，系统不会直接展示旧账号数据。'),
      ],
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalPage(
      title: '隐私政策',
      version: 'internal-test-2026-07-13.1',
      sections: [
        ('邮箱', '邮箱仅用于账号验证和访问保护；接口只展示脱敏邮箱，不返回完整邮箱地址。'),
        ('训练数据', '当前训练资料、日志和比赛计划仍保存在设备本地，退出账号不会自动删除。'),
        ('赛事图片', '用户主动选择的赛事图片会发送至 MiniMax 进行一次性识别，后端不写入磁盘、数据库或日志。'),
        ('令牌', '访问令牌只保存在内存；iPhone 刷新令牌保存在系统 Keychain，Web 刷新后需重新登录。'),
      ],
    );
  }
}

class _LegalPage extends StatelessWidget {
  final String title;
  final String version;
  final List<(String, String)> sections;

  const _LegalPage({
    required this.title,
    required this.version,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: title,
      layout: TrainFlowPageLayout.legal,
      subtitle: '内部测试版本 $version',
      eyebrow: AppBrand.displayName,
      headerVariant: TrainFlowHeaderVariant.compact,
      includeDisclaimer: false,
      action: IconButton(
        tooltip: '返回',
        onPressed: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.login),
        icon: const Icon(Icons.close),
      ),
      children: [
        for (final (String heading, String body) in sections)
          TrainFlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(body),
              ],
            ),
          ),
      ],
    );
  }
}
