import '../models/book_content.dart';
import '../models/search_result.dart';

class SearchService {
  SearchService(List<SearchSection> sections)
    : _sections = List.generate(
        sections.length,
        (index) => _IndexedSection(sections[index], index),
        growable: false,
      ),
      _glossary = _collectGlossary(sections);

  final List<_IndexedSection> _sections;
  final List<_GlossaryEntry> _glossary;

  List<SearchResult> search(String query, {int limit = 40}) {
    if (limit <= 0) return const [];
    final queryWords = _tokenise(query).map((token) => token.lower).toList();
    if (queryWords.isEmpty) return const [];

    final concepts = _queryConcepts(queryWords);
    final results = <_ScoredResult>[];
    for (final indexed in _sections) {
      final matches = <_WordMatch>[];
      var score = 0.0;
      var matchesAllConcepts = true;

      for (final concept in concepts) {
        final match = _bestConceptMatch(concept, indexed);
        if (match == null) {
          matchesAllConcepts = false;
          break;
        }
        score += match.score;
        matches.addAll(match.words);
      }
      if (!matchesAllConcepts) continue;

      final normalisedQuery = queryWords.join(' ');
      if (indexed.titleText.contains(normalisedQuery)) score += 12;
      if (indexed.headingText.contains(normalisedQuery)) score += 9;
      if (indexed.bodyText.contains(normalisedQuery)) score += 4;
      final subject = queryWords.first;
      if (indexed.titleTokens.contains(subject)) score += 8;
      if (indexed.hasRealHeading && indexed.headingTokens.contains(subject)) {
        score += 5;
      }

      final matchedTerms = _uniqueTerms(
        matches.map((match) => match.token.original),
      );
      final metadataTerms = {...indexed.titleTokens, ...indexed.headingTokens};
      final preferredBodyMatches = matches.where(
        (match) =>
            match.bodyPosition != null &&
            !metadataTerms.contains(match.token.lower),
      );
      final bodyMatches = preferredBodyMatches.isEmpty
          ? matches.where((match) => match.bodyPosition != null)
          : preferredBodyMatches;
      results.add(
        _ScoredResult(
          indexed: indexed,
          hasContentMatch: matches.any((match) => match.hasContentMatch),
          result: SearchResult(
            section: indexed.section,
            snippet: _snippet(
              indexed.bodySource,
              bodyMatches.map((match) => match.bodyPosition!).toList(),
            ),
            matchedTerms: matchedTerms,
            score: score,
          ),
        ),
      );
    }

    final collapsed = _collapseTitleOnlyDuplicates(results);
    collapsed.sort((first, second) {
      final byScore = second.result.score.compareTo(first.result.score);
      if (byScore != 0) return byScore;
      final byTitle = first.result.section.pageTitle.compareTo(
        second.result.section.pageTitle,
      );
      if (byTitle != 0) return byTitle;
      return first.result.section.heading.compareTo(
        second.result.section.heading,
      );
    });
    return collapsed
        .take(limit)
        .map((match) => match.result)
        .toList(growable: false);
  }

  List<_ScoredResult> _collapseTitleOnlyDuplicates(
    List<_ScoredResult> results,
  ) {
    final byPage = <String, List<_ScoredResult>>{};
    for (final result in results) {
      byPage.putIfAbsent(result.result.section.pagePath, () => []).add(result);
    }

    final collapsed = <_ScoredResult>[];
    for (final pageResults in byPage.values) {
      final contentMatches = pageResults
          .where((result) => result.hasContentMatch)
          .toList();
      if (contentMatches.isNotEmpty) {
        collapsed.addAll(contentMatches);
        continue;
      }
      pageResults.sort(
        (first, second) =>
            first.indexed.inputIndex.compareTo(second.indexed.inputIndex),
      );
      collapsed.add(pageResults.first);
    }
    return collapsed;
  }

  List<_QueryConcept> _queryConcepts(List<String> words) {
    final concepts = <_QueryConcept>[];
    var index = 0;
    while (index < words.length) {
      _GlossaryEntry? phraseEntry;
      for (final entry in _glossary) {
        if (_startsWithWords(words, index, entry.expansion) ||
            _startsWithWords(words, index, entry.abbreviation)) {
          phraseEntry = entry;
          break;
        }
      }

      if (phraseEntry == null) {
        concepts.add(
          _QueryConcept([
            [words[index]],
          ]),
        );
        index++;
        continue;
      }

      concepts.add(
        _QueryConcept([phraseEntry.abbreviation, phraseEntry.expansion]),
      );
      final matchesExpansion = _startsWithWords(
        words,
        index,
        phraseEntry.expansion,
      );
      index += matchesExpansion
          ? phraseEntry.expansion.length
          : phraseEntry.abbreviation.length;
    }
    return concepts;
  }

  _ConceptMatch? _bestConceptMatch(
    _QueryConcept concept,
    _IndexedSection section,
  ) {
    _ConceptMatch? best;
    for (final alias in concept.aliases) {
      final words = <_WordMatch>[];
      var score = 0.0;
      var complete = true;
      for (final queryWord in alias) {
        final wordMatch = _bestWordMatch(queryWord, section.tokens);
        if (wordMatch == null) {
          complete = false;
          break;
        }
        score += wordMatch.score;
        words.add(wordMatch);
      }
      if (complete && (best == null || score > best.score)) {
        best = _ConceptMatch(score, words);
      }
    }
    return best;
  }

  _WordMatch? _bestWordMatch(String queryWord, List<_WeightedToken> tokens) {
    _MatchedCandidate? best;
    _MatchedCandidate? bestBody;
    _MatchedCandidate? bestHeading;
    for (final weightedToken in tokens) {
      final quality = _matchQuality(queryWord, weightedToken.token.lower);
      if (quality == 0) continue;
      final candidate = _MatchedCandidate(
        weightedToken,
        quality * weightedToken.weight,
      );
      if (best == null || candidate.score > best.score) best = candidate;
      if (weightedToken.field == _MatchField.body &&
          (bestBody == null || candidate.score > bestBody.score)) {
        bestBody = candidate;
      }
      if (weightedToken.field == _MatchField.heading &&
          (bestHeading == null || candidate.score > bestHeading.score)) {
        bestHeading = candidate;
      }
    }
    if (best == null) return null;

    final content = bestBody ?? bestHeading;
    final contentContribution =
        best.weightedToken.field == _MatchField.title && content != null
        ? content.score * 0.5
        : 0.0;
    final displayedMatch = bestBody ?? bestHeading ?? best;
    return _WordMatch(
      displayedMatch.weightedToken.token,
      best.score + contentContribution,
      hasContentMatch: content != null,
      bodyPosition: bestBody?.weightedToken.token.start,
    );
  }

  double _matchQuality(String query, String candidate) {
    if (query == candidate) return 1;
    if (query.length >= 3 && candidate.startsWith(query)) return 0.72;
    if (query.length < 4 || candidate.length < 4) return 0;

    final maximumDistance = query.length >= 8 ? 2 : 1;
    if ((query.length - candidate.length).abs() > maximumDistance) return 0;
    if (query.codeUnitAt(0) != candidate.codeUnitAt(0)) return 0;
    final distance = _boundedEditDistance(query, candidate, maximumDistance);
    return distance <= maximumDistance ? 0.48 : 0;
  }

  int _boundedEditDistance(String first, String second, int maximum) {
    var previous = List<int>.generate(second.length + 1, (index) => index);
    for (var firstIndex = 1; firstIndex <= first.length; firstIndex++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = firstIndex;
      var rowMinimum = current[0];
      for (var secondIndex = 1; secondIndex <= second.length; secondIndex++) {
        final substitutionCost =
            first.codeUnitAt(firstIndex - 1) ==
                second.codeUnitAt(secondIndex - 1)
            ? 0
            : 1;
        current[secondIndex] = _minimum(
          current[secondIndex - 1] + 1,
          previous[secondIndex] + 1,
          previous[secondIndex - 1] + substitutionCost,
        );
        if (current[secondIndex] < rowMinimum) {
          rowMinimum = current[secondIndex];
        }
      }
      if (rowMinimum > maximum) return maximum + 1;
      previous = current;
    }
    return previous.last;
  }

  int _minimum(int first, int second, int third) {
    final pairMinimum = first < second ? first : second;
    return pairMinimum < third ? pairMinimum : third;
  }

  String _snippet(String compact, List<int> matchPositions) {
    if (compact.isEmpty) return '';

    final matchIndex = matchPositions.isEmpty
        ? 0
        : matchPositions.reduce(
            (first, second) => first < second ? first : second,
          );

    var start = matchIndex > 70 ? matchIndex - 70 : 0;
    var end = start + 180;
    if (end > compact.length) end = compact.length;
    if (start > 0) {
      final nextSpace = compact.indexOf(' ', start);
      if (nextSpace >= 0 && nextSpace < matchIndex) start = nextSpace + 1;
    }
    if (end < compact.length) {
      final previousSpace = compact.lastIndexOf(' ', end);
      if (previousSpace > matchIndex) end = previousSpace;
    }

    return '${start > 0 ? '…' : ''}${compact.substring(start, end)}'
        '${end < compact.length ? '…' : ''}';
  }

  List<String> _uniqueTerms(Iterable<String> terms) {
    final seen = <String>{};
    final unique = <String>[];
    for (final term in terms) {
      if (seen.add(term.toLowerCase())) unique.add(term);
    }
    return unique;
  }

  bool _startsWithWords(List<String> source, int start, List<String> expected) {
    if (start + expected.length > source.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (source[start + index] != expected[index]) return false;
    }
    return true;
  }

  static List<_GlossaryEntry> _collectGlossary(List<SearchSection> sections) {
    final entries = <String, _GlossaryEntry>{};
    for (final section in sections) {
      for (final entry in section.glossary.entries) {
        final abbreviation = _tokenise(
          entry.key,
        ).map((token) => token.lower).toList();
        final expansion = _tokenise(
          entry.value,
        ).map((token) => token.lower).toList();
        if (abbreviation.isEmpty || expansion.isEmpty) continue;
        entries['${abbreviation.join(' ')}|${expansion.join(' ')}'] =
            _GlossaryEntry(abbreviation, expansion);
      }
    }
    final sorted = entries.values.toList();
    sorted.sort((first, second) {
      final firstLength = first.expansion.length > first.abbreviation.length
          ? first.expansion.length
          : first.abbreviation.length;
      final secondLength = second.expansion.length > second.abbreviation.length
          ? second.expansion.length
          : second.abbreviation.length;
      return secondLength.compareTo(firstLength);
    });
    return sorted;
  }
}

class _IndexedSection {
  _IndexedSection(this.section, this.inputIndex)
    : titleText = section.pageTitle.toLowerCase(),
      headingText = section.heading.toLowerCase(),
      hasRealHeading = section.anchor != 'quarto-document-content',
      bodySource = _compactText(section.text),
      bodyText = _compactText(section.text).toLowerCase(),
      titleTokens = _tokenise(
        section.pageTitle,
      ).map((token) => token.lower).toSet(),
      headingTokens = _tokenise(
        section.heading,
      ).map((token) => token.lower).toSet(),
      tokens = [
        ..._tokenise(
          section.pageTitle,
        ).map((token) => _WeightedToken(token, 12, _MatchField.title)),
        if (section.anchor != 'quarto-document-content')
          ..._tokenise(
            section.heading,
          ).map((token) => _WeightedToken(token, 9, _MatchField.heading)),
        ..._tokenise(
          _compactText(section.text),
        ).map((token) => _WeightedToken(token, 4, _MatchField.body)),
      ];

  final SearchSection section;
  final int inputIndex;
  final String titleText;
  final String headingText;
  final bool hasRealHeading;
  final String bodySource;
  final String bodyText;
  final Set<String> titleTokens;
  final Set<String> headingTokens;
  final List<_WeightedToken> tokens;
}

class _Token {
  _Token(String value, this.start)
    : original = value,
      lower = value.toLowerCase();

  final String original;
  final String lower;
  final int start;
}

List<_Token> _tokenise(String value) {
  return RegExp(r"[\p{L}\p{N}]+(?:[’'][\p{L}\p{N}]+)?", unicode: true)
      .allMatches(value)
      .map((match) => _Token(match.group(0)!, match.start))
      .toList(growable: false);
}

String _compactText(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

enum _MatchField { title, heading, body }

class _WeightedToken {
  const _WeightedToken(this.token, this.weight, this.field);

  final _Token token;
  final double weight;
  final _MatchField field;
}

class _MatchedCandidate {
  const _MatchedCandidate(this.weightedToken, this.score);

  final _WeightedToken weightedToken;
  final double score;
}

class _GlossaryEntry {
  const _GlossaryEntry(this.abbreviation, this.expansion);

  final List<String> abbreviation;
  final List<String> expansion;
}

class _QueryConcept {
  const _QueryConcept(this.aliases);

  final List<List<String>> aliases;
}

class _WordMatch {
  const _WordMatch(
    this.token,
    this.score, {
    required this.hasContentMatch,
    required this.bodyPosition,
  });

  final _Token token;
  final double score;
  final bool hasContentMatch;
  final int? bodyPosition;
}

class _ConceptMatch {
  const _ConceptMatch(this.score, this.words);

  final double score;
  final List<_WordMatch> words;
}

class _ScoredResult {
  const _ScoredResult({
    required this.indexed,
    required this.result,
    required this.hasContentMatch,
  });

  final _IndexedSection indexed;
  final SearchResult result;
  final bool hasContentMatch;
}
