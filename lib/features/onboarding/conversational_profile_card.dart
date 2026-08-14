import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/ai_artifact.dart';
import '../../data/models/profile_proposal.dart';
import '../../data/models/user_profile.dart';
import '../ai_center/application/voice_input_gateway.dart';
import '../ai_center/data/ai_api.dart';
import 'application/profile_privacy_parser.dart';
import 'data/sensitive_profile_draft_store.dart';

class ProfileDraftPatch {
  final String? trainingGoal;
  final MainSport? primarySport;
  final TrainingExperienceLevel? experienceLevel;
  final int? weeklyTrainingDays;
  final int? availableMinutes;
  final EquipmentAccessType? equipmentAccessType;
  final int? declaredAge;
  final double? heightCm;
  final double? weightKg;
  final List<String>? injuryHistory;

  const ProfileDraftPatch({
    this.trainingGoal,
    this.primarySport,
    this.experienceLevel,
    this.weeklyTrainingDays,
    this.availableMinutes,
    this.equipmentAccessType,
    this.declaredAge,
    this.heightCm,
    this.weightKg,
    this.injuryHistory,
  });

  bool get isEmpty =>
      trainingGoal == null &&
      primarySport == null &&
      experienceLevel == null &&
      weeklyTrainingDays == null &&
      availableMinutes == null &&
      equipmentAccessType == null &&
      declaredAge == null &&
      heightCm == null &&
      weightKg == null &&
      (injuryHistory == null || injuryHistory!.isEmpty);

  ProfileDraftPatch merge(ProfileDraftPatch other) => ProfileDraftPatch(
        trainingGoal: other.trainingGoal ?? trainingGoal,
        primarySport: other.primarySport ?? primarySport,
        experienceLevel: other.experienceLevel ?? experienceLevel,
        weeklyTrainingDays: other.weeklyTrainingDays ?? weeklyTrainingDays,
        availableMinutes: other.availableMinutes ?? availableMinutes,
        equipmentAccessType: other.equipmentAccessType ?? equipmentAccessType,
        declaredAge: other.declaredAge ?? declaredAge,
        heightCm: other.heightCm ?? heightCm,
        weightKg: other.weightKg ?? weightKg,
        injuryHistory: other.injuryHistory ?? injuryHistory,
      );

  factory ProfileDraftPatch.fromFields(Map<String, dynamic> fields) {
    final Object? equipment = fields['equipment_access'];
    return ProfileDraftPatch(
      trainingGoal: _goalLabel(fields['goal'] as String?),
      primarySport: _mainSport(fields['primary_sport'] as String?),
      experienceLevel: _experienceLevel(fields['experience_level'] as String?),
      weeklyTrainingDays: fields['weekly_training_days'] as int?,
      availableMinutes: fields['available_minutes'] as int?,
      equipmentAccessType: equipment is List
          ? _equipmentAccess(equipment.whereType<String>().toList())
          : null,
    );
  }

  factory ProfileDraftPatch.fromSensitive(ProfileSensitiveDraft draft) {
    return ProfileDraftPatch(
      declaredAge: draft.declaredAge,
      heightCm: draft.heightCm,
      weightKg: draft.weightKg,
      injuryHistory: draft.painOrInjuryNote == null
          ? null
          : <String>[draft.painOrInjuryNote!],
    );
  }

  Map<String, String> get previewRows => <String, String>{
        if (trainingGoal != null) '目标': trainingGoal!,
        if (primarySport != null) '主项目': primarySport!.label,
        if (experienceLevel != null) '经验': experienceLevel!.label,
        if (weeklyTrainingDays != null) '每周训练': '$weeklyTrainingDays 天',
        if (availableMinutes != null) '单次可用': '$availableMinutes 分钟',
        if (equipmentAccessType != null) '器械条件': equipmentAccessType!.label,
        if (declaredAge != null) '年龄（仅本机）': '$declaredAge 岁',
        if (heightCm != null) '身高（仅本机）': '${_numberLabel(heightCm!)} cm',
        if (weightKg != null) '体重（仅本机）': '${_numberLabel(weightKg!)} kg',
        if (injuryHistory != null && injuryHistory!.isNotEmpty)
          '疼痛与伤病（仅本机）': injuryHistory!.join('、'),
      };
}

class ConversationalProfileCard extends ConsumerStatefulWidget {
  final ValueChanged<ProfileDraftPatch> onConfirmed;

  const ConversationalProfileCard({
    required this.onConfirmed,
    super.key,
  });

  @override
  ConsumerState<ConversationalProfileCard> createState() =>
      _ConversationalProfileCardState();
}

class _ConversationalProfileCardState
    extends ConsumerState<ConversationalProfileCard>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ProfilePrivacyParser _parser = const ProfilePrivacyParser();
  late final VoiceInputGateway _voice;
  ProfileLocalExtraction? _extraction;
  ProfileProposal? _proposal;
  ProfileDraftPatch _patch = const ProfileDraftPatch();
  ProfileSensitiveDraft _sensitiveDraft = const ProfileSensitiveDraft();
  final Map<String, String> _followUpAnswers = <String, String>{};
  bool _loading = false;
  bool _listening = false;
  String _status = '先在本机识别训练偏好；敏感信息不会上传。';

  @override
  void initState() {
    super.initState();
    _voice = createVoiceInputGateway();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreSensitiveDraft());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_cancelVoice());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_voice.cancelListening());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ProfileLocalExtraction? extraction = _extraction;
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '对话式建档（可选）',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '可以描述目标、主项目、经验、频次、时长和器械。'
            '年龄、身体指标、疼痛、伤病和联系方式只在本机识别并移除。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('profile-conversation-input'),
            controller: _controller,
            minLines: 2,
            maxLines: 4,
            maxLength: 600,
            enabled: !_loading,
            decoration: const InputDecoration(
              hintText: '例如：跑步初学者，每周 3 天，每次 45 分钟，有哑铃',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_voice.isSupported) ...[
                IconButton.filledTonal(
                  tooltip: _listening ? '停止本机语音识别' : '开始本机语音识别',
                  onPressed: _loading ? null : _toggleVoice,
                  icon: Icon(_listening ? Icons.stop : Icons.mic_none),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton.icon(
                  key: const Key('profile-conversation-analyze'),
                  onPressed: _loading ? null : _analyze,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(_loading ? '正在整理…' : '整理为画像提议'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (extraction != null &&
              extraction.sensitiveFieldCodes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '仅保存在本机：${extraction.sensitiveFieldCodes.map(_sensitiveLabel).join('、')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warningDark,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (extraction != null &&
              extraction.followUpQuestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),
            Text(
              '还需要确认',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final ProfileFollowUpQuestion question
                in extraction.followUpQuestions) ...[
              DropdownButtonFormField<String>(
                key: Key('profile-follow-up-${question.fieldCode}'),
                initialValue: _followUpAnswers[question.fieldCode],
                decoration: InputDecoration(labelText: question.prompt),
                items: <DropdownMenuItem<String>>[
                  for (final ProfileFollowUpOption option in question.options)
                    DropdownMenuItem<String>(
                      value: option.value,
                      child: Text(option.label),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (String? value) {
                        if (value != null) {
                          _applyFollowUpAnswer(question.fieldCode, value);
                        }
                      },
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (!_patch.isEmpty || !_sensitiveDraft.isEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 6),
            Text(
              '待你确认',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final MapEntry<String, String> row in _patch
                .merge(ProfileDraftPatch.fromSensitive(_sensitiveDraft))
                .previewRows
                .entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${row.key}：${row.value}'),
              ),
            if (_proposal != null &&
                _proposal!.followUpCodes.isNotEmpty &&
                (extraction?.followUpQuestions.isEmpty ?? true)) ...[
              const SizedBox(height: 4),
              Text(
                '仍需补充：${_proposal!.followUpCodes.map(_followUpLabel).join('、')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('profile-conversation-confirm'),
                onPressed: _loading ? null : _confirmPatch,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('确认并填入下方草稿'),
              ),
            ),
            Text(
              '这里只更新页面草稿；仍需点击页面底部“确认资料并生成计划”才会正式保存。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _analyze() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _status = '请先输入一段训练偏好。');
      return;
    }
    final ProfileLocalExtraction extraction = _parser.parse(text);
    ProfileDraftPatch patch =
        ProfileDraftPatch.fromFields(extraction.knownFields);
    final ProfileSensitiveDraft sensitive =
        _sensitiveDraft.merge(extraction.localSensitiveDraft);
    if (!sensitive.isEmpty) {
      try {
        await ref.read(sensitiveProfileDraftStoreProvider).save(sensitive);
      } on Object {
        if (!mounted) return;
        setState(() => _status = '本机加密草稿暂不可用，请改用下方表单手动确认。');
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _extraction = extraction;
      _proposal = null;
      _patch = patch;
      _sensitiveDraft = sensitive;
      _followUpAnswers.clear();
      _status = extraction.requiresCloudProposal
          ? '本地字段已提取，正在为剩余歧义生成提议…'
          : '已完成本地整理，没有上传原文。';
    });
    if (!extraction.requiresCloudProposal) {
      setState(() => _loading = false);
      return;
    }
    try {
      final ProfileProposal proposal =
          await ref.read(aiApiProvider).proposeProfile(
                extraction.toRequest(
                  requestId: 'profile-${DateTime.now().microsecondsSinceEpoch}',
                ),
              );
      final Map<String, dynamic> proposed = <String, dynamic>{
        for (final ProposedProfileField field in proposal.proposedFields)
          field.fieldCode: field.value,
      };
      patch = patch.merge(ProfileDraftPatch.fromFields(proposed));
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _patch = patch;
        _loading = false;
        _status = proposal.generationMode == 'local_safe_fallback'
            ? '云端不可用，已退回本地表单补充。'
            : '画像提议已生成，确认前不会修改档案。';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '画像提议暂不可用，请继续使用下方表单；现有资料没有改变。';
      });
    }
  }

  Future<void> _confirmPatch() async {
    if (_patch.isEmpty && _sensitiveDraft.isEmpty) return;
    final ProfileProposal? proposal = _proposal;
    if (proposal != null) {
      setState(() => _loading = true);
      try {
        await ref.read(aiApiProvider).decide(
              artifactId: proposal.artifactId,
              decision: AiArtifactDecision.accepted,
            );
      } on Object {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _status = '确认同步失败，草稿没有改变，请稍后重试或手动填写。';
        });
        return;
      }
    }
    final ProfileDraftPatch confirmed =
        _patch.merge(ProfileDraftPatch.fromSensitive(_sensitiveDraft));
    if (!_sensitiveDraft.isEmpty) {
      try {
        await ref.read(sensitiveProfileDraftStoreProvider).clear();
      } on Object {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _status = '本机敏感草稿清理失败，资料没有写入正式草稿，请稍后重试。';
        });
        return;
      }
    }
    widget.onConfirmed(confirmed);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _proposal = null;
      _patch = const ProfileDraftPatch();
      _sensitiveDraft = const ProfileSensitiveDraft();
      _status = '已填入下方草稿，正式保存仍由你在页面底部确认。';
    });
  }

  Future<void> _restoreSensitiveDraft() async {
    try {
      final ProfileSensitiveDraft? restored =
          await ref.read(sensitiveProfileDraftStoreProvider).load();
      if (!mounted || restored == null || restored.isEmpty) return;
      setState(() {
        _sensitiveDraft = restored;
        _status = '已恢复上次保存在本机的敏感草稿；确认前不会写入正式档案。';
      });
    } on Object {
      // 测试环境或系统钥匙串不可用时保持内存态，不影响手动表单。
    }
  }

  void _applyFollowUpAnswer(String fieldCode, String value) {
    final Map<String, dynamic> field = <String, dynamic>{
      fieldCode: switch (fieldCode) {
        'weekly_training_days' || 'available_minutes' => int.parse(value),
        'equipment_access' => <String>[value],
        _ => value,
      },
    };
    setState(() {
      _followUpAnswers[fieldCode] = value;
      _patch = _patch.merge(ProfileDraftPatch.fromFields(field));
    });
  }

  Future<void> _toggleVoice() async {
    try {
      if (!_listening) {
        await _voice.startListening();
        if (!mounted) return;
        setState(() {
          _listening = true;
          _status = '正在本机识别；音频不会上传。';
        });
        return;
      }
      final String transcript = await _voice.stopListening();
      if (!mounted) return;
      setState(() {
        _listening = false;
        if (transcript.trim().isEmpty) {
          _status = '没有识别到文字，请重试或直接输入。';
          return;
        }
        _controller.text = transcript.trim();
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
        _status = '识别完成，请核对文字后再整理。';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _status = '本机语音识别不可用，请检查权限或直接输入。';
      });
    }
  }

  Future<void> _cancelVoice() async {
    if (!_listening) return;
    await _voice.cancelListening();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _status = '语音识别已停止，未上传任何音频。';
    });
  }
}

String? _goalLabel(String? value) => switch (value) {
      'fat_loss' => '低冲击、可持续减脂',
      'strength' => '提升力量与肌肉能力',
      'endurance' => '提升基础耐力',
      'race_preparation' => '为目标赛事稳定备赛',
      'general_fitness' => '建立稳定、可恢复的训练习惯',
      _ => null,
    };

MainSport? _mainSport(String? value) => switch (value) {
      'running' => MainSport.marathon,
      'strength' => MainSport.strength,
      'hyrox' => MainSport.hyrox,
      'general_fitness' => MainSport.generalFitness,
      _ => null,
    };

TrainingExperienceLevel? _experienceLevel(String? value) => switch (value) {
      'beginner' => TrainingExperienceLevel.beginner,
      'intermediate' => TrainingExperienceLevel.intermediate,
      'advanced' => TrainingExperienceLevel.advanced,
      _ => null,
    };

EquipmentAccessType? _equipmentAccess(List<String> values) {
  if (values.isEmpty) return null;
  final bool hasGym = values.contains('gym') || values.contains('barbell');
  final bool hasHome =
      values.contains('dumbbell') || values.contains('bodyweight');
  if (hasGym && hasHome) return EquipmentAccessType.mixed;
  if (hasGym) return EquipmentAccessType.gym;
  if (hasHome) {
    return values.length == 1 && values.single == 'bodyweight'
        ? EquipmentAccessType.none
        : EquipmentAccessType.basicHome;
  }
  return EquipmentAccessType.none;
}

String _sensitiveLabel(String value) => switch (value) {
      'age' => '年龄',
      'body_metrics' => '身体指标',
      'pain_or_injury' => '疼痛与伤病',
      'contact' => '联系方式',
      _ => '敏感信息',
    };

String _followUpLabel(String value) => switch (value) {
      'ask_goal' => '你的主要目标是什么',
      'ask_primary_sport' => '你主要想练什么项目',
      'ask_experience' => '你的训练经验如何',
      'ask_frequency' => '每周可训练几天',
      'ask_duration' => '单次可用多长时间',
      'ask_equipment' => '可以使用哪些器械',
      _ => '请继续补充训练偏好',
    };

String _numberLabel(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
