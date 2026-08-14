import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/widgets/trainflow_widgets.dart';
import '../../../data/models/daily_activity_summary.dart';
import '../../profile/application/health_sync_controller.dart';
import '../application/daily_activity_sync_controller.dart';

class PetDataSettingsPage extends ConsumerWidget {
  const PetDataSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DailyActivitySyncState> asyncState =
        ref.watch(dailyActivitySyncControllerProvider);
    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _page(
        context,
        ref,
        state: DailyActivitySyncState(
          supported: false,
          syncing: false,
          summaries: const <DailyActivitySummary>[],
          suggestedGoals: null,
          statusMessage: '伙伴活动数据读取失败，请稍后重试。',
        ),
      ),
      data: (DailyActivitySyncState state) => _page(context, ref, state: state),
    );
  }

  Widget _page(
    BuildContext context,
    WidgetRef ref, {
    required DailyActivitySyncState state,
  }) {
    return TrainFlowPage(
      title: '伙伴数据',
      layout: TrainFlowPageLayout.form,
      subtitle: 'Apple 健康自动同步，也可逐项手动补录',
      leading: const TrainMateBackButton(fallbackRoute: AppRoutes.pet),
      includeDisclaimer: false,
      children: <Widget>[
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(state.statusMessage),
              const SizedBox(height: 12),
              if (state.supported)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.syncing
                        ? null
                        : () async {
                            await ref
                                .read(healthSyncControllerProvider.notifier)
                                .connectAndSync();
                            await ref
                                .read(dailyActivitySyncControllerProvider
                                    .notifier)
                                .refresh();
                          },
                    icon: const Icon(Icons.favorite_outline),
                    label: Text(state.syncing ? '正在同步…' : '连接并同步 Apple 健康'),
                  ),
                ),
            ],
          ),
        ),
        for (final _ActivityMetric metric in _metrics)
          _ActivityMetricCard(
            metric: metric,
            summary: state.latest,
            onEditValue: () => _editField(
              context,
              ref,
              metric: metric,
              field: metric.valueField,
              isGoal: false,
            ),
            onEditGoal: () => _editField(
              context,
              ref,
              metric: metric,
              field: metric.goalField,
              isGoal: true,
            ),
            onRestoreValue: () => ref
                .read(dailyActivitySyncControllerProvider.notifier)
                .restoreAutomatic(metric.valueField),
            onRestoreGoal: () => ref
                .read(dailyActivitySyncControllerProvider.notifier)
                .restoreAutomatic(metric.goalField),
          ),
      ],
    );
  }

  Future<void> _editField(
    BuildContext context,
    WidgetRef ref, {
    required _ActivityMetric metric,
    required DailyActivityField field,
    required bool isGoal,
  }) async {
    final num? value = await showDialog<num>(
      context: context,
      builder: (BuildContext dialogContext) => _ManualValueDialog(
        title: isGoal ? '设置${metric.label}目标' : '补录${metric.label}',
        unit: metric.unit,
        confirmLabel: isGoal ? '保存目标' : '保存补录',
      ),
    );
    if (value == null || !context.mounted) return;
    final DailyActivitySyncController controller =
        ref.read(dailyActivitySyncControllerProvider.notifier);
    if (isGoal) {
      await controller.setManualGoal(field, value);
    } else {
      await controller.setManualValue(field, value);
    }
  }
}

class _ManualValueDialog extends StatefulWidget {
  const _ManualValueDialog({
    required this.title,
    required this.unit,
    required this.confirmLabel,
  });

  final String title;
  final String unit;
  final String confirmLabel;

  @override
  State<_ManualValueDialog> createState() => _ManualValueDialogState();
}

class _ManualValueDialogState extends State<_ManualValueDialog> {
  final TextEditingController _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey<String>('manual-value-input'),
        controller: _input,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.unit,
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final num? parsed = num.tryParse(_input.text.trim());
            if (parsed == null || parsed < 0) {
              setState(() => _error = '请输入不小于 0 的有效数值');
              return;
            }
            Navigator.of(context).pop(parsed);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ActivityMetricCard extends StatelessWidget {
  const _ActivityMetricCard({
    required this.metric,
    required this.summary,
    required this.onEditValue,
    required this.onEditGoal,
    required this.onRestoreValue,
    required this.onRestoreGoal,
  });

  final _ActivityMetric metric;
  final DailyActivitySummary? summary;
  final VoidCallback onEditValue;
  final VoidCallback onEditGoal;
  final VoidCallback onRestoreValue;
  final VoidCallback onRestoreGoal;

  @override
  Widget build(BuildContext context) {
    final num? value = metric.valueOf(summary);
    final num? goal = metric.goalOf(summary);
    final ActivityFieldSource valueSource =
        summary?.sourceFor(metric.valueField) ??
            ActivityFieldSource.unavailable;
    final ActivityFieldSource goalSource =
        summary?.sourceFor(metric.goalField) ?? ActivityFieldSource.unavailable;
    return TrainFlowCard(
      key: ValueKey<String>('metric-${metric.valueField.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(metric.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(value == null ? '未授权' : '${_format(value)} ${metric.unit}'),
          Text(goal == null ? '目标：未设置' : '目标：${_format(goal)} ${metric.unit}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              TextButton(
                key: ValueKey<String>('manual-${metric.valueField.name}'),
                onPressed: onEditValue,
                child: const Text('手动补录'),
              ),
              TextButton(
                key: ValueKey<String>('manual-${metric.goalField.name}'),
                onPressed: onEditGoal,
                child: const Text('设置目标'),
              ),
              if (valueSource == ActivityFieldSource.manualOverride)
                TextButton(
                  key: ValueKey<String>('restore-${metric.valueField.name}'),
                  onPressed: onRestoreValue,
                  child: const Text('恢复自动'),
                ),
              if (goalSource == ActivityFieldSource.manualOverride)
                TextButton(
                  key: ValueKey<String>('restore-${metric.goalField.name}'),
                  onPressed: onRestoreGoal,
                  child: const Text('恢复目标'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityMetric {
  const _ActivityMetric({
    required this.label,
    required this.unit,
    required this.valueField,
    required this.goalField,
    required this.valueOf,
    required this.goalOf,
  });

  final String label;
  final String unit;
  final DailyActivityField valueField;
  final DailyActivityField goalField;
  final num? Function(DailyActivitySummary? summary) valueOf;
  final num? Function(DailyActivitySummary? summary) goalOf;
}

final List<_ActivityMetric> _metrics = <_ActivityMetric>[
  _ActivityMetric(
    label: '步数',
    unit: '步',
    valueField: DailyActivityField.steps,
    goalField: DailyActivityField.stepGoal,
    valueOf: (DailyActivitySummary? value) => value?.steps,
    goalOf: (DailyActivitySummary? value) => value?.stepGoal,
  ),
  _ActivityMetric(
    label: '活动消耗',
    unit: '千卡',
    valueField: DailyActivityField.activeEnergyKcal,
    goalField: DailyActivityField.activeEnergyGoalKcal,
    valueOf: (DailyActivitySummary? value) => value?.activeEnergyKcal,
    goalOf: (DailyActivitySummary? value) => value?.activeEnergyGoalKcal,
  ),
  _ActivityMetric(
    label: '运动分钟',
    unit: '分钟',
    valueField: DailyActivityField.exerciseMinutes,
    goalField: DailyActivityField.exerciseGoalMinutes,
    valueOf: (DailyActivitySummary? value) => value?.exerciseMinutes,
    goalOf: (DailyActivitySummary? value) => value?.exerciseGoalMinutes,
  ),
  _ActivityMetric(
    label: '站立小时',
    unit: '小时',
    valueField: DailyActivityField.standHours,
    goalField: DailyActivityField.standGoalHours,
    valueOf: (DailyActivitySummary? value) => value?.standHours,
    goalOf: (DailyActivitySummary? value) => value?.standGoalHours,
  ),
];

String _format(num value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
