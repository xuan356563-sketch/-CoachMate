import '../models/knowledge_entry.dart';
import '../seed/seed_knowledge_entries.dart';
import '../../services/local_storage_service.dart';

abstract class KnowledgeRepository {
  List<TrainingBook> listBooks();

  List<BookQuote> listQuotes();

  List<CitationLink> listCitationLinks();

  List<BookQuote> quotesForBook(String bookId);

  List<CitationLink> citationsForQuote(String quoteId);

  KnowledgeImportResult saveImportedEntry(KnowledgeImportResult result);

  void clearImportedEntries();
}

class InMemoryKnowledgeRepository implements KnowledgeRepository {
  final List<TrainingBook> _books;
  final List<BookQuote> _quotes;
  final List<CitationLink> _citationLinks;

  InMemoryKnowledgeRepository({
    List<TrainingBook>? initialBooks,
    List<BookQuote>? initialQuotes,
    List<CitationLink>? initialCitationLinks,
  })  : _books = List<TrainingBook>.from(initialBooks ?? seedTrainingBooks),
        _quotes = List<BookQuote>.from(initialQuotes ?? seedBookQuotes),
        _citationLinks =
            List<CitationLink>.from(initialCitationLinks ?? seedCitationLinks);

  @override
  List<TrainingBook> listBooks() {
    return List<TrainingBook>.unmodifiable(_books);
  }

  @override
  List<BookQuote> listQuotes() {
    return List<BookQuote>.unmodifiable(_quotes);
  }

  @override
  List<CitationLink> listCitationLinks() {
    return List<CitationLink>.unmodifiable(_citationLinks);
  }

  @override
  List<BookQuote> quotesForBook(String bookId) {
    return _quotes.where((BookQuote quote) => quote.bookId == bookId).toList();
  }

  @override
  List<CitationLink> citationsForQuote(String quoteId) {
    return _citationLinks
        .where((CitationLink citation) => citation.quoteId == quoteId)
        .toList();
  }

  @override
  KnowledgeImportResult saveImportedEntry(KnowledgeImportResult result) {
    _books.removeWhere((TrainingBook book) => book.id == result.book.id);
    _quotes.removeWhere((BookQuote quote) => quote.id == result.quote.id);
    _books.add(result.book);
    _quotes.add(result.quote);
    return result;
  }

  @override
  void clearImportedEntries() {
    _books.removeWhere(_isImportedBook);
    _quotes.removeWhere(_isImportedQuote);
    _citationLinks.removeWhere(_isImportedCitation);
  }

  bool _isImportedBook(TrainingBook book) {
    return book.id.startsWith('imported-book-');
  }

  bool _isImportedQuote(BookQuote quote) {
    return quote.id.startsWith('imported-quote-');
  }

  bool _isImportedCitation(CitationLink citation) {
    return citation.id.startsWith('imported-citation-');
  }
}

class PersistedKnowledgeRepository extends InMemoryKnowledgeRepository {
  static const String storageKey = 'trainflow.knowledge_library.v1';

  final LocalStorageService _storageService;

  PersistedKnowledgeRepository(this._storageService) {
    _hydrate();
  }

  @override
  KnowledgeImportResult saveImportedEntry(KnowledgeImportResult result) {
    final KnowledgeImportResult savedResult = super.saveImportedEntry(result);
    _persist();
    return savedResult;
  }

  @override
  void clearImportedEntries() {
    super.clearImportedEntries();
    _persist();
  }

  void _hydrate() {
    final Map<String, dynamic>? storedState =
        _storageService.readJson(storageKey);
    if (storedState == null) {
      return;
    }
    final List<dynamic> bookItems =
        storedState['books'] as List<dynamic>? ?? const [];
    final List<dynamic> quoteItems =
        storedState['quotes'] as List<dynamic>? ?? const [];
    _books.addAll(
      bookItems
          .whereType<Map<String, dynamic>>()
          .map(TrainingBook.fromJson)
          .toList(),
    );
    _quotes.addAll(
      quoteItems
          .whereType<Map<String, dynamic>>()
          .map(BookQuote.fromJson)
          .toList(),
    );
  }

  void _persist() {
    _storageService.saveJson(storageKey, {
      'schemaVersion': 1,
      'books': _books
          .where((TrainingBook book) => book.id.startsWith('imported-book-'))
          .map((TrainingBook book) => book.toJson())
          .toList(),
      'quotes': _quotes
          .where((BookQuote quote) => quote.id.startsWith('imported-quote-'))
          .map((BookQuote quote) => quote.toJson())
          .toList(),
    });
  }
}
