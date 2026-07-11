import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
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
                label: '引用关联',
                value: '${state.citationLinks.length} 条',
                color: AppColors.warningDark,
              ),
              const SizedBox(height: 12),
              Text(
                '本地 MVP：books、book_quotes、citations 三层结构已能展示、搜索和导入；真实书库数据库后续再接。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
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

    return Padding(
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
                '${quote.chapter} · ${quote.pageRange}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text('原文片段：${quote.quote}'),
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
                  '引用关联',
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
            ],
          ),
        ),
      ),
    );
  }
}
