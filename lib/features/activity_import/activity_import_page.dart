import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/imported_workout.dart';
import '../dashboard/training_mvp_controller.dart';

class ActivityImportPage extends ConsumerWidget {
  const ActivityImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final String importText = ref.watch(activityImportTextProvider);

    return TrainFlowPage(
      title: '训练文件导入',
      subtitle: 'GPX / FIT 导入 Mock：配速、心率、爬升写入 workout_logs。',
      children: [
        _ActivityImportEditor(importText: importText),
        _ActivityImportResultCard(state: state),
        const SectionTitle(title: '最近导入'),
        if (state.importedWorkouts.isEmpty)
          TrainFlowCard(
            child: Text(
              '还没有导入记录。粘贴 GPX 或 FIT 摘要后，这里会显示训练效果标签。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          )
        else
          for (final ImportedWorkout workout in state.importedWorkouts)
            _ImportedWorkoutCard(workout: workout),
      ],
    );
  }
}

class _ActivityImportEditor extends ConsumerWidget {
  final String importText;

  const _ActivityImportEditor({required this.importText});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.upload_file, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '导入源文本',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const ToneBadge(label: '本地解析'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '第一版不读取真实文件，只粘贴 GPX 文本或 FIT 摘要；导入成功后会写入 workout_logs。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(activityImportTextProvider.notifier).useGpxSample();
                },
                icon: const Icon(Icons.route),
                label: const Text('使用 GPX 样例'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(activityImportTextProvider.notifier)
                      .useFitSummarySample();
                },
                icon: const Icon(Icons.watch),
                label: const Text('使用 FIT 摘要样例'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<String>(importText),
            initialValue: importText,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: 'GPX / FIT 摘要文本',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) {
              ref.read(activityImportTextProvider.notifier).setValue(value);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                ref
                    .read(trainingMvpProvider.notifier)
                    .importActivityText(ref.read(activityImportTextProvider));
              },
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('导入训练文件'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityImportResultCard extends StatelessWidget {
  final TrainingMvpState state;

  const _ActivityImportResultCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final ImportedWorkout? workout = state.latestImportedWorkout;

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '导入结果',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (workout != null) ToneBadge(label: workout.source.label),
            ],
          ),
          const SizedBox(height: 10),
          Text(state.activityImportStatusMessage),
          if (workout != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '距离',
                    value: '${workout.distanceKm.toStringAsFixed(2)} km',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricPill(
                    label: '训练效果',
                    value: workout.trainingEffect.label,
                    color: _effectColor(workout.trainingEffect),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportedWorkoutCard extends StatelessWidget {
  final ImportedWorkout workout;

  const _ImportedWorkoutCard({required this.workout});

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
                  workout.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(
                label: workout.trainingEffect.label,
                color: _effectColor(workout.trainingEffect),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${workout.dateLabel} · ${workout.source.label}'),
          const SizedBox(height: 8),
          Text(
            '${workout.summary} · 爬升 ${workout.elevationGainMeters} m · 平均心率 ${workout.averageHeartRate} bpm',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

Color _effectColor(TrainingEffectLabel effect) {
  switch (effect) {
    case TrainingEffectLabel.recovery:
      return AppColors.success;
    case TrainingEffectLabel.aerobic:
      return AppColors.primary;
    case TrainingEffectLabel.anaerobic:
      return AppColors.warningDark;
  }
}
