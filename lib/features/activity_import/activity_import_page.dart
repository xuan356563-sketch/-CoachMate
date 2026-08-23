import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/imported_workout.dart';
import '../../services/activity_document_picker.dart';
import '../dashboard/training_mvp_controller.dart';
import 'route_replay_card.dart';

final activityDocumentPickerProvider = Provider<ActivityDocumentPicker>(
  (Ref ref) => const SystemActivityDocumentPicker(),
);

class ActivityImportPage extends ConsumerWidget {
  const ActivityImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final String importText = ref.watch(activityImportTextProvider);

    return TrainFlowPage(
      title: '训练文件导入',
      layout: TrainFlowPageLayout.form,
      subtitle: '真实 GPX 文件在本地解析；FIT 第一版继续使用文本摘要。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.dataCenter,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.running,
        backgroundColor: AppColors.primary,
      ),
      children: [
        _ActivityImportEditor(importText: importText),
        _ActivityImportResultCard(state: state),
        const SectionTitle(title: '最近导入'),
        if (state.importedWorkouts.isEmpty)
          TrainFlowCard(
            cornerCharacterAction: TrainMateAction.running,
            child: Text(
              '还没有导入记录。选择 GPX 文件或粘贴 FIT 摘要后，这里会显示训练效果和路线。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TrainFlowTokens.darkTrainingMuted,
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
              const Icon(Icons.upload_file, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '导入训练数据',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const ToneBadge(label: '本地解析'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'GPX 使用系统文件选择器，原始经纬度只参与本次计算；持久化时仅保留去地理化路线形状。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _pickGpxDocument(context, ref),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('选择 GPX 文件'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '也可以粘贴 GPX 内容或 FIT 文本摘要：',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TrainFlowTokens.darkTrainingMuted,
                ),
          ),
          const SizedBox(height: 8),
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
              const Icon(Icons.fact_check, color: TrainFlowTokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '导入结果',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
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

class _ImportedWorkoutCard extends ConsumerWidget {
  final ImportedWorkout workout;

  const _ImportedWorkoutCard({required this.workout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        TrainFlowCard(
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
                          ?.copyWith(fontWeight: FontWeight.w600),
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
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
            ],
          ),
        ),
        if (workout.hasRouteShape)
          RouteReplayCard(
            workout: workout,
            onDeleteRoute: () => ref
                .read(trainingMvpProvider.notifier)
                .removeImportedRouteShape(workout.id),
          ),
      ],
    );
  }
}

Future<void> _pickGpxDocument(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final ActivityDocument? document =
        await ref.read(activityDocumentPickerProvider).pickGpx();
    if (!context.mounted) return;
    if (document == null) {
      ref
          .read(trainingMvpProvider.notifier)
          .setActivityImportStatusMessage('已取消选择 GPX 文件，未写入任何训练数据。');
      return;
    }
    ref.read(trainingMvpProvider.notifier).importGpxDocument(
          document.contents,
          fileName: document.fileName,
        );
  } on FormatException catch (error) {
    if (!context.mounted) return;
    ref
        .read(trainingMvpProvider.notifier)
        .setActivityImportStatusMessage(error.message.toString());
  } catch (_) {
    if (!context.mounted) return;
    ref
        .read(trainingMvpProvider.notifier)
        .setActivityImportStatusMessage('读取 GPX 文件失败，请重新选择有效文件。');
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
