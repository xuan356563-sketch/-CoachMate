import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/knowledge_entry.dart';
import 'package:trainflow_ai/features/knowledge_library/knowledge_library_page.dart';

void main() {
  const BookQuote pendingQuote = BookQuote(
    id: 'quote-pending',
    bookId: 'book-1',
    chapter: '第 1 章',
    pageRange: '待核',
    quote: '待核内容',
    note: '测试',
    areas: <KnowledgeArea>[KnowledgeArea.running],
  );
  const BookQuote verifiedQuote = BookQuote(
    id: 'quote-verified',
    bookId: 'book-1',
    chapter: '第 1 章',
    pageRange: 'p. 1',
    quote: '已核短引',
    note: '测试',
    areas: <KnowledgeArea>[KnowledgeArea.running],
    kind: QuoteKind.shortExcerpt,
    verificationStatus: QuoteVerificationStatus.verified,
  );

  test('没有引文时显示暂无可核引文', () {
    expect(knowledgeReviewBadgeLabel(const <BookQuote>[]), '暂无可核引文');
  });

  test('存在待核引文时显示含待核内容', () {
    expect(
      knowledgeReviewBadgeLabel(const <BookQuote>[
        pendingQuote,
        verifiedQuote,
      ]),
      '含待核内容',
    );
  });

  test('所有非空引文已核时才显示内部已审核', () {
    expect(
      knowledgeReviewBadgeLabel(const <BookQuote>[verifiedQuote]),
      '内部已审核',
    );
  });
}
