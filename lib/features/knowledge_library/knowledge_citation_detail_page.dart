import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/ai_knowledge_citation.dart';
import '../dashboard/training_mvp_controller.dart';

class KnowledgeCitationDetailPage extends ConsumerWidget {
  final String itemId;

  const KnowledgeCitationDetailPage({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AiKnowledgeCitation? citation = ref
        .watch(trainingMvpProvider)
        .plans
        .expand((plan) => plan.knowledgeCitations)
        .where((item) => item.id == itemId)
        .firstOrNull;
    if (citation == null) {
      return const TrainFlowPage(
        title: '知识条目不可用',
        leading: TrainMateBackButton(fallbackRoute: AppRoutes.knowledge),
        children: [
          TrainFlowCard(child: Text('没有找到对应的审核知识条目，请刷新计划后重试。')),
        ],
      );
    }
    return TrainFlowPage(
      title: citation.title,
      subtitle: citation.type == AiKnowledgeCitationType.principle
          ? '审核训练原则'
          : '审核结构模板',
      leading: const TrainMateBackButton(fallbackRoute: AppRoutes.knowledge),
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_outlined, color: TrainFlowTokens.accent),
              const SizedBox(height: 12),
              InfoRow(label: '来源', value: citation.sourceLabel),
              InfoRow(label: '章节', value: citation.sourceSection),
              InfoRow(label: '内容版本', value: citation.contentVersion),
              InfoRow(label: '条目 ID', value: citation.id),
              const SizedBox(height: 8),
              Text(
                '该条目来自当前处方使用的审核知识快照。它只说明处方依据，不替代动作详情中的本地证据来源。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TrainFlowTokens.darkTrainingMuted,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
