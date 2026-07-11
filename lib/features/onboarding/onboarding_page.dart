import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/user_profile.dart';
import '../dashboard/training_mvp_controller.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  late UserProfile _draftProfile;

  @override
  void initState() {
    super.initState();
    _draftProfile = ref.read(trainingMvpProvider).profile;
  }

  @override
  Widget build(BuildContext context) {
    final UserProfile profile = _draftProfile;

    return TrainFlowPage(
      title: '基础资料',
      subtitle: 'MVP 阶段先使用本地档案，后续再接完整问卷。',
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(label: '昵称', value: profile.name),
              InfoRow(label: '年龄', value: '${profile.age} 岁'),
              InfoRow(
                label: '身高体重',
                value: '${profile.heightCm.toStringAsFixed(0)} cm / '
                    '${profile.weightKg.toStringAsFixed(0)} kg',
              ),
              InfoRow(label: '训练目标', value: profile.trainingGoal),
              InfoRow(
                label: '主项',
                value: profile.mainSports
                    .map((MainSport sport) => sport.label)
                    .join('、'),
              ),
              InfoRow(label: '时间', value: '每周 ${profile.weeklyTrainingDays} 天'),
              InfoRow(
                label: '单次可用',
                value: '${profile.dailyAvailableMinutes} 分钟',
              ),
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
              InfoRow(
                label: '伤病史',
                value: profile.injuryHistory.join('、'),
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
                  onPressed: () {
                    ref.read(trainingMvpProvider.notifier).saveProfile(profile);
                    context.go(AppRoutes.dashboard);
                  },
                  child: const Text('确认资料并生成计划'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
