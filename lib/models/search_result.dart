import 'book_content.dart';

class SearchResult {
  final SearchSection section;
  final String snippet;
  final List<String> matchedTerms;
  final double score;

  const SearchResult({
    required this.section,
    required this.snippet,
    required this.matchedTerms,
    required this.score,
  });
}
