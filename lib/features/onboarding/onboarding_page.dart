import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_branding.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/user_profile.dart';
import '../profile/application/user_profile_controller.dart';
import 'conversational_profile_card.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  late UserProfile _draftProfile;
  String? _maxHeartRateError;

  @override
  void initState() {
    super.initState();
    _draftProfile = ref.read(userProfileControllerProvider).profile;
  }

  @override
  Widget build(BuildContext context) {
    final UserProfile profile = _draftProfile;
    final MainSport primarySport = profile.mainSports.isEmpty
        ? MainSport.generalFitness
        : profile.mainSports.first;
    final MainSport? secondarySport =
        profile.mainSports.length > 1 ? profile.mainSports[1] : null;
    final List<int> minuteOptions = <int>{
      20,
      30,
      45,
      60,
      75,
      90,
      profile.dailyAvailableMinutes,
    }.toList()
      ..sort();

    return TrainFlowPage(
      title: '基础资料',
      layout: TrainFlowPageLayout.form,
      subtitle: '完善档案，选择一个主目标和一个可选次目标，生成滚动 4 周计划。',
      animateChildren: true,
      eyebrow: '认识你的训练节奏',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateCharacterAvatar(
        action: TrainMateAction.pointingGuide,
      ),
      children: [
        TrainFlowCard(
          tone: TrainFlowCardTone.peach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用户档案',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('onboarding-name-field'),
                initialValue: profile.name,
                decoration: const InputDecoration(labelText: '昵称'),
                textInputAction: TextInputAction.next,
                onChanged: (String value) {
                  _updateProfile(name: value.trim());
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '${profile.age}',
                      decoration: const InputDecoration(labelText: '年龄'),
                      keyboardType: TextInputType.number,
                      onChanged: (String value) {
                        final int? parsed = int.tryParse(value);
                        if (parsed != null && parsed > 0) {
                          _updateProfile(age: parsed.clamp(1, 120).toInt());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<Gender>(
                      initialValue: profile.gender,
                      decoration: const InputDecoration(labelText: '性别'),
                      items: [
                        for (final Gender gender in Gender.values)
                          DropdownMenuItem<Gender>(
                            value: gender,
                            child: Text(_genderLabel(gender)),
                          ),
                      ],
                      onChanged: (Gender? value) {
                        if (value != null) {
                          _updateProfile(gender: value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (profile.gender == Gender.male ||
                  profile.gender == Gender.female) ...[
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  key: const Key('onboarding-ai-biological-sex-consent'),
                  contentPadding: EdgeInsets.zero,
                  value: profile.allowBiologicalSexInAiPlanning,
                  title: const Text('允许将性别用于 AI 计划生成'),
                  subtitle: const Text(
                    '开启后，生成云端计划时会把性别（仅「男」或「女」）随请求发送。'
                    '关闭时性别只在本地使用，不会离开设备。可随时关闭。',
                  ),
                  onChanged: (bool value) {
                    _updateProfile(allowBiologicalSexInAiPlanning: value);
                  },
                ),
              ],
              const SizedBox(height: 12),
              ConversationalProfileCard(
                onConfirmed: _applyProfilePatch,
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: profile.birthDate == null
                    ? '选择生日，用于计算状态年龄'
                    : '生日 ${_formatDate(profile.birthDate!)}，点击修改',
                child: OutlinedButton.icon(
                  key: const Key('onboarding-birth-date-button'),
                  onPressed: () => _pickBirthDate(profile),
                  icon: const Icon(Icons.cake_outlined),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      profile.birthDate == null
                          ? '选择生日（用于状态年龄）'
                          : '生日：${_formatDate(profile.birthDate!)}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '状态年龄是长期行为与健康趋势的训练参考，不是医学年龄。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: profile.heightCm.toStringAsFixed(0),
                      decoration: const InputDecoration(labelText: '身高（cm）'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (String value) {
                        final double? parsed = double.tryParse(value);
                        if (parsed != null && parsed > 0) {
                          _updateProfile(
                            heightCm: parsed.clamp(80, 250).toDouble(),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      initialValue: profile.weightKg.toStringAsFixed(0),
                      decoration: const InputDecoration(labelText: '体重（kg）'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (String value) {
                        final double? parsed = double.tryParse(value);
                        if (parsed != null && parsed > 0) {
                          _updateProfile(
                            weightKg: parsed.clamp(20, 350).toDouble(),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('onboarding-max-heart-rate-field'),
                initialValue: profile.maxHeartRate?.toString() ?? '',
                decoration: InputDecoration(
                  labelText: '最大心率（可选）',
                  hintText: '仅填写本人实测值',
                  helperText: '用于训练负荷计算；不根据年龄或单次训练峰值猜测。',
                  errorText: _maxHeartRateError,
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: _updateMaxHeartRate,
              ),
              const SizedBox(height: 20),
              Text(
                '运动目标',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('onboarding-target-field'),
                initialValue: profile.trainingGoal,
                decoration: const InputDecoration(
                  labelText: '目标描述',
                  hintText: '例如：10 公里稳定跑进 55 分钟',
                ),
                onChanged: (String value) {
                  _updateProfile(trainingGoal: value.trim());
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MainSport>(
                key: const Key('onboarding-primary-goal'),
                initialValue: primarySport,
                decoration: const InputDecoration(labelText: '主目标'),
                items: [
                  for (final MainSport sport in MainSport.values)
                    DropdownMenuItem<MainSport>(
                      value: sport,
                      child: Text(sport.label),
                    ),
                ],
                onChanged: (MainSport? value) {
                  if (value != null) {
                    final List<MainSport> sports = <MainSport>[value];
                    if (secondarySport != null && secondarySport != value) {
                      sports.add(secondarySport);
                    }
                    _updateProfile(mainSports: sports);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('onboarding-secondary-goal'),
                initialValue: secondarySport?.jsonValue ?? 'none',
                decoration: const InputDecoration(labelText: '次目标（可选）'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: 'none',
                    child: Text('无次目标'),
                  ),
                  for (final MainSport sport in MainSport.values)
                    if (sport != primarySport)
                      DropdownMenuItem<String>(
                        value: sport.jsonValue,
                        child: Text(sport.label),
                      ),
                ],
                onChanged: (String? value) {
                  if (value == null || value == 'none') {
                    _updateProfile(mainSports: <MainSport>[primarySport]);
                    return;
                  }
                  final MainSport selected = MainSport.values.firstWhere(
                    (MainSport sport) => sport.jsonValue == value,
                  );
                  _updateProfile(
                    mainSports: <MainSport>[primarySport, selected],
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TrainingExperienceLevel>(
                key: const Key('onboarding-experience-level'),
                initialValue: profile.trainingExperienceLevel,
                decoration: const InputDecoration(labelText: '训练经验'),
                items: [
                  for (final TrainingExperienceLevel level
                      in TrainingExperienceLevel.values)
                    DropdownMenuItem<TrainingExperienceLevel>(
                      value: level,
                      child: Text(level.label),
                    ),
                ],
                onChanged: (TrainingExperienceLevel? value) {
                  if (value != null) {
                    _updateProfile(trainingExperienceLevel: value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: profile.weeklyTrainingDays,
                      decoration: const InputDecoration(labelText: '每周训练'),
                      items: [
                        for (int days = 1; days <= 7; days += 1)
                          DropdownMenuItem<int>(
                            value: days,
                            child: Text('$days 天'),
                          ),
                      ],
                      onChanged: (int? value) {
                        if (value != null) {
                          _updateProfile(weeklyTrainingDays: value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: profile.dailyAvailableMinutes,
                      decoration: const InputDecoration(labelText: '单次可用'),
                      items: [
                        for (final int minutes in minuteOptions)
                          DropdownMenuItem<int>(
                            value: minutes,
                            child: Text('$minutes 分钟'),
                          ),
                      ],
                      onChanged: (int? value) {
                        if (value != null) {
                          _updateProfile(dailyAvailableMinutes: value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<WorkerProfileType>(
                initialValue: profile.workerProfileType,
                decoration: const InputDecoration(labelText: '职业 / 生活分型'),
                items: [
                  for (final WorkerProfileType type in WorkerProfileType.values)
                    DropdownMenuItem<WorkerProfileType>(
                      value: type,
                      child: Text(type.label),
                    ),
                ],
                onChanged: (WorkerProfileType? value) {
                  if (value != null) {
                    setState(() {
                      _draftProfile =
                          _draftProfile.copyWith(workerProfileType: value);
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                '分型策略：${profile.workerProfileType.strategy}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EquipmentAccessType>(
                initialValue: profile.equipmentAccessType,
                decoration: const InputDecoration(labelText: '器械条件'),
                items: [
                  for (final EquipmentAccessType access
                      in EquipmentAccessType.values)
                    DropdownMenuItem<EquipmentAccessType>(
                      value: access,
                      child: Text(access.label),
                    ),
                ],
                onChanged: (EquipmentAccessType? value) {
                  if (value != null) {
                    setState(() {
                      _draftProfile = _draftProfile.copyWith(
                        equipmentAccessType: value,
                      );
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                '器械条件会参与今日训练替代；没有器械时不会继续安排必须使用器械的动作。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<WorkScheduleType>(
                initialValue: profile.workScheduleType,
                decoration: const InputDecoration(labelText: '作息类型'),
                items: [
                  for (final WorkScheduleType type in WorkScheduleType.values)
                    DropdownMenuItem<WorkScheduleType>(
                      value: type,
                      child: Text(type.label),
                    ),
                ],
                onChanged: (WorkScheduleType? value) {
                  if (value != null) {
                    setState(() {
                      _draftProfile =
                          _draftProfile.copyWith(workScheduleType: value);
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: profile.injuryHistory.join('、'),
                decoration: const InputDecoration(
                  labelText: '伤病史（可选）',
                  hintText: '用逗号分隔；没有可留空',
                ),
                onChanged: (String value) {
                  _updateProfile(
                    injuryHistory: value
                        .split(RegExp(r'[,，、\n]'))
                        .map((String item) => item.trim())
                        .where((String item) => item.isNotEmpty)
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                '分型只用于调整训练重点和表达方式，不替代疼痛红线、准备度和每日反馈等安全规则。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _maxHeartRateError == null
                      ? () {
                          final UserProfile confirmedProfile = profile.copyWith(
                            name: profile.name.trim().isEmpty
                                ? '训练者'
                                : profile.name.trim(),
                            trainingGoal: profile.trainingGoal.trim().isEmpty
                                ? '建立稳定、可恢复的训练习惯'
                                : profile.trainingGoal.trim(),
                          );
                          ref
                              .read(userProfileControllerProvider.notifier)
                              .save(confirmedProfile);
                          context.go(AppRoutes.dashboard);
                        }
                      : null,
                  child: const Text('确认资料并生成计划'),
                ),
              ),
              const SizedBox(height: 96),
            ],
          ),
        ),
      ],
    );
  }

  void _updateProfile({
    String? name,
    Gender? gender,
    int? age,
    DateTime? birthDate,
    double? heightCm,
    double? weightKg,
    int? maxHeartRate,
    bool clearMaxHeartRate = false,
    String? trainingGoal,
    List<MainSport>? mainSports,
    TrainingExperienceLevel? trainingExperienceLevel,
    int? weeklyTrainingDays,
    int? dailyAvailableMinutes,
    List<String>? injuryHistory,
    EquipmentAccessType? equipmentAccessType,
    bool? allowBiologicalSexInAiPlanning,
  }) {
    setState(() {
      // 性别改成「其他」或「暂不填写」时同时撤回授权，避免残留一个已经无从展示、
      // 用户也无法再关掉的 true。
      final bool? revokedConsent =
          gender == Gender.other || gender == Gender.unknown ? false : null;
      _draftProfile = _draftProfile.copyWith(
        name: name,
        gender: gender,
        age: age,
        birthDate: birthDate,
        heightCm: heightCm,
        weightKg: weightKg,
        maxHeartRate: maxHeartRate,
        clearMaxHeartRate: clearMaxHeartRate,
        trainingGoal: trainingGoal,
        mainSports: mainSports,
        trainingExperienceLevel: trainingExperienceLevel,
        weeklyTrainingDays: weeklyTrainingDays,
        dailyAvailableMinutes: dailyAvailableMinutes,
        injuryHistory: injuryHistory,
        equipmentAccessType: equipmentAccessType,
        allowBiologicalSexInAiPlanning:
            allowBiologicalSexInAiPlanning ?? revokedConsent,
      );
    });
  }

  void _applyProfilePatch(ProfileDraftPatch patch) {
    final MainSport? primarySport = patch.primarySport;
    final List<MainSport>? sports = primarySport == null
        ? null
        : <MainSport>[
            primarySport,
            ..._draftProfile.mainSports.where(
              (MainSport sport) => sport != primarySport,
            ),
          ].take(2).toList(growable: false);
    _updateProfile(
      trainingGoal: patch.trainingGoal,
      mainSports: sports,
      trainingExperienceLevel: patch.experienceLevel,
      weeklyTrainingDays: patch.weeklyTrainingDays,
      dailyAvailableMinutes: patch.availableMinutes,
      equipmentAccessType: patch.equipmentAccessType,
      age: patch.declaredAge,
      heightCm: patch.heightCm,
      weightKg: patch.weightKg,
      injuryHistory: patch.injuryHistory,
    );
  }

  Future<void> _pickBirthDate(UserProfile profile) async {
    final DateTime now = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: profile.birthDate ??
          DateTime(now.year - profile.age.clamp(1, 120), now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: DateTime(now.year - 1, now.month, now.day),
      helpText: '选择生日',
      cancelText: '取消',
      confirmText: '确认',
    );
    if (selected == null || !mounted) return;
    final int age = now.year -
        selected.year -
        ((now.month < selected.month ||
                (now.month == selected.month && now.day < selected.day))
            ? 1
            : 0);
    _updateProfile(
      birthDate: selected,
      age: age.clamp(1, 120).toInt(),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  void _updateMaxHeartRate(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      setState(() {
        _maxHeartRateError = null;
        _draftProfile = _draftProfile.copyWith(clearMaxHeartRate: true);
      });
      return;
    }
    final int? parsed = int.tryParse(normalized);
    if (parsed == null || parsed < 80 || parsed > 240) {
      setState(() {
        _maxHeartRateError = '请输入 80–240 次/分钟的本人实测值，或留空。';
      });
      return;
    }
    setState(() {
      _maxHeartRateError = null;
      _draftProfile = _draftProfile.copyWith(maxHeartRate: parsed);
    });
  }

  String _genderLabel(Gender gender) => switch (gender) {
        Gender.male => '男',
        Gender.female => '女',
        Gender.other => '其他',
        Gender.unknown => '暂不填写',
      };
}
