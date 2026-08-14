import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/trainmate_action_character.dart';
import '../../core/widgets/trainflow_widgets.dart';
import '../../data/models/knowledge_entry.dart';
import '../dashboard/training_mvp_controller.dart';

class KnowledgeLibraryPage extends ConsumerWidget {
  const KnowledgeLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TrainingMvpState state = ref.watch(trainingMvpProvider);
    final String importText = ref.watch(knowledgeImportTextProvider);
    final List<TrainingBook> visibleBooks = state.filteredKnowledgeBooks;

    return TrainFlowPage(
      title: '书库 / 知识库',
      subtitle: '把计划、动作、照吃卡和纠错建议绑定到可追溯的来源。',
      leading: const TrainMateBackButton(
        fallbackRoute: AppRoutes.aiCenter,
      ),
      artwork: const TrainMateActionCharacter(
        action: TrainMateAction.seatedMeditation,
        backgroundColor: AppColors.primary,
      ),
      children: [
        TrainFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.library_books, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '引用闭环',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const ToneBadge(label: '内部已审核'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricPill(
                      label: '书籍',
                      value: '${state.knowledgeBooks.length} 本',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricPill(
                      label: '引文',
                      value: '${state.bookQuotes.length} 条',
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              MetricPill(
                label: '已核引用关联',
                value: '${state.citationLinks.length} 条',
                color: AppColors.warningDark,
              ),
            ],
          ),
        ),
        _KnowledgeSearchImportCard(
          state: state,
          importText: importText,
        ),
        const SectionTitle(title: '书籍与引文'),
        if (visibleBooks.isEmpty)
          TrainFlowCard(
            cornerCharacterAction: TrainMateAction.seatedMeditation,
            child: Text(
              '没有匹配的书籍或引文。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          )
        else
          for (final TrainingBook book in visibleBooks)
            _KnowledgeBookCard(book: book, state: state),
      ],
    );
  }
}

class _KnowledgeSearchImportCard extends ConsumerWidget {
  final TrainingMvpState state;
  final String importText;

  const _KnowledgeSearchImportCard({
    required this.state,
    required this.importText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '书库搜索与导入',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${state.knowledgeSearchMatchCount} 本匹配'),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey<String>('knowledge-search-field'),
            initialValue: state.knowledgeSearchQuery,
            decoration: const InputDecoration(
              labelText: '全文搜索',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) {
              ref
                  .read(trainingMvpProvider.notifier)
                  .setKnowledgeSearchQuery(value);
            },
          ),
          const SizedBox(height: 12),
          Text(
            state.knowledgeImportStatusMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<String>('knowledge-import-field-$importText'),
            initialValue: importText,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '书籍 / 引文导入文本',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (String value) {
              ref.read(knowledgeImportTextProvider.notifier).setValue(value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(knowledgeImportTextProvider.notifier).useSample();
                  },
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('使用样例'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ref.read(trainingMvpProvider.notifier).importKnowledgeText(
                          ref.read(knowledgeImportTextProvider),
                        );
                  },
                  icon: const Icon(Icons.library_add_check),
                  label: const Text('导入知识片段'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KnowledgeBookCard extends StatelessWidget {
  final TrainingBook book;
  final TrainingMvpState state;

  const _KnowledgeBookCard({
    required this.book,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final List<BookQuote> quotes = state.quotesForBook(book.id);

    return TrainFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  book.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ToneBadge(label: '${quotes.length} 条引文'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${book.author} · ${book.edition}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(book.summary),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final KnowledgeArea area in book.areas)
                ToneBadge(label: area.label, color: AppColors.secondary),
            ],
          ),
          if (quotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final BookQuote quote in quotes)
              _BookQuoteBlock(quote: quote, state: state),
          ],
        ],
      ),
    );
  }
}

class _BookQuoteBlock extends StatelessWidget {
  final BookQuote quote;
  final TrainingMvpState state;

  const _BookQuoteBlock({
    required this.quote,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final List<CitationLink> citations = state.citationsForQuote(quote.id);
    final String locationLabel =
        quote.isVerified ? '${quote.chapter} · ${quote.pageRange}' : '待核版本/页码';
    final String quoteLabel = quote.isVerified ? quote.kind.label : '内容摘要（待核页）';

    return Padding(
      key: ValueKey<String>('knowledge-quote-${quote.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.grayLightest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locationLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ToneBadge(
                    label: quote.verificationStatus.label,
                    color: quote.isVerified
                        ? AppColors.success
                        : AppColors.warningDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$quoteLabel：${quote.quote}')),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '适用原因：${quote.note}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (citations.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '已核引用关联',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                for (final CitationLink citation in citations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ToneBadge(
                          label: citation.targetType.label,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${citation.targetTitle}：${citation.reason}',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (!quote.isVerified) ...[
                const SizedBox(height: 8),
                Text(
                  '收到实际版本版权页和引用页照片并人工核页后，才开放引用关联。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.warningDark,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
