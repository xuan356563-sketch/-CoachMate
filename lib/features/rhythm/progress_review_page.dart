import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/body_rhythm.dart';
import 'application/body_rhythm_controller.dart';

class ProgressReviewPage extends ConsumerWidget {
  const ProgressReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BodyRhythmState> rhythm =
        ref.watch(bodyRhythmControllerProvider);
    return TrainFlowPage(
      title: '15 天复盘',
      layout: TrainFlowPageLayout.report,
      subtitle: '只根据真实记录总结变化，不用百分比制造虚假精确。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.rhythmDetail,
      ),
      children: [
        rhythm.when(
          data: (BodyRhythmState value) => _ReviewContent(state: value),
          loading: () => const TrainFlowCard(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace stackTrace) => TrainFlowCard(
            child: Text('复盘数据暂时无法读取：$error'),
          ),
        ),
      ],
    );
  }
}

class _ReviewContent extends StatelessWidget {
  const _ReviewContent({required this.state});

  final BodyRhythmState state;

  @override
  Widget build(BuildContext context) {
    final ReviewUnlockStatus status = state.reviewStatus;
    return Column(
      children: [
        TrainFlowCard(
          tone: status.isUnlocked
              ? TrainFlowCardTone.peach
              : TrainFlowCardTone.outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status.isUnlocked ? '这 15 天，你的坚持有结果了' : '15 天复盘正在积累证据',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                status.isUnlocked
                    ? '饮食与体重记录已达到复盘门槛，训练记录作为变化背景展示。'
                    : status.gaps.join('；'),
              ),
            ],
          ),
        ),
        _EvidenceStripCard(
          status: status,
          mealDates: state.mealRecords
              .map((MealRecord item) => item.localDate)
              .toSet(),
          weightDates: state.weightDates.toSet(),
          trainingDates: state.trainingDates.toSet(),
        ),
        if (status.isUnlocked)
          TrainFlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(title: '阶段变化摘要'),
                InfoRow(label: '饮食坚持', value: '${status.dietDays} 个记录日'),
                InfoRow(
                  label: '体重证据',
                  value:
                      '${status.weightRecords} 条 · 跨 ${status.weightSpanDays} 天',
                ),
                InfoRow(label: '训练记录', value: '${status.trainingDays} 天'),
                const SizedBox(height: 8),
                Text(
                  status.trainingDays == 0
                      ? '训练数据不足，本次只总结饮食与体重记录情况。'
                      : '以上是记录变化，不构成医学或减重效果判断。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          )
        else
          TrainFlowCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restaurant_outlined),
                  title: const Text('补充饮食记录'),
                  subtitle: const Text('记录餐次和实际吃了什么'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.mealGuide),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.monitor_weight_outlined),
                  title: const Text('补充体重记录'),
                  subtitle: const Text('至少 4 条，首末相隔至少 7 天'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.dataCenter),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EvidenceStripCard extends StatelessWidget {
  const _EvidenceStripCard({
    required this.status,
    required this.mealDates,
    required this.weightDates,
    required this.trainingDates,
  });

  final ReviewUnlockStatus status;
  final Set<DateTime> mealDates;
  final Set<DateTime> weightDates;
  final Set<DateTime> trainingDates;

  @override
  Widget build(BuildContext context) {
    final DateTime end = DateTime.now();
    final List<DateTime> days = <DateTime>[
      for (int offset = 14; offset >= 0; offset--)
        DateTime(end.year, end.month, end.day).subtract(Duration(days: offset)),
    ];
    final Set<String> mealKeys = mealDates.map(_dateKey).toSet();
    final Set<String> weightKeys = weightDates.map(_dateKey).toSet();
    final Set<String> trainingKeys = trainingDates.map(_dateKey).toSet();
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '真实记录覆盖',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _HeatRow(
            label: '饮食 ${status.dietDays}/7 天',
            values:
                days.map((DateTime day) => mealKeys.contains(_dateKey(day))),
          ),
          const SizedBox(height: 12),
          _HeatRow(
            label: '体重 ${status.weightRecords}/4 条',
            values:
                days.map((DateTime day) => weightKeys.contains(_dateKey(day))),
          ),
          const SizedBox(height: 12),
          _HeatRow(
            label: '训练 ${status.trainingDays} 天（非门槛）',
            values: days
                .map((DateTime day) => trainingKeys.contains(_dateKey(day))),
          ),
        ],
      ),
    );
  }
}

class _HeatRow extends StatelessWidget {
  const _HeatRow({required this.label, required this.values});

  final String label;
  final Iterable<bool> values;

  @override
  Widget build(BuildContext context) {
    final List<bool> items = values.toList(growable: false);
    final int completed = items.where((bool value) => value).length;
    return Semantics(
      label: '$label，共 15 天中有 $completed 天存在记录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Row(
            children: [
              for (final bool active in items)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _dateKey(DateTime value) => '${value.year}-${value.month}-${value.day}';
