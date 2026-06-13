import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pdfrx/pdfrx.dart';

import '../reader/domain/figurine_map.dart';
import '../reader/presentation/epub_book_view.dart';
import '../reader/state/book_providers.dart';

/// A search match: which page/chapter, and a text snippet around the hit.
class SearchHit {
  const SearchHit({required this.page, required this.snippet});

  /// PDF page number, or EPUB chapter index + 1.
  final int page;
  final String snippet;
}

class SearchState {
  const SearchState({
    this.query = '',
    this.hits = const [],
    this.searching = false,
  });

  final String query;
  final List<SearchHit> hits;
  final bool searching;
}

/// Full-text search over the open book. Queries are figurine-normalized, so
/// searching "Nf3" also finds "♘f3" and the book's mapped figurine sequences.
/// PDF page texts are extracted once and cached for the session.
class BookSearch extends Notifier<SearchState> {
  String? _cachedPath;
  List<String>? _normalizedPages; // PDF: normalized text per page (index 0 = page 1)

  @override
  SearchState build() => const SearchState();

  Future<void> search(String rawQuery) async {
    final query = normalizeFigurines(rawQuery).text.trim().toLowerCase();
    if (query.isEmpty) {
      state = const SearchState();
      return;
    }
    final path = ref.read(openedBookProvider);
    if (path == null) return;
    state = SearchState(query: rawQuery, searching: true);

    final hits = path.toLowerCase().endsWith('.epub')
        ? await _searchEpub(path, query)
        : await _searchPdf(path, query);

    state = SearchState(query: rawQuery, hits: hits, searching: false);
  }

  void clear() => state = const SearchState();

  Future<List<SearchHit>> _searchPdf(String path, String query) async {
    if (_cachedPath != path || _normalizedPages == null) {
      final doc = await PdfDocument.openFile(path);
      final pages = <String>[];
      for (final page in doc.pages) {
        final text = await page.loadStructuredText();
        pages.add(normalizeFigurines(text.fullText).text);
      }
      doc.dispose();
      _normalizedPages = pages;
      _cachedPath = path;
    }
    final hits = <SearchHit>[];
    for (var i = 0; i < _normalizedPages!.length; i++) {
      final idx = _normalizedPages![i].toLowerCase().indexOf(query);
      if (idx >= 0) {
        hits.add(SearchHit(
          page: i + 1,
          snippet: _snippet(_normalizedPages![i], idx, query.length),
        ));
      }
    }
    return hits;
  }

  Future<List<SearchHit>> _searchEpub(String path, String query) async {
    final book = await ref.read(epubBookProvider(path).future);
    final hits = <SearchHit>[];
    for (var i = 0; i < book.chapters.length; i++) {
      // Strip tags to plain text for snippet/search.
      final plain = html_parser.parse(book.chapters[i].html).body?.text ?? '';
      final norm = normalizeFigurines(plain).text;
      final idx = norm.toLowerCase().indexOf(query);
      if (idx >= 0) {
        hits.add(SearchHit(
          page: i + 1,
          snippet: _snippet(norm, idx, query.length),
        ));
      }
    }
    return hits;
  }

  String _snippet(String text, int idx, int len) {
    final start = (idx - 40).clamp(0, text.length);
    final end = (idx + len + 40).clamp(0, text.length);
    final s = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${start > 0 ? '…' : ''}$s${end < text.length ? '…' : ''}';
  }
}

final bookSearchProvider =
    NotifierProvider<BookSearch, SearchState>(BookSearch.new);
