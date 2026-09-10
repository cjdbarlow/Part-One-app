import 'package:path/path.dart' as path;

class PublishedUrlNormaliser {
  const PublishedUrlNormaliser({
    required this.publishedOrigin,
    required this.entryPage,
  });

  final Uri publishedOrigin;
  final String entryPage;

  String reference(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('/') || trimmed.startsWith('//')) return value;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.hasAuthority || uri.hasScheme) return value;

    final containedPath = _pathWithinPublication(uri.path);
    if (containedPath == null) {
      return publishedOrigin.resolveUri(uri).toString();
    }
    final localPath = containedPath.isEmpty ? entryPage : containedPath;
    return Uri(
      path: '/$localPath',
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  String sourceSet(String value) {
    var rewritten = value;
    for (final candidate in _sourceSetCandidates(value).reversed) {
      rewritten = rewritten.replaceRange(
        candidate.start,
        candidate.end,
        reference(candidate.url),
      );
    }
    return rewritten;
  }

  String css(String source) {
    var rewritten = source;
    final patterns = [
      RegExp(r'''url\(\s*["']?([^"')]+)["']?\s*\)'''),
      RegExp(r'''@import\s*["']([^"']+)["']'''),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(rewritten).toList().reversed) {
        final original = match.group(1)!;
        final replacement = reference(original);
        if (replacement == original) continue;
        rewritten = rewritten.replaceRange(
          match.start + match.group(0)!.indexOf(original),
          match.start + match.group(0)!.indexOf(original) + original.length,
          replacement,
        );
      }
    }
    return rewritten;
  }

  String? _pathWithinPublication(String uriPath) {
    var sitePath = publishedOrigin.path;
    if (!sitePath.startsWith('/')) sitePath = '/$sitePath';
    if (!sitePath.endsWith('/')) sitePath = '$sitePath/';
    sitePath = path.posix.normalize(sitePath);
    if (!sitePath.endsWith('/')) sitePath = '$sitePath/';
    if (sitePath == '/') return uriPath.replaceFirst(RegExp(r'^/+'), '');

    final rootPath = sitePath.substring(0, sitePath.length - 1);
    if (uriPath == rootPath) return '';
    if (!uriPath.startsWith(sitePath)) return null;
    return uriPath.substring(sitePath.length);
  }
}

class _SourceSetCandidate {
  const _SourceSetCandidate(this.url, this.start, this.end);

  final String url;
  final int start;
  final int end;
}

List<_SourceSetCandidate> _sourceSetCandidates(String input) {
  final candidates = <_SourceSetCandidate>[];
  var position = 0;
  while (position < input.length) {
    while (position < input.length &&
        (_isAsciiWhitespace(input.codeUnitAt(position)) ||
            input.codeUnitAt(position) == 0x2c)) {
      position++;
    }
    if (position >= input.length) break;

    final start = position;
    while (position < input.length &&
        !_isAsciiWhitespace(input.codeUnitAt(position))) {
      position++;
    }
    var end = position;
    while (end > start && input.codeUnitAt(end - 1) == 0x2c) {
      end--;
    }
    if (end > start) {
      candidates.add(
        _SourceSetCandidate(input.substring(start, end), start, end),
      );
    }
    if (end != position) continue;

    var parenthesisDepth = 0;
    while (position < input.length) {
      final character = input.codeUnitAt(position);
      if (character == 0x28) {
        parenthesisDepth++;
      } else if (character == 0x29 && parenthesisDepth > 0) {
        parenthesisDepth--;
      } else if (character == 0x2c && parenthesisDepth == 0) {
        position++;
        break;
      }
      position++;
    }
  }
  return candidates;
}

bool _isAsciiWhitespace(int character) =>
    character == 0x09 ||
    character == 0x0a ||
    character == 0x0c ||
    character == 0x0d ||
    character == 0x20;
