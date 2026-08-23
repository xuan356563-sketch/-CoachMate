import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/constants/app_brand.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/design_system/trainmate_primitives.dart';
import '../../../core/widgets/trainmate_branding.dart';
import '../../../core/widgets/trainmate_showcase_widgets.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../services/workout_platform_service.dart';
import '../../ai_center/application/voice_input_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/authenticated_api_client.dart';
import '../application/first_run_onboarding_controller.dart';
import '../application/membership_controller.dart';
import '../application/personal_profile_local_parser.dart';
import '../data/first_run_remote_api.dart';
import '../domain/first_run_models.dart';

const String _personalPrompt =
    '请描述您的个人资料，包括性别、昵称、年龄、身高、体重、伤病情况、职业和训练目标。你可以打字，也可以点击麦克风说。';
const String _trainingPrompt =
    '请告诉我：你通常在哪里训练、一周能稳定训练几次；动作标准且没有疼痛时，平板支撑大约多久；快走或慢跑多久还能说完整句子；快走上三层楼后，大约多久能恢复到可以正常说话。';
const String _healthConsentVersion = 'health-profile-cloud-2026-07-31.1';

class PersonalProfileWelcomePage extends ConsumerStatefulWidget {
  const PersonalProfileWelcomePage({super.key});

  @override
  ConsumerState<PersonalProfileWelcomePage> createState() =>
      _PersonalProfileWelcomePageState();
}

class _PersonalProfileWelcomePageState
    extends ConsumerState<PersonalProfileWelcomePage> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _occupation = TextEditingController();
  final TextEditingController _goal = TextEditingController();
  final VoiceInputGateway _voice = createVoiceInputGateway();
  final WorkoutPlatformService _speaker = WorkoutPlatformService();
  PersonalProfileDraft? _parsed;
  bool _listening = false;
  String _gender = 'unknown';
  String? _message;

  @override
  void dispose() {
    unawaited(_voice.cancelListening());
    unawaited(_speaker.stopSpeech());
    _input.dispose();
    _nickname.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _occupation.dispose();
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: '先认识一下你',
      layout: TrainFlowPageLayout.form,
      subtitle: '1/4 · 个人资料只在你确认后保存',
      eyebrow: '首次建档',
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_onboarding_scene.png',
        semanticLabel: '个人资料确认与训练伙伴插画',
        fallback: TrainMateBrandmark(size: 68),
      ),
      includeDisclaimer: false,
      children: <Widget>[
        _PromptCard(
          text: _personalPrompt,
          onSpeak: () => _speaker.speak(_personalPrompt, rate: 0.9),
        ),
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '文字或本地语音输入',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey<String>('first-run-personal-input'),
                controller: _input,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: '我叫小智，男，32岁，175厘米，72公斤，办公室久坐，右膝以前受过伤，想减脂并提高体能。',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _voice.isSupported ? _toggleVoice : null,
                    icon: Icon(_listening ? Icons.stop : Icons.mic_none),
                    label: Text(_listening ? '结束并转写' : '本地语音'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TrainMateButton(
                      label: '识别为待确认字段',
                      onPressed: _parse,
                      expand: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '音频不会上传；识别后立即清除原始文字，只保留你确认的结构化字段。',
                style: TextStyle(color: TrainFlowTokens.darkTrainingMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (_parsed != null) _confirmationCard(context),
        if (_message != null)
          Text(
            _message!,
            key: const ValueKey<String>('first-run-personal-message'),
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  Widget _confirmationCard(BuildContext context) {
    final PersonalProfileDraft parsed = _parsed!;
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '请逐项确认或修改',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _field(_nickname, '昵称'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: const InputDecoration(
              labelText: '性别',
              border: OutlineInputBorder(),
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'male', child: Text('男')),
              DropdownMenuItem(value: 'female', child: Text('女')),
              DropdownMenuItem(value: 'other', child: Text('其他')),
              DropdownMenuItem(value: 'unknown', child: Text('暂不说明')),
            ],
            onChanged: (String? value) => _gender = value ?? 'unknown',
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: _field(_age, '年龄', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field(_height, '身高 cm', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field(_weight, '体重 kg', number: true)),
            ],
          ),
          const SizedBox(height: 10),
          _field(_occupation, '职业类型'),
          const SizedBox(height: 10),
          _field(_goal, '训练目标'),
          if (parsed.injuries.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text('伤病限制（不作疾病诊断）',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final StructuredInjuryProfile injury in parsed.injuries)
              Text(
                '${injury.bodyRegion} · ${injury.state} · ${injury.limitingActivity} · ${injury.confirmedNote}',
              ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('first-run-confirm-personal'),
              onPressed: _confirm,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('确认并继续'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  void _parse() {
    final String raw = _input.text;
    if (raw.trim().isEmpty) {
      setState(() => _message = '请先输入或说出个人资料');
      return;
    }
    final PersonalProfileDraft profile =
        const PersonalProfileLocalParser().parse(raw).profile;
    _input.clear();
    setState(() {
      _parsed = profile;
      _nickname.text = profile.nickname;
      _age.text = profile.declaredAge == 0 ? '' : '${profile.declaredAge}';
      _height.text = profile.heightCm?.toStringAsFixed(0) ?? '';
      _weight.text = profile.weightKg?.toStringAsFixed(0) ?? '';
      _occupation.text = profile.workerProfileType;
      _goal.text = profile.trainingGoal;
      _gender = profile.gender;
      _message = null;
    });
  }

  Future<void> _toggleVoice() async {
    try {
      if (!_listening) {
        await _voice.startListening();
        if (mounted) setState(() => _listening = true);
        return;
      }
      final String transcript = await _voice.stopListening();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _input.text = transcript;
        _message = transcript.trim().isEmpty ? '没有识别到语音，请改用文字输入' : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _message = '语音识别不可用，请使用文字输入';
        });
      }
    }
  }

  Future<void> _confirm() async {
    final PersonalProfileDraft original = _parsed!;
    final PersonalProfileDraft confirmed = PersonalProfileDraft(
      nickname: _nickname.text.trim(),
      gender: _gender,
      declaredAge: int.tryParse(_age.text.trim()) ?? 0,
      heightCm: double.tryParse(_height.text.trim()),
      weightKg: double.tryParse(_weight.text.trim()),
      workerProfileType: _occupation.text.trim(),
      workScheduleType: original.workScheduleType,
      trainingGoal: _goal.text.trim(),
      mainSports: original.mainSports,
      trainingExperienceLevel: original.trainingExperienceLevel,
      injuries: original.injuries,
    );
    if (confirmed.nickname.isEmpty || confirmed.declaredAge == 0) {
      setState(() => _message = '请补充昵称和年龄');
      return;
    }
    final bool accepted = await ref
        .read(firstRunOnboardingControllerProvider.notifier)
        .confirmPersonal(confirmed);
    if (!mounted) return;
    if (!accepted) {
      setState(() => _message = '${AppBrand.displayName} 目前仅向18岁以上用户开放');
      return;
    }
    context.go(AppRoutes.welcomeTraining);
  }
}

class TrainingBaselineWelcomePage extends ConsumerStatefulWidget {
  const TrainingBaselineWelcomePage({super.key});

  @override
  ConsumerState<TrainingBaselineWelcomePage> createState() =>
      _TrainingBaselineWelcomePageState();
}

class _TrainingBaselineWelcomePageState
    extends ConsumerState<TrainingBaselineWelcomePage> {
  String? environment;
  int? days;
  int minutes = 45;
  String? core;
  String? aerobic;
  String? recovery;
  String? message;

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: '了解你的运动情况',
      layout: TrainFlowPageLayout.form,
      subtitle: '2/4 · 用于训练分层，不作健康诊断',
      eyebrow: '首次建档',
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_onboarding_scene.png',
        semanticLabel: '运动基础与训练目标确认插画',
        fallback: TrainMateBrandmark(size: 68),
      ),
      includeDisclaimer: false,
      children: <Widget>[
        _PromptCard(
          text: _trainingPrompt,
          onSpeak: () =>
              WorkoutPlatformService().speak(_trainingPrompt, rate: 0.9),
        ),
        _choice(
            '通常在哪里训练？',
            <String, String>{
              'bodyweight_home': '徒手居家',
              'home_equipment': '家用器械',
              'gym': '健身房',
              'outdoor': '户外',
              'mixed': '混合',
            },
            environment,
            (String value) => setState(() => environment = value)),
        _choice(
            '一周能稳定训练几次？',
            <String, String>{
              '1': '每周1次',
              '2': '每周2次',
              '3': '每周3次',
              '4': '每周4次',
              '5': '每周5次以上',
            },
            days?.toString(),
            (String value) => setState(() => days = int.parse(value))),
        _choice(
            '平板支撑大约多久？',
            <String, String>{
              'under_20_seconds': '少于20秒',
              'seconds_20_45': '20–45秒',
              'seconds_46_90': '46–90秒',
              'over_90_seconds': '90秒以上',
              'uncertain': '不确定',
            },
            core,
            (String value) => setState(() => core = value)),
        _choice(
            '快走或慢跑多久还能说完整句子？',
            <String, String>{
              'under_10_minutes': '少于10分钟',
              'minutes_10_20': '10–20分钟',
              'minutes_21_40': '21–40分钟',
              'over_40_minutes': '40分钟以上',
              'uncertain': '不确定',
            },
            aerobic,
            (String value) => setState(() => aerobic = value)),
        _choice(
            '快走上三层楼后，多久能正常说话？',
            <String, String>{
              'over_5_minutes': '5分钟以上',
              'minutes_3_5': '3–5分钟',
              'minutes_1_3': '1–3分钟',
              'under_1_minute': '1分钟以内',
              'uncertain': '不确定',
            },
            recovery,
            (String value) => setState(() => recovery = value)),
        _choice(
            '每次通常能安排多久？',
            <String, String>{
              '30': '30分钟',
              '45': '45分钟',
              '60': '60分钟',
              '90': '90分钟',
            },
            minutes.toString(),
            (String value) => setState(() => minutes = int.parse(value))),
        if (message != null)
          Text(message!, style: const TextStyle(color: AppColors.danger)),
        FilledButton(
          key: const ValueKey<String>('first-run-confirm-training'),
          onPressed: _confirm,
          child: const Text('确认并进入登录'),
        ),
      ],
    );
  }

  Widget _choice(
    String title,
    Map<String, String> options,
    String? selected,
    ValueChanged<String> onSelected,
  ) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.entries
                .map(
                  (MapEntry<String, String> entry) => ChoiceChip(
                    label: Text(entry.value),
                    selected: selected == entry.key,
                    onSelected: (_) => onSelected(entry.key),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    if (environment == null ||
        days == null ||
        core == null ||
        aerobic == null ||
        recovery == null) {
      setState(() => message = '请完成五项运动情况自评');
      return;
    }
    await ref
        .read(firstRunOnboardingControllerProvider.notifier)
        .confirmTraining(
          TrainingBaselineDraft(
            trainingEnvironment: environment!,
            weeklyTrainingDays: days!,
            dailyAvailableMinutes: minutes,
            coreSelfReport: core!,
            aerobicTalkTest: aerobic!,
            cardioRecovery: recovery!,
          ),
        );
    if (mounted) context.go(AppRoutes.login);
  }
}

class HealthCloudConsentPage extends ConsumerStatefulWidget {
  const HealthCloudConsentPage({super.key});

  @override
  ConsumerState<HealthCloudConsentPage> createState() =>
      _HealthCloudConsentPageState();
}

class _HealthCloudConsentPageState
    extends ConsumerState<HealthCloudConsentPage> {
  bool height = false;
  bool weight = false;
  bool injuries = false;
  bool busy = false;
  String? message;

  @override
  Widget build(BuildContext context) {
    return TrainFlowPage(
      title: '确认云端保存范围',
      layout: TrainFlowPageLayout.form,
      subtitle: '3/4 · 登录成功，健康资料需单独授权',
      eyebrow: '隐私控制',
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_data_shield.png',
        semanticLabel: '健康资料授权保护插画',
        fallback: TrainMateBrandmark(size: 68),
      ),
      includeDisclaimer: false,
      children: <Widget>[
        const TrainFlowCard(
          child: Text(
            '昵称、训练目标和运动情况会正常同步。身高、体重和伤病默认不上传；健康资料不会进入大模型请求。',
          ),
        ),
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            children: <Widget>[
              if (!healthProfileCloudEnabled)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('健康资料云同步尚未放量'),
                  subtitle: Text('本次只同步非健康档案字段。'),
                ),
              SwitchListTile(
                title: const Text('云端保存身高'),
                value: height,
                onChanged: busy || !healthProfileCloudEnabled
                    ? null
                    : (bool value) => setState(() => height = value),
              ),
              SwitchListTile(
                title: const Text('云端保存体重'),
                value: weight,
                onChanged: busy || !healthProfileCloudEnabled
                    ? null
                    : (bool value) => setState(() => weight = value),
              ),
              SwitchListTile(
                title: const Text('云端保存伤病限制'),
                subtitle: const Text('只保存你确认的部位、状态、受限动作和说明'),
                value: injuries,
                onChanged: busy || !healthProfileCloudEnabled
                    ? null
                    : (bool value) => setState(() => injuries = value),
              ),
            ],
          ),
        ),
        if (message != null)
          Text(message!, style: const TextStyle(color: AppColors.danger)),
        FilledButton(
          onPressed: busy ? null : _save,
          child: Text(busy ? '正在加密保存…' : '确认保存范围'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final AuthState auth = await ref.read(authControllerProvider.future);
    final String? userId = auth.user?.userId;
    if (userId == null) {
      setState(() => message = '登录状态已失效，请重新登录');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    final HealthCloudConsent consent = HealthCloudConsent(
      includeHeight: height,
      includeWeight: weight,
      includeInjuries: injuries,
      documentVersion: _healthConsentVersion,
    );
    try {
      final FirstRunOnboardingController controller =
          ref.read(firstRunOnboardingControllerProvider.notifier);
      if (ref.read(firstRunOnboardingControllerProvider).requireValue.stage ==
          OnboardingStage.login) {
        await controller.bindAuthenticatedUser(userId);
      }
      final FirstRunDraft draft =
          ref.read(firstRunOnboardingControllerProvider).requireValue;
      await FirstRunRemoteApi(ref.read(authenticatedApiClientProvider))
          .saveConfirmedProfile(userId: userId, draft: draft, consent: consent);
      await controller.confirmCloudConsent(consent);
      if (mounted) context.go(AppRoutes.welcomeMembership);
    } catch (error) {
      if (mounted) {
        setState(() {
          busy = false;
          message =
              error is ApiException ? error.message : '档案尚未保存，本地草稿仍在，请稍后重试。';
        });
      }
    }
  }
}

class MembershipWelcomePage extends ConsumerWidget {
  const MembershipWelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MembershipUiState> async =
        ref.watch(membershipControllerProvider);
    final MembershipUiState? value = async.value;
    final String price = value?.product?.price ?? 'App Store 实际价格';
    final bool eligible = value?.introductoryOfferEligible == true;
    final bool showIosPurchaseActions =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return TrainFlowPage(
      title: '解锁个性化计划',
      layout: TrainFlowPageLayout.form,
      subtitle: '4/4 · 订阅可随时在 Apple 账号中管理',
      eyebrow: '${AppBrand.displayName} 月度会员',
      artwork: const TrainMateIllustration(
        assetPath: 'assets/images/trainmate_growth_scene.png',
        semanticLabel: '循序渐进的训练成长插画',
        fallback: TrainMateBrandmark(size: 68),
      ),
      includeDisclaimer: false,
      children: <Widget>[
        const TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('会员权益',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
              SizedBox(height: 10),
              Text('• AI个性化计划\n• 月度更新\n• 动态重排\n• 训练依据说明'),
            ],
          ),
        ),
        TrainFlowCard(
          child: Column(
            children: <Widget>[
              Text(
                eligible ? '7天免费试用，之后 $price/月' : '$price/月',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('订阅会自动续费；不订阅仍可浏览动作库、已有计划和历史数据。'),
              const SizedBox(height: 16),
              if (showIosPurchaseActions)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: value?.canPurchase == true
                        ? () => ref
                            .read(membershipControllerProvider.notifier)
                            .purchase()
                        : null,
                    child: Text(eligible ? '免费试用7天，之后$price/月' : '以$price/月订阅'),
                  ),
                ),
              const SizedBox(height: 8),
              if (showIosPurchaseActions)
                TextButton(
                  onPressed: value?.busy == true
                      ? null
                      : () => ref
                          .read(membershipControllerProvider.notifier)
                          .restore(),
                  child: const Text('恢复购买'),
                ),
              if (showIosPurchaseActions)
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(
                      'https://apps.apple.com/account/subscriptions')),
                  child: const Text('管理订阅'),
                ),
              TextButton(
                onPressed: () => _enterBrowseMode(context, ref),
                child: const Text('暂不订阅，进入浏览模式'),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: <Widget>[
                  TextButton(
                      onPressed: () => context.push(AppRoutes.terms),
                      child: const Text('服务协议')),
                  TextButton(
                      onPressed: () => context.push(AppRoutes.privacy),
                      child: const Text('隐私政策')),
                ],
              ),
              if (value?.message != null) Text(value!.message!),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _enterBrowseMode(BuildContext context, WidgetRef ref) async {
    await ref.read(firstRunOnboardingControllerProvider.notifier).complete();
    if (context.mounted) context.go(AppRoutes.dashboard);
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.text, required this.onSpeak});

  final String text;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(
              onPressed: onSpeak,
              tooltip: '朗读提示',
              icon: const Icon(Icons.volume_up_outlined)),
        ],
      ),
    );
  }
}
