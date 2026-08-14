import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/meal_guide.dart';
import '../../data/models/body_rhythm.dart';
import '../dashboard/training_mvp_controller.dart';
import '../rhythm/application/body_rhythm_controller.dart';
import 'application/meal_preference_controller.dart';

class MealGuidePage extends ConsumerWidget {
  const MealGuidePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final MealScenario mealScenario = ref.watch(
      mealPreferenceControllerProvider.select(
        (MealPreference preference) => preference.scenario,
      ),
    );
    final MealGuide activeGuide = state.activeMealGuide;
    final AsyncValue<BodyRhythmState> rhythm =
        ref.watch(bodyRhythmControllerProvider);

    return TrainFlowPage(
      title: '照吃指令卡',
      layout: TrainFlowPageLayout.form,
      subtitle: '不记录热量，只给今天最容易执行的一条饮食指令。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.profile,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.treePoseBalance,
        backgroundColor: AppColors.primary,
      ),
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '吃饭场景',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MealScenario>(
                initialValue: mealScenario,
                decoration: const InputDecoration(labelText: '今天怎么吃'),
                items: [
                  for (final MealScenario scenario in MealScenario.values)
                    DropdownMenuItem<MealScenario>(
                      value: scenario,
                      child: Text(scenario.label),
                    ),
                ],
                onChanged: (MealScenario? value) {
                  if (value != null) {
                    ref
                        .read(mealPreferenceControllerProvider.notifier)
                        .saveScenario(value);
                  }
                },
              ),
            ],
          ),
        ),
        _MealRecordCard(rhythm: rhythm),
        _MealGuideCard(guide: activeGuide),
        const SectionTitle(title: '三种场景模板'),
        for (final MealGuide guide in state.mealGuides)
          _MealGuideSummaryCard(guide: guide),
      ],
    );
  }
}

class _MealRecordCard extends ConsumerWidget {
  const _MealRecordCard({required this.rhythm});

  final AsyncValue<BodyRhythmState> rhythm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int recordedDays = switch (rhythm) {
      AsyncData<BodyRhythmState>(:final value) => value.reviewStatus.dietDays,
      _ => 0,
    };
    final bool canPersist = switch (rhythm) {
      AsyncData<BodyRhythmState>(:final value) => value.canPersist,
      _ => false,
    };
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '记录这一餐',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              ToneBadge(label: '近 15 天 $recordedDays/7 天'),
            ],
          ),
          const SizedBox(height: 8),
          const Text('选择餐次并写下实际吃了什么，不能只打卡。'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('add-meal-record-button'),
              onPressed: canPersist
                  ? () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (BuildContext context) =>
                            const _MealRecordSheet(),
                      )
                  : null,
              icon: const Icon(Icons.add),
              label: Text(canPersist ? '添加真实饮食记录' : '存储恢复中，暂不可记录'),
            ),
          ),
          if (rhythm case AsyncData<BodyRhythmState>(:final value))
            for (final MealRecord record in value.mealRecords.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${record.mealType.label} · ${record.summary}'),
                subtitle: Text(
                  '${record.localDate.month}月${record.localDate.day}日',
                ),
                trailing: IconButton(
                  tooltip: '撤销这条饮食记录',
                  onPressed: () async {
                    await ref
                        .read(bodyRhythmControllerProvider.notifier)
                        .revokeMeal(record.id);
                  },
                  icon: const Icon(Icons.undo),
                ),
              ),
        ],
      ),
    );
  }
}

class _MealRecordSheet extends ConsumerStatefulWidget {
  const _MealRecordSheet();

  @override
  ConsumerState<_MealRecordSheet> createState() => _MealRecordSheetState();
}

class _MealRecordSheetState extends ConsumerState<_MealRecordSheet> {
  final TextEditingController _summaryController = TextEditingController();
  MealType _mealType = MealType.lunch;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '记录这一餐',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<MealType>(
              initialValue: _mealType,
              decoration: const InputDecoration(labelText: '餐次'),
              items: [
                for (final MealType type in MealType.values)
                  DropdownMenuItem<MealType>(
                    value: type,
                    child: Text(type.label),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (MealType? value) {
                      if (value != null) setState(() => _mealType = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('meal-record-summary-field'),
              controller: _summaryController,
              enabled: !_saving,
              maxLength: 80,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '实际吃了什么',
                hintText: '例如：鸡蛋、牛肉、米饭和一份蔬菜',
                errorText: _errorMessage,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final String summary = _summaryController.text.trim();
    if (summary.isEmpty) {
      setState(() => _errorMessage = '请填写这一餐实际吃了什么。');
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await ref.read(bodyRhythmControllerProvider.notifier).saveMeal(
            mealType: _mealType,
            summary: summary,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = '保存失败，请稍后重试。';
      });
    }
  }
}

class _MealGuideCard extends StatelessWidget {
  final MealGuide guide;

  const _MealGuideCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  guide.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: guide.dayLabel, color: AppColors.secondary),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(label: '今天照吃', value: guide.instruction),
          InfoRow(label: '公式', value: guide.formula),
          InfoRow(label: '只加一件事', value: guide.addOneThing),
          InfoRow(label: '避开', value: guide.avoidItems.join('、')),
          const SizedBox(height: 8),
          Text(
            guide.reason,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          _EvidenceBlock(sources: guide.evidenceSources),
        ],
      ),
    );
  }
}

class _MealGuideSummaryCard extends StatelessWidget {
  final MealGuide guide;

  const _MealGuideSummaryCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      child: Row(
        children: [
          ToneBadge(label: guide.scenario.label),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              guide.instruction,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceBlock extends StatelessWidget {
  final List<EvidenceSource> sources;

  const _EvidenceBlock({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '依据来源',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final EvidenceSource source in sources) ...[
          Text(
            source.citationLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text('原文片段：${source.quote}'),
          const SizedBox(height: 4),
          Text(
            '适用原因：${source.note}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (source != sources.last) const Divider(height: 18),
        ],
      ],
    );
  }
}
