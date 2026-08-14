import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/data/models/knowledge_entry.dart';
import 'package:trainflow_ai/data/repositories/knowledge_repository.dart';

void main() {
  test('旧引文JSON默认按内容转述和待核读取', () {
    final BookQuote quote = BookQuote.fromJson(<String, dynamic>{
      'id': 'legacy-quote',
      'bookId': 'book-1',
      'chapter': '旧章节',
      'pageRange': 'p. 1',
      'quote': '旧内容',
      'note': '旧说明',
      'areas': <String>['running'],
    });

    expect(quote.kind, QuoteKind.paraphrase);
    expect(quote.verificationStatus, QuoteVerificationStatus.pending);
    expect(quote.isVerified, isFalse);
  });

  test('待核引文不计入引用关联，已核引文才计入', () {
    const TrainingBook book = TrainingBook(
      id: 'book-1',
      title: '测试书',
      author: '测试作者',
      edition: '第 1 版 · 2026 · ISBN 000',
      areas: <KnowledgeArea>[KnowledgeArea.running],
      summary: '测试',
    );
    const CitationLink citation = CitationLink(
      id: 'citation-1',
      quoteId: 'quote-1',
      targetType: CitationTargetType.plan,
      targetId: 'plan-1',
      targetTitle: '测试计划',
      reason: '测试引用',
    );
    const BookQuote pending = BookQuote(
      id: 'quote-1',
      bookId: 'book-1',
      chapter: '第 1 章',
      pageRange: 'p. 1',
      quote: '待核内容',
      note: '测试',
      areas: <KnowledgeArea>[KnowledgeArea.running],
    );
    final InMemoryKnowledgeRepository pendingRepository =
        InMemoryKnowledgeRepository(
      initialBooks: const <TrainingBook>[book],
      initialQuotes: const <BookQuote>[pending],
      initialCitationLinks: const <CitationLink>[citation],
    );
    expect(pendingRepository.listCitationLinks(), isEmpty);

    const BookQuote verified = BookQuote(
      id: 'quote-1',
      bookId: 'book-1',
      chapter: '第 1 章',
      pageRange: 'p. 1',
      quote: '已核短引',
      note: '测试',
      areas: <KnowledgeArea>[KnowledgeArea.running],
      kind: QuoteKind.shortExcerpt,
      verificationStatus: QuoteVerificationStatus.verified,
    );
    final InMemoryKnowledgeRepository verifiedRepository =
        InMemoryKnowledgeRepository(
      initialBooks: const <TrainingBook>[book],
      initialQuotes: const <BookQuote>[verified],
      initialCitationLinks: const <CitationLink>[citation],
    );
    expect(verifiedRepository.listCitationLinks(), hasLength(1));
  });
}
