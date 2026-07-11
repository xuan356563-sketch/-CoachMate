import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/race.dart';
import '../dashboard/training_mvp_controller.dart';

class RacePrepPage extends ConsumerWidget {
  const RacePrepPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final String raceImportText = ref.watch(raceImportTextProvider);

    return TrainFlowPage(
      title: '比赛备战',
      subtitle: '本地 Mock 先覆盖周期反推、赛前减量、装备建议、策略和赛后恢复。',
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'base→build→specific→taper',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  ToneBadge(label: '${state.races.length} 场'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '比赛模块当前是本地规则 MVP：不接报名平台，不做真实成绩模型，先把 races 结构、自动排期和展示闭环接进 Flutter。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        _RaceImportCard(
          importText: raceImportText,
          statusMessage: state.raceImportStatusMessage,
        ),
        for (final RacePlan race in state.races)
          _RacePlanCard(race: race, state: state),
      ],
    );
  }
}

class _RaceImportCard extends ConsumerWidget {
  final String importText;
  final String statusMessage;

  const _RaceImportCard({
    required this.importText,
    required this.statusMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '赛事导入',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const ToneBadge(label: '本地 races'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '先粘贴赛事名称、类型、日期、目标和赛道信息；导入后会写入本地 races，并使用本地规则生成周期、装备、策略和自动排期。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ref.read(raceImportTextProvider.notifier).useSample();
            },
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('使用赛事样例'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<String>(importText),
            initialValue: importText,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '赛事信息文本',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) {
              ref.read(raceImportTextProvider.notifier).setValue(value);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref
                    .read(trainingMvpProvider.notifier)
                    .importRaceText(ref.read(raceImportTextProvider));
              },
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('导入比赛'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            statusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _RacePlanCard extends StatelessWidget {
  final RacePlan race;
  final TrainingMvpState state;

  const _RacePlanCard({
    required this.race,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final RaceAutoSchedule schedule = state.raceAutoScheduleFor(race);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  race.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: race.type.label),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '比赛日期', value: race.raceDateLabel),
          InfoRow(label: '当前阶段', value: race.currentPhase),
          InfoRow(label: '目标成绩', value: race.targetResult),
          InfoRow(label: '成绩预测', value: race.predictedResult),
          InfoRow(label: '赛道信息', value: race.courseInfo),
          const SizedBox(height: 12),
          _RaceAutoScheduleBlock(schedule: schedule),
          const SizedBox(height: 12),
          _RacePhaseList(phases: race.phases),
          const SizedBox(height: 12),
          _TextListBlock(title: '赛前减量', items: race.taperPlan),
          _TextListBlock(title: '装备建议', items: race.gearAdvice),
          _RaceStrategyBlock(sections: race.strategySections),
          _TextListBlock(title: '赛后恢复', items: race.postRaceRecovery),
          _RaceEvidenceBlock(sources: race.evidenceSources),
        ],
      ),
    );
  }
}

class _RacePhaseList extends StatelessWidget {
  final List<RaceTrainingPhase> phases;

  const _RacePhaseList({required this.phases});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '周期反推',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        for (final RaceTrainingPhase phase in phases) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 82,
                child: ToneBadge(
                  label: phase.phaseType.label,
                  color: _phaseColor(phase.phaseType),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${phase.weekRange} · ${phase.focus}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phase.keyWorkouts.join(' / '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (phase != phases.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RaceAutoScheduleBlock extends StatelessWidget {
  final RaceAutoSchedule schedule;

  const _RaceAutoScheduleBlock({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final RaceAutoScheduleItem? currentItem = schedule.currentItem;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.grayLightest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '自动排期',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                ToneBadge(label: schedule.countdownLabel),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              schedule.statusLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (currentItem != null) ...[
              const SizedBox(height: 10),
              InfoRow(label: '本周阶段', value: currentItem.phaseType.label),
              InfoRow(label: '本周窗口', value: currentItem.weekLabel),
              InfoRow(label: '本周重点', value: currentItem.focus),
              const SizedBox(height: 8),
              Text(
                '自动生成任务',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final String workout in currentItem.keyWorkouts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $workout'),
                ),
              const SizedBox(height: 6),
              Text(
                '补给：${currentItem.nutritionCue}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '恢复：${currentItem.recoveryRule}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '安全门槛：${currentItem.safetyGate}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TextListBlock extends StatelessWidget {
  final String title;
  final List<String> items;

  const _TextListBlock({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final String item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RaceStrategyBlock extends StatelessWidget {
  final List<RaceStrategySection> sections;

  const _RaceStrategyBlock({required this.sections});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '比赛策略',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final RaceStrategySection section in sections) ...[
            Text(
              section.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(section.items.join(' / ')),
            if (section != sections.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _RaceEvidenceBlock extends StatelessWidget {
  final List<EvidenceSource> sources;

  const _RaceEvidenceBlock({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '依据来源',
            style: Theme.of(context)
                .textTheme
                .titleMedium
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
      ),
    );
  }
}

Color _phaseColor(RacePhaseType phaseType) {
  switch (phaseType) {
    case RacePhaseType.base:
      return AppColors.secondary;
    case RacePhaseType.build:
      return AppColors.primary;
    case RacePhaseType.specific:
      return AppColors.warningDark;
    case RacePhaseType.taper:
      return AppColors.danger;
    case RacePhaseType.raceWeek:
      return AppColors.textSecondary;
  }
}
