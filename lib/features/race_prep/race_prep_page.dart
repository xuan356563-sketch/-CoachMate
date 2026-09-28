import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/design_system/trainmate_primitives.dart';
import '../../core/design_system/trainmate_states.dart';
import '../../core/widgets/emp_system.dart';
import '../../core/widgets/flow_mascot.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/evidence_source.dart';
import '../../data/models/race.dart';
import '../../data/models/training_log.dart';
import '../dashboard/training_mvp_controller.dart';
import 'application/race_image_recognition_controller.dart';

FlowMascotSpec selectRaceMascotSpec({
  required bool isRecognizing,
  required bool hasRaces,
  required bool hasActiveOfficialResult,
  required RacePhaseType? phase,
  required bool needsRecovery,
}) {
  if (isRecognizing) {
    return const FlowMascotSpec(
      action: FlowMascotAction.scan,
      expression: FlowMascotExpression.focused,
      semanticLabel: 'Flow 训练伙伴正在扫描赛事图片',
      durationMilliseconds: 560,
    );
  }
  if (!hasRaces) {
    return const FlowMascotSpec(
      action: FlowMascotAction.startLine,
      expression: FlowMascotExpression.curious,
      semanticLabel: 'Flow 训练伙伴在起跑线等待赛事',
      durationMilliseconds: 520,
    );
  }
  if (hasActiveOfficialResult) {
    return const FlowMascotSpec(
      action: FlowMascotAction.celebrate,
      expression: FlowMascotExpression.happy,
      semanticLabel: 'Flow 训练伙伴庆祝正式比赛成绩',
      durationMilliseconds: 460,
      motionCycles: 2,
    );
  }
  if (needsRecovery || phase == RacePhaseType.taper) {
    return const FlowMascotSpec(
      action: FlowMascotAction.meditate,
      expression: FlowMascotExpression.calm,
      semanticLabel: 'Flow 训练伙伴提醒赛前恢复与减量',
      durationMilliseconds: 620,
    );
  }
  if (phase == RacePhaseType.raceWeek) {
    return const FlowMascotSpec(
      action: FlowMascotAction.sprint,
      expression: FlowMascotExpression.determined,
      semanticLabel: 'Flow 训练伙伴快速冲向比赛周',
      durationMilliseconds: 300,
      motionCycles: 2,
    );
  }
  return const FlowMascotSpec(
    action: FlowMascotAction.sprint,
    expression: FlowMascotExpression.determined,
    semanticLabel: 'Flow 训练伙伴稳步推进赛事备战',
    durationMilliseconds: 500,
    motionCycles: 2,
  );
}

enum RaceScheduleTab { preparing, completed }

RaceScheduleTab raceScheduleTabFor(RacePlan race) {
  return race.hasActiveOfficialRaceResult
      ? RaceScheduleTab.completed
      : RaceScheduleTab.preparing;
}

int raceDaysUntil(RacePlan race, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime raceDay =
      DateTime(race.raceDate.year, race.raceDate.month, race.raceDate.day);
  return raceDay.difference(today).inDays;
}

class RacePrepPage extends ConsumerStatefulWidget {
  const RacePrepPage({super.key});

  @override
  ConsumerState<RacePrepPage> createState() => _RacePrepPageState();
}

class _RacePrepPageState extends ConsumerState<RacePrepPage> {
  RaceScheduleTab _selectedTab = RaceScheduleTab.preparing;
  bool _isImportExpanded = false;

  @override
  Widget build(BuildContext context) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final String raceImportText = ref.watch(raceImportTextProvider);
    final AsyncValue<RaceImageRecognitionState> recognitionState =
        ref.watch(raceImageRecognitionControllerProvider);
    final bool isRecognizing = switch (recognitionState) {
      AsyncData<RaceImageRecognitionState>(:final value) => value.isBusy,
      _ => false,
    };
    final DateTime now = DateTime.now();
    final List<RacePlan> orderedRaces = _orderedRacesForTab(
      races: state.races,
      tab: _selectedTab,
      now: now,
    );
    final RacePlan? focusRace =
        orderedRaces.isEmpty ? null : orderedRaces.first;
    final RacePhaseType? focusPhase = focusRace == null
        ? null
        : state.raceAutoScheduleFor(focusRace).currentItem?.phaseType;
    final FlowMascotSpec mascotSpec = selectRaceMascotSpec(
      isRecognizing: isRecognizing,
      hasRaces: state.races.isNotEmpty,
      hasActiveOfficialResult: state.races.any(
        (RacePlan race) => race.hasActiveOfficialRaceResult,
      ),
      phase: focusPhase,
      needsRecovery:
          state.requiresMedicalAttention || (state.readinessScore != null && state.readinessScore! < 52),
    );

    return TrainFlowPage(
      title: '比赛',
      layout: TrainFlowPageLayout.detail,
      subtitle: '按比赛倒计时管理备赛节奏与正式成绩。',
      eyebrow: '赛事日程',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.plans,
      ),
      artwork: FloatingFlowMascot(size: 72, spec: mascotSpec),
      children: [
        if (orderedRaces.isNotEmpty)
          EmpIllustrationCard(
            title: '下一场挑战',
            subtitle:
                '距 ${orderedRaces.first.name} 还有 ${raceDaysUntil(orderedRaces.first, now)} 天 · 陪你科学备赛',
            bg: TrainFlowTokens.blue,
            actionLabel: '查看排期',
            onAction: () => _openRaceDetail(
              context,
              race: orderedRaces.first,
              state: state,
            ),
          ),
        const SizedBox(height: 20),
        _RaceScheduleTabs(
          selectedTab: _selectedTab,
          preparingCount: state.races
              .where((RacePlan race) => !race.hasActiveOfficialRaceResult)
              .length,
          completedCount: state.races
              .where((RacePlan race) => race.hasActiveOfficialRaceResult)
              .length,
          onChanged: (RaceScheduleTab value) {
            setState(() => _selectedTab = value);
          },
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('race-import-toggle'),
            onPressed: () => setState(
              () => _isImportExpanded = !_isImportExpanded,
            ),
            icon: Icon(_isImportExpanded ? Icons.expand_less : Icons.add),
            label: Text(_isImportExpanded ? '收起添加比赛' : '添加比赛'),
          ),
        ),
        if (_isImportExpanded)
          _RaceImportCard(
            importText: raceImportText,
            statusMessage: state.raceImportStatusMessage,
          ),
        if (orderedRaces.isEmpty)
          _RaceScheduleEmptyState(tab: _selectedTab)
        else
          for (final RacePlan race in orderedRaces)
            _RaceScheduleCard(
              race: race,
              now: now,
              onOpen: () => _openRaceDetail(
                context,
                race: race,
                state: state,
              ),
            ),
      ],
    );
  }

  List<RacePlan> _orderedRacesForTab({
    required List<RacePlan> races,
    required RaceScheduleTab tab,
    required DateTime now,
  }) {
    final List<RacePlan> result = races
        .where((RacePlan race) => raceScheduleTabFor(race) == tab)
        .toList(growable: false);
    result.sort((RacePlan left, RacePlan right) {
      if (tab == RaceScheduleTab.preparing) {
        final bool leftIsPast = raceDaysUntil(left, now) < 0;
        final bool rightIsPast = raceDaysUntil(right, now) < 0;
        if (leftIsPast != rightIsPast) return leftIsPast ? 1 : -1;
      }
      return left.raceDate.compareTo(right.raceDate);
    });
    return result;
  }

  void _openRaceDetail(
    BuildContext context, {
    required RacePlan race,
    required TrainingMvpState state,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          minChildSize: 0.5,
          maxChildSize: 0.96,
          builder: (BuildContext context, ScrollController controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _RacePlanCard(race: race, state: state),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RaceScheduleTabs extends StatelessWidget {
  final RaceScheduleTab selectedTab;
  final int preparingCount;
  final int completedCount;
  final ValueChanged<RaceScheduleTab> onChanged;

  const _RaceScheduleTabs({
    required this.selectedTab,
    required this.preparingCount,
    required this.completedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RaceTabButton(
          label: '备赛',
          count: preparingCount,
          selected: selectedTab == RaceScheduleTab.preparing,
          onTap: () => onChanged(RaceScheduleTab.preparing),
        ),
        const SizedBox(width: 24),
        _RaceTabButton(
          label: '完赛',
          count: completedCount,
          selected: selectedTab == RaceScheduleTab.completed,
          onTap: () => onChanged(RaceScheduleTab.completed),
        ),
      ],
    );
  }
}

class _RaceTabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _RaceTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label，$count 场',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: selected
                          ? TrainFlowTokens.darkTrainingOnSurface
                          : TrainFlowTokens.darkTrainingMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 44 : 0,
                height: 5,
                decoration: BoxDecoration(
                  color: TrainFlowTokens.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RaceScheduleCard extends StatelessWidget {
  final RacePlan race;
  final DateTime now;
  final VoidCallback onOpen;

  const _RaceScheduleCard({
    required this.race,
    required this.now,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final int days = raceDaysUntil(race, now);
    final bool isCompleted = race.hasActiveOfficialRaceResult;
    final bool awaitingConfirmation = !isCompleted && days < 0;
    final String countdown = isCompleted
        ? race.officialRaceResult!.durationLabel
        : days == 0
            ? '今天'
            : days < 0
                ? '已过期'
                : '$days';
    final (String statusLabel, EmpBadgeTone statusTone) = isCompleted
        ? ('已完赛', EmpBadgeTone.mint)
        : awaitingConfirmation
            ? ('待确认', EmpBadgeTone.yellow)
            : days == 0
                ? ('今天', EmpBadgeTone.pink)
                : ('$days 天后', EmpBadgeTone.blue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          key: ValueKey<String>('race-schedule-${race.id}'),
          borderRadius: BorderRadius.circular(26),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              race.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          EmpBadge(label: statusLabel, tone: statusTone),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${race.raceDateLabel}  |  ${race.type.label}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: TrainFlowTokens.darkTrainingMuted,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isCompleted
                            ? '查看正式比赛成绩 ›'
                            : awaitingConfirmation
                                ? '待确认成绩 ›'
                                : '去备赛 ›',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: TrainFlowTokens.accent,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      countdown,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: isCompleted
                                ? AppColors.primary
                                : TrainFlowTokens.darkTrainingOnSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (!isCompleted && days > 0)
                      Text(
                        '天',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: TrainFlowTokens.darkTrainingMuted,
                                ),
                      ),
                    if (awaitingConfirmation)
                      const Icon(Icons.pending_outlined,
                          color: AppColors.warning),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RaceScheduleEmptyState extends StatelessWidget {
  final RaceScheduleTab tab;

  const _RaceScheduleEmptyState({required this.tab});

  @override
  Widget build(BuildContext context) {
    final bool preparing = tab == RaceScheduleTab.preparing;
    return TrainMateEmptyState(
      title: preparing ? '还没有待备赛赛事' : '还没有完赛成绩',
      message: preparing
          ? '添加比赛后会自动显示倒计时与备赛节奏。'
          : '确认正式比赛成绩后会显示在这里。',
      icon: preparing ? Icons.flag_outlined : Icons.emoji_events_outlined,
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
              const Icon(Icons.event_note, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '赛事导入',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const ToneBadge(label: '本地 races'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '先粘贴赛事名称、类型、日期、目标和赛道信息；导入后会写入本地 races，并使用本地规则生成周期、装备、策略和自动排期。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 14),
          const _RaceImageRecognitionBlock(),
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
          TrainMateButton(
            label: '导入比赛',
            icon: Icons.playlist_add_check,
            onPressed: () {
              ref
                  .read(trainingMvpProvider.notifier)
                  .importRaceText(ref.read(raceImportTextProvider));
            },
            expand: true,
          ),
          const SizedBox(height: 10),
          Text(
            statusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _RaceImageRecognitionBlock extends ConsumerWidget {
  const _RaceImageRecognitionBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RaceImageRecognitionState> asyncState =
        ref.watch(raceImageRecognitionControllerProvider);
    final RaceImageRecognitionState state = switch (asyncState) {
      AsyncData<RaceImageRecognitionState>(:final value) => value,
      _ => const RaceImageRecognitionState(
          status: RaceImageRecognitionStatus.picking,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.document_scanner_outlined,
                color: TrainFlowTokens.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '图片识别',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (state.image != null)
              IconButton(
                tooltip: '移除赛事图片',
                onPressed: state.isBusy
                    ? null
                    : () => ref
                        .read(raceImageRecognitionControllerProvider.notifier)
                        .clear(),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '图片会发送至 MiniMax-M3 提取明确可见的赛事信息，结果不会自动导入或保存图片。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TrainFlowTokens.darkTrainingMuted,
              ),
        ),
        const SizedBox(height: 10),
        if (kIsWeb)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref
                      .read(raceImageRecognitionControllerProvider.notifier)
                      .pickAndRecognize(RaceImageSource.gallery),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('选择赛事图片'),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy
                      ? null
                      : () => ref
                          .read(
                            raceImageRecognitionControllerProvider.notifier,
                          )
                          .pickAndRecognize(RaceImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('拍照识别'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy
                      ? null
                      : () => ref
                          .read(
                            raceImageRecognitionControllerProvider.notifier,
                          )
                          .pickAndRecognize(RaceImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从相册选择'),
                ),
              ),
            ],
          ),
        if (state.image != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.memory(
                state.image!.bytes,
                key: const ValueKey<String>('race-image-preview'),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(
                    color: AppColors.grayLighter,
                    child: Center(child: Text('图片预览不可用')),
                  );
                },
              ),
            ),
          ),
        ],
        if (state.status == RaceImageRecognitionStatus.picking ||
            state.status == RaceImageRecognitionStatus.recognizing) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(
            state.status == RaceImageRecognitionStatus.picking
                ? '正在读取图片…'
                : '正在识别赛事名称、日期和赛道…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            state.errorMessage!,
            key: const ValueKey<String>('race-image-error'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (state.image != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: state.isBusy
                  ? null
                  : () => ref
                      .read(raceImageRecognitionControllerProvider.notifier)
                      .recognizeSelected(),
              icon: const Icon(Icons.refresh),
              label: const Text('重新识别'),
            ),
          ],
        ],
        if (state.result != null) ...[
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '识别结果',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ToneBadge(label: '匹配 ${state.result!.matchedFieldCount} 项'),
            ],
          ),
          const SizedBox(height: 8),
          _RecognizedField(label: '赛事', value: state.result!.name),
          _RecognizedField(label: '类型', value: state.result!.type),
          _RecognizedField(label: '日期', value: state.result!.raceDate),
          _RecognizedField(label: '目标', value: state.result!.targetResult),
          _RecognizedField(label: '赛道', value: state.result!.courseInfo),
          if (state.result!.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final String warning in state.result!.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $warning',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.warningDark,
                      ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state.result!.normalizedText.trim().isEmpty
                  ? null
                  : () {
                      ref.read(raceImportTextProvider.notifier).setValue(
                            state.result!.normalizedText,
                          );
                    },
              icon: const Icon(Icons.edit_note),
              label: const Text('填入并编辑'),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecognizedField extends StatelessWidget {
  final String label;
  final String? value;

  const _RecognizedField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value?.trim().isNotEmpty == true ? value! : '未识别',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ToneBadge(label: race.type.label),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(label: '比赛日期', value: race.raceDateLabel),
          InfoRow(
            label: '当前阶段',
            value:
                '${schedule.items.first.phaseType.label} · ${schedule.countdownLabel}',
          ),
          InfoRow(label: '目标成绩', value: race.targetResult),
          InfoRow(label: '成绩预测', value: race.predictedResult),
          InfoRow(label: '赛道信息', value: race.courseInfo),
          const SizedBox(height: 12),
          _OfficialRaceResultBlock(race: race, state: state),
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

class _OfficialRaceResultBlock extends ConsumerWidget {
  final RacePlan race;
  final TrainingMvpState state;

  const _OfficialRaceResultBlock({
    required this.race,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState currentState = ref.watch(trainingMvpProvider);
    final RacePlan currentRace = currentState.findRace(race.id) ?? race;
    final OfficialRaceResult? result = currentRace.officialRaceResult;
    final List<TrainingLog> candidates = currentState.logs
        .where(
          (TrainingLog log) =>
              log.canConfirmOfficialRaceResult &&
              currentRace.isOnRaceDate(log.date),
        )
        .toList(growable: false);
    TrainingLog? linkedLog;
    if (result != null) {
      for (final TrainingLog log in currentState.logs) {
        if (log.id == result.trainingLogId) {
          linkedLog = log;
          break;
        }
      }
    }
    final bool canShowPb = result?.isActive == true &&
        linkedLog?.canConfirmOfficialRaceResult == true &&
        currentRace.isOnRaceDate(linkedLog!.date);

    return DecoratedBox(
      key: ValueKey<String>('official-race-result-${race.id}'),
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
                const Icon(Icons.workspace_premium_outlined,
                    color: TrainFlowTokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    canShowPb ? '正式比赛 PB' : '正式比赛成绩',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                ToneBadge(
                  label: canShowPb ? '已确认' : '待确认',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (canShowPb) ...[
              Text(
                result!.durationLabel,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: TrainFlowTokens.accent,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '确认于 ${_dateTimeLabel(result.confirmedAt)} · '
                '关联 ${_trainingLogLabel(currentState, linkedLog)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: ValueKey<String>('official-race-revoke-${race.id}'),
                onPressed: () => _confirmRevocation(context, ref),
                icon: const Icon(Icons.undo),
                label: const Text('撤销确认'),
              ),
            ] else ...[
              Text(
                result?.status == OfficialRaceResultStatus.revoked
                    ? '上一次正式成绩确认已撤销，不再作为 PB 展示。'
                    : result?.isActive == true
                        ? '原关联训练记录已不可用，当前成绩不再作为 PB 展示，请重新关联确认。'
                        : '只有你明确确认并关联训练记录的正式比赛成绩，才会标记为 PB；旧成绩文本不会自动转换。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey<String>('official-race-confirm-${race.id}'),
                  onPressed: candidates.isEmpty
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (BuildContext context) {
                              return _OfficialRaceResultDialog(
                                race: currentRace,
                                state: currentState,
                                candidateLogs: candidates,
                              );
                            },
                          ),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('确认正式比赛成绩'),
                ),
              ),
              if (candidates.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '还没有可关联的比赛当天完整训练记录。请先保存已完成且包含实际时长或距离的训练反馈。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TrainFlowTokens.darkTrainingMuted,
                      ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRevocation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final bool? approved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('撤销正式成绩确认？'),
          content: const Text('撤销后，这条成绩将停止以“正式比赛 PB”展示，但会保留撤销审计信息。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey<String>('official-race-revoke-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认撤销'),
            ),
          ],
        );
      },
    );
    if (approved != true || !context.mounted) {
      return;
    }
    final String? error = ref
        .read(trainingMvpProvider.notifier)
        .revokeOfficialRaceResult(raceId: race.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '已撤销正式比赛成绩确认。')),
    );
  }
}

class _OfficialRaceResultDialog extends ConsumerStatefulWidget {
  final RacePlan race;
  final TrainingMvpState state;
  final List<TrainingLog> candidateLogs;

  const _OfficialRaceResultDialog({
    required this.race,
    required this.state,
    required this.candidateLogs,
  });

  @override
  ConsumerState<_OfficialRaceResultDialog> createState() =>
      _OfficialRaceResultDialogState();
}

class _OfficialRaceResultDialogState
    extends ConsumerState<_OfficialRaceResultDialog> {
  final TextEditingController _durationController = TextEditingController();
  String? _selectedTrainingLogId;
  String? _saveError;

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String durationText = _durationController.text;
    final bool durationIsValid =
        OfficialRaceResult.tryParseDurationSeconds(durationText) != null;
    final bool canSave =
        durationIsValid && _selectedTrainingLogId?.isNotEmpty == true;

    return AlertDialog(
      title: Text('确认 ${widget.race.name} 的正式成绩'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请主动选择一条已完成的训练记录，并核对正式比赛净计时或枪声计时。'),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('official-race-log-selector'),
              initialValue: _selectedTrainingLogId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '关联训练记录',
                border: OutlineInputBorder(),
              ),
              items: widget.candidateLogs.map((TrainingLog log) {
                return DropdownMenuItem<String>(
                  key: ValueKey<String>('official-race-log-${log.id}'),
                  value: log.id,
                  child: Text(
                    _trainingLogLabel(widget.state, log),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(growable: false),
              onChanged: (String? value) {
                setState(() {
                  _selectedTrainingLogId = value;
                  _saveError = null;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('official-race-duration-input'),
              controller: _durationController,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: '正式成绩',
                hintText: '例如 4:30:00',
                border: const OutlineInputBorder(),
                errorText: durationText.trim().isNotEmpty && !durationIsValid
                    ? '请使用时:分:秒或分:秒格式'
                    : null,
              ),
              onChanged: (_) {
                setState(() {
                  _saveError = null;
                });
              },
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                _saveError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey<String>('official-race-save-button'),
          onPressed: canSave ? _save : null,
          child: const Text('确认并保存'),
        ),
      ],
    );
  }

  void _save() {
    final String? error =
        ref.read(trainingMvpProvider.notifier).confirmOfficialRaceResult(
              raceId: widget.race.id,
              trainingLogId: _selectedTrainingLogId ?? '',
              durationText: _durationController.text,
            );
    if (error != null) {
      setState(() {
        _saveError = error;
      });
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('已保存正式比赛 PB。')),
    );
  }
}

String _trainingLogLabel(TrainingMvpState state, TrainingLog log) {
  final String workoutTitle =
      state.findWorkoutDay(log.workoutDayId)?.title ?? '训练记录';
  return '${_dateLabel(log.date)} · $workoutTitle · ${log.sessionReviewSummary}';
}

String _dateLabel(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _dateTimeLabel(DateTime date) {
  return '${_dateLabel(date)} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
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
              ?.copyWith(fontWeight: FontWeight.w600),
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
                            color: TrainFlowTokens.darkTrainingMuted,
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
                const Icon(Icons.event_available, color: TrainFlowTokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '自动排期',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                ToneBadge(label: schedule.countdownLabel),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              schedule.statusLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
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
                    ?.copyWith(fontWeight: FontWeight.w600),
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
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '恢复：${currentItem.recoveryRule}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '安全门槛：${currentItem.safetyGate}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
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
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final String item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 18, color: TrainFlowTokens.accent),
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
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final RaceStrategySection section in sections) ...[
            Text(
              section.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final EvidenceSource source in sources) ...[
            Text(
              source.citationLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text('原文片段：${source.quote}'),
            const SizedBox(height: 4),
            Text(
              '适用原因：${source.note}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
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
      return TrainFlowTokens.darkTrainingMuted;
  }
}
