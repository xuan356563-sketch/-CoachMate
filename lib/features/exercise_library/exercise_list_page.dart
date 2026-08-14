import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/trainmate_visual_mode.dart';
import '../../core/theme/trainflow_tokens.dart';
import '../../core/widgets/flow_mascot.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainmate_showcase_widgets.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/body_region.dart';
import '../../data/models/exercise.dart';
import '../../data/models/exercise_focus_profile.dart';
import '../../data/models/motion_check.dart';
import '../dashboard/training_mvp_controller.dart';

FlowMascotSpec selectExerciseMascotSpec({
  required bool hasExercises,
  required MotionRiskLevel? riskLevel,
}) {
  if (!hasExercises) {
    return const FlowMascotSpec(
      action: FlowMascotAction.search,
      expression: FlowMascotExpression.curious,
      semanticLabel: 'Flow 训练伙伴正在寻找可用动作',
      durationMilliseconds: 580,
    );
  }
  return switch (riskLevel) {
    null => const FlowMascotSpec(
        action: FlowMascotAction.stretch,
        expression: FlowMascotExpression.smile,
        semanticLabel: 'Flow 训练伙伴微笑示范侧弓步伸展',
        durationMilliseconds: 520,
      ),
    MotionRiskLevel.low => const FlowMascotSpec(
        action: FlowMascotAction.thumbsUp,
        expression: FlowMascotExpression.happy,
        semanticLabel: 'Flow 训练伙伴为低风险动作点赞',
        durationMilliseconds: 420,
        motionCycles: 2,
      ),
    MotionRiskLevel.medium => const FlowMascotSpec(
        action: FlowMascotAction.correct,
        expression: FlowMascotExpression.focused,
        semanticLabel: 'Flow 训练伙伴正在提示动作修正',
        durationMilliseconds: 520,
      ),
    MotionRiskLevel.high => const FlowMascotSpec(
        action: FlowMascotAction.correct,
        expression: FlowMascotExpression.concerned,
        semanticLabel: 'Flow 训练伙伴提醒暂停高风险动作',
        durationMilliseconds: 620,
      ),
  };
}

class ExerciseListPage extends ConsumerStatefulWidget {
  const ExerciseListPage({super.key});

  @override
  ConsumerState<ExerciseListPage> createState() => _ExerciseListPageState();
}

/// 「全部」视图下每个部位预览的动作数量。
const int _previewPerRegion = 4;

class _ExerciseListPageState extends ConsumerState<ExerciseListPage> {
  /// null 表示「全部」：按部位分组预览；选中某个部位时展示该部位全部动作。
  BodyRegion? _selectedRegion;
  ExerciseFocusTag? _selectedFocus;
  ExerciseFocusArea? _selectedFocusArea;

  @override
  Widget build(BuildContext context) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final FlowMascotSpec mascotSpec = selectExerciseMascotSpec(
      hasExercises: state.exercises.isNotEmpty,
      riskLevel: state.latestMotionAnalysisResult?.riskLevel,
    );
    final List<Exercise> taggedExercises = filterExercisesByFocus(
      exercises: state.exercises,
      tag: _selectedFocus,
      area: null,
    );
    final List<Exercise> focusFiltered = filterExercisesByFocus(
      exercises: taggedExercises,
      tag: null,
      area: _selectedFocusArea,
    );
    final Map<BodyRegion, List<Exercise>> grouped =
        groupExercisesByBodyRegion(focusFiltered);
    final Map<ExerciseFocusArea, List<Exercise>> focusGrouped =
        groupExercisesByFocusArea(taggedExercises);
    final BodyRegion? selected =
        grouped.containsKey(_selectedRegion) ? _selectedRegion : null;

    return TrainMateImmersiveHubPage(
      includeDisclaimer: false,
      mode: TrainMateVisualMode.darkTraining,
      hero: KeyedSubtree(
        key: const ValueKey<String>('exercises-showcase-header'),
        child: TrainMateSceneHero(
          sceneAsset:
              'assets/images/immersive_scenes/trainmate_exercise_lab.png',
          greeting:
              '动作库 · ${state.profile.name.trim().isEmpty ? '训练者' : state.profile.name}',
          dateLabel: '${state.exercises.length} 个真实动作可用',
          character: TrainMateIllustration(
            assetPath: 'assets/images/trainmate_exercises_showcase.png',
            semanticLabel: '多动作训练人物插画',
            fallback: const TrainMateActionCharacter(
              action: TrainMateAction.sideLungeStretch,
              size: 164,
              backgroundColor: AppColors.transparent,
            ),
          ),
          taskTitle:
              state.latestMotionAnalysisResult == null ? '开始动作检测' : '查看最近动作检测',
          taskSubtitle: state.latestMotionAnalysisResult == null
              ? '检测前只做动作提示，不会写入训练计划。'
              : '已有真实检测记录，可继续查看风险提示与纠错。',
          taskIcon: Icons.center_focus_strong_rounded,
          actionTooltip: '打开动作检测',
          onAction: () => context.push(AppRoutes.motionCheck),
          onTaskTap: () => context.push(AppRoutes.motionCheck),
        ),
      ),
      children: [
        TrainMateStatusStrip(
          semanticLabel: '动作筛选状态',
          metrics: <TrainMateStatusMetric>[
            TrainMateStatusMetric(
                label: '全部',
                value: '${state.exercises.length}',
                icon: Icons.grid_view_outlined),
            TrainMateStatusMetric(
                label: '小肌群',
                value:
                    '${filterExercisesByFocus(exercises: state.exercises, tag: ExerciseFocusTag.smallMuscle, area: null).length}',
                icon: Icons.accessibility_new_outlined,
                color: AppColors.secondaryLight),
            TrainMateStatusMetric(
                label: '功能性',
                value:
                    '${filterExercisesByFocus(exercises: state.exercises, tag: ExerciseFocusTag.functional, area: null).length}',
                icon: Icons.bolt_outlined),
          ],
        ),
        const SizedBox(height: 20),
        TrainMateOverviewGrid(
          first: _ExerciseOverviewTile(
              label: '部位',
              value: '${grouped.length} 类',
              icon: Icons.accessibility_new_outlined),
          second: _ExerciseOverviewTile(
              label: '焦点',
              value: _selectedFocus?.label ?? '全部',
              icon: Icons.tune_outlined),
          trend: _ExerciseOverviewTile(
              label: '动作检测',
              value: state.latestMotionAnalysisResult == null
                  ? '暂无检测记录'
                  : '已有检测记录',
              icon: Icons.center_focus_strong_outlined,
              wide: true),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: '动作检测'),
        _MotionCheckPreviewCard(state: state),
        const SectionTitle(title: '精选组合'),
        _KneeAnkleCircuitCard(
          onStart: () => context.push(
            AppRoutes.exerciseCircuitDetail('knee-ankle-stability-v1'),
          ),
        ),
        SectionTitle(title: '训练动作 · 共 ${state.exercises.length} 个'),
        _FocusFilterBar(
          selected: _selectedFocus,
          onSelected: (ExerciseFocusTag? tag) {
            setState(() {
              _selectedFocus = tag;
              _selectedFocusArea = null;
            });
          },
        ),
        if (grouped.isNotEmpty)
          _BodyRegionFilterBar(
            regions: grouped.keys.toList(),
            counts: grouped.map(
              (BodyRegion region, List<Exercise> items) =>
                  MapEntry<BodyRegion, int>(region, items.length),
            ),
            selected: selected,
            onSelected: (BodyRegion? region) {
              setState(() => _selectedRegion = region);
            },
          ),
        if (selected == null && _selectedFocus == null)
          // 「全部」视图每个部位只预览前 4 个，避免一次性构建上百个卡片。
          ...grouped.entries.expand(
            (MapEntry<BodyRegion, List<Exercise>> entry) => <Widget>[
              SectionTitle(
                title: '${entry.key.label} · ${entry.value.length} 个',
              ),
              _ExerciseGrid(
                exercises: entry.value.take(_previewPerRegion).toList(),
                mascotAction: mascotSpec.action,
              ),
              if (entry.value.length > _previewPerRegion)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _selectedRegion = entry.key);
                    },
                    icon: const Icon(Icons.grid_view),
                    label: Text(
                        '查看全部 ${entry.value.length} 个${entry.key.label}动作'),
                  ),
                ),
            ],
          )
        else if (selected == null && _selectedFocusArea == null)
          ...focusGrouped.entries.expand(
            (MapEntry<ExerciseFocusArea, List<Exercise>> entry) => <Widget>[
              SectionTitle(
                title: '${entry.key.label} · ${entry.value.length} 个',
              ),
              _ExerciseGrid(
                exercises: entry.value.take(_previewPerRegion).toList(),
                mascotAction: mascotSpec.action,
              ),
              if (entry.value.length > _previewPerRegion)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _selectedFocusArea = entry.key);
                    },
                    icon: const Icon(Icons.grid_view),
                    label: Text('查看 ${entry.key.label} 全部动作'),
                  ),
                ),
            ],
          )
        else if (selected == null) ...<Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedFocusArea = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回焦点分区'),
            ),
          ),
          _ExerciseGrid(
            exercises: focusFiltered,
            mascotAction: mascotSpec.action,
          ),
        ] else
          _ExerciseGrid(
            exercises: grouped[selected] ?? const <Exercise>[],
            mascotAction: mascotSpec.action,
          ),
      ],
    );
  }
}

class _ExerciseOverviewTile extends StatelessWidget {
  const _ExerciseOverviewTile(
      {required this.label,
      required this.value,
      required this.icon,
      this.wide = false});
  final String label;
  final String value;
  final IconData icon;
  final bool wide;
  @override
  Widget build(BuildContext context) => TrainFlowCard(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: wide ? 108 : 132),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: TrainFlowTokens.accent),
                const SizedBox(height: 14),
                TrainMateMetricValue(value: value, label: label),
              ]),
        ),
      );
}

class _FocusFilterBar extends StatelessWidget {
  final ExerciseFocusTag? selected;
  final ValueChanged<ExerciseFocusTag?> onSelected;

  const _FocusFilterBar({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _RegionChip(
            label: '全部',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final ExerciseFocusTag tag in ExerciseFocusTag.values)
            _RegionChip(
              label: tag.label,
              isSelected: selected == tag,
              onTap: () => onSelected(tag),
            ),
        ],
      ),
    );
  }
}

class _KneeAnkleCircuitCard extends StatelessWidget {
  final VoidCallback onStart;

  const _KneeAnkleCircuitCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      onTap: onStart,
      child: Row(
        children: <Widget>[
          const Icon(Icons.directions_walk, color: AppColors.primary, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '膝踝稳定与小肌群激活循环',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '5 个动作 · 2–3 轮 · 用户确认后开始跟练',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.primary),
        ],
      ),
    );
  }
}

/// 部位筛选条。第一个是「全部」，其余按 [BodyRegion.values] 的固定顺序排列。
class _BodyRegionFilterBar extends StatelessWidget {
  final List<BodyRegion> regions;
  final Map<BodyRegion, int> counts;
  final BodyRegion? selected;
  final ValueChanged<BodyRegion?> onSelected;

  const _BodyRegionFilterBar({
    required this.regions,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _RegionChip(
            label: '全部',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          ...regions.map(
            (BodyRegion region) => _RegionChip(
              label: '${region.label} ${counts[region] ?? 0}',
              isSelected: selected == region,
              onTap: () => onSelected(region),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RegionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool dark = TrainMateVisualScope.isDark(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(TrainFlowTokens.mainTabControlRadius),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected
                ? TrainFlowTokens.accent
                : (dark
                    ? TrainFlowTokens.darkTrainingRaised
                    : TrainFlowTokens.lightCompanionCard),
            borderRadius:
                BorderRadius.circular(TrainFlowTokens.mainTabControlRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isSelected
                        ? TrainFlowTokens.onAccent
                        : TrainMateVisualScope.foreground(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseGrid extends StatelessWidget {
  final List<Exercise> exercises;
  final FlowMascotAction mascotAction;

  const _ExerciseGrid({
    required this.exercises,
    required this.mascotAction,
  });

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return TrainFlowCard(
        cornerCharacterAction: trainMateActionForFlowMascot(mascotAction),
        child: const Text('暂无可用动作，完成基础资料后再查看推荐。'),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: exercises.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 264,
      ),
      itemBuilder: (context, index) {
        return _ExerciseTile(exercise: exercises[index]);
      },
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  final Exercise exercise;

  const _ExerciseTile({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final bool hasPreciseMedia =
        exercise.mediaStatus == ExerciseMediaStatus.precise;
    return TrainFlowCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push(AppRoutes.exerciseDetail(exercise.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: const Icon(
                  Icons.directions_run,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              if (exercise.mediaUrl != null)
                Tooltip(
                  message: exercise.mediaStatus.label,
                  child: Icon(
                    hasPreciseMedia ? Icons.gif_box_outlined : Icons.image,
                    size: 20,
                    color: hasPreciseMedia
                        ? AppColors.primary
                        : AppColors.secondaryDark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            exercise.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: ToneBadge(
              label: exercise.category.label,
              color: AppColors.secondary,
            ),
          ),
          if (!exerciseFocusProfile(exercise).isEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: exerciseFocusProfile(exercise)
                  .tags
                  .map(
                    (ExerciseFocusTag tag) => ToneBadge(
                      label: tag.label,
                      color: AppColors.primary,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            exercise.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 7),
          Text(
            '建议：${exercise.setsAndReps}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MotionCheckPreviewCard extends StatelessWidget {
  final TrainingMvpState state;

  const _MotionCheckPreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final MotionCheckRule rule = state.featuredMotionCheck;
    final MotionAnalysisResult? result = state.latestMotionAnalysisResult;

    return TrainFlowCard(
      tone: TrainFlowCardTone.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.motion_photos_on, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '动作纠错',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${rule.score} 分'),
            ],
          ),
          const SizedBox(height: 10),
          if (result == null)
            Text('8 个核心动作规则已接入，先从${rule.type.label}纠错开始。')
          else
            Text(
              '最近分析：${result.type.label} · ${result.riskLevel.label} · ${result.suggestedImpact.label}',
            ),
          const SizedBox(height: 8),
          Text(
            result == null
                ? '当前为本地规则 Mock，不做真实视频识别。'
                : '动作质量风险已进入每日调整，训练会按 Body Engine 解释更保守地处理。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push(AppRoutes.motionCheck),
              icon: const Icon(Icons.open_in_new),
              label: const Text('查看纠错'),
            ),
          ),
        ],
      ),
    );
  }
}
