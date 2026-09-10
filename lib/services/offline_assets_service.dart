import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/download_progress.dart';
import 'github_service.dart';

class OfflineAssetsService {
  final http.Client client;
  OfflineAssetsService(this.client);
  final Map<String, String> _cached = {};
  final Set<int> _mathVersions = {};
  late Directory _directory;
  late void Function(DownloadProgress) _progress;

  Future<void> prepare(
    Directory directory,
    void Function(DownloadProgress) progress, {
    Set<String>? requiredHtmlPaths,
  }) async {
    _directory = directory;
    _progress = progress;
    _cached.clear();
    _mathVersions.clear();
    final files = await directory
        .list(recursive: true, followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              ['.html', '.css'].contains(path.extension(entry.path)),
        )
        .cast<File>()
        .toList();
    var completed = 0;
    for (final file in files) {
      progress(
        DownloadProgress(
          'Preparing offline assets…',
          completed++ / files.length,
        ),
      );
      final source = await file.readAsString();
      if (file.path.endsWith('.css')) {
        await file.writeAsString(await _rewriteCss(source, null));
        continue;
      }
      final document = parser.parse(source);
      for (final element in document.querySelectorAll(
        'script[src], img[src], source[src], [poster], link[href]',
      )) {
        if (element.localName == 'link' && !_isRenderingLink(element)) continue;
        final attribute = element.localName == 'link'
            ? 'href'
            : element.attributes.containsKey('poster')
            ? 'poster'
            : 'src';
        final original = element.attributes[attribute];
        if (original == null) continue;
        final uri = _remoteUri(original);
        if (uri == null) continue;
        if (element.localName == 'script' &&
            uri.toString().toLowerCase().contains('mathjax')) {
          final major = uri.toString().contains('@4') ? 4 : 3;
          await _cacheMathJax(major);
          final filename = path.posix.basename(uri.path);
          final base = '/_vendor/mathjax$major';
          element.attributes[attribute] = major == 3
              ? '$base/es5/$filename'
              : '$base/$filename';
          element.attributes.remove('integrity');
          element.parentNode!.insertBefore(
            Element.tag('script')..text = _mathConfiguration(major),
            element,
          );
        } else {
          element.attributes[attribute] = await _cacheAsset(uri);
          element.attributes.remove('integrity');
        }
      }
      for (final style in document.querySelectorAll('style')) {
        style.text = await _rewriteCss(style.text, null);
      }
      for (final element in document.querySelectorAll('[style]')) {
        element.attributes['style'] = await _rewriteCss(
          element.attributes['style']!,
          null,
        );
      }
      for (final element in document.querySelectorAll(
        'img[srcset], source[srcset]',
      )) {
        final values = element.attributes['srcset']!;
        var rewritten = values;
        for (final candidate in _parseSourceSet(values).reversed) {
          final uri = _remoteUri(candidate.url);
          if (uri == null) continue;
          final local = await _cacheAsset(uri);
          rewritten = rewritten.replaceRange(
            candidate.start,
            candidate.end,
            local,
          );
        }
        element.attributes['srcset'] = rewritten;
      }
      await file.writeAsString(document.outerHtml);
    }
    await _validateRenderingAssets(
      requiredHtmlPaths ??
          files
              .where((file) => path.extension(file.path) == '.html')
              .map(
                (file) => path
                    .relative(file.path, from: directory.path)
                    .split(path.separator)
                    .join('/'),
              )
              .toSet(),
    );
  }

  Future<void> _validateRenderingAssets(Set<String> htmlPaths) async {
    final stylesheets = <String>[];
    final visitedStylesheets = <String>{};
    for (final htmlPath in htmlPaths) {
      final file = _requiredRelativeFile(htmlPath);
      final document = parser.parse(await file.readAsString());
      for (final element in document.querySelectorAll(
        'script[src], img[src], source[src], [poster]',
      )) {
        for (final attribute in const ['src', 'poster']) {
          final value = element.attributes[attribute];
          if (value != null) _requiredFile(value, htmlPath);
        }
      }
      for (final element in document.querySelectorAll(
        'img[srcset], source[srcset]',
      )) {
        final sourceSet = element.attributes['srcset']!;
        for (final candidate in _parseSourceSet(sourceSet)) {
          _requiredFile(candidate.url, htmlPath);
        }
      }
      for (final link in document.querySelectorAll('link[href]')) {
        if (!_isRenderingLink(link)) continue;
        final relationships = _linkRelationships(link);
        final value = link.attributes['href']!;
        final relative = _requiredRelativePath(value, htmlPath);
        if (relative == null) continue;
        _requiredFile(value, htmlPath);
        if (relationships.contains('stylesheet')) stylesheets.add(relative);
      }
      for (final style in document.querySelectorAll('style')) {
        _validateCss(style.text, htmlPath, stylesheets);
      }
      for (final element in document.querySelectorAll('[style]')) {
        _validateCss(element.attributes['style']!, htmlPath, stylesheets);
      }
    }

    while (stylesheets.isNotEmpty) {
      final stylesheet = stylesheets.removeLast();
      if (!visitedStylesheets.add(stylesheet)) continue;
      final file = _requiredRelativeFile(stylesheet);
      _validateCss(await file.readAsString(), stylesheet, stylesheets);
    }
  }

  void _validateCss(
    String source,
    String sourcePath,
    List<String> stylesheets,
  ) {
    final css = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final imports = RegExp(
      r'''@import\s+(?:url\(\s*)?["']?([^"'\)\s;]+)''',
      caseSensitive: false,
    );
    for (final match in imports.allMatches(css)) {
      final value = match.group(1)!;
      final relative = _requiredRelativePath(value, sourcePath);
      if (relative == null) continue;
      _requiredFile(value, sourcePath);
      stylesheets.add(relative);
    }
    final urls = RegExp(
      r'''url\(\s*["']?([^"')]+)["']?\s*\)''',
      caseSensitive: false,
    );
    for (final match in urls.allMatches(css)) {
      _requiredFile(match.group(1)!.trim(), sourcePath);
    }
  }

  File _requiredFile(String reference, String sourcePath) {
    final relative = _requiredRelativePath(reference, sourcePath);
    if (relative == null) return File(_directory.path);
    return _requiredRelativeFile(relative);
  }

  File _requiredRelativeFile(String relative) {
    final file = File(path.join(_directory.path, relative));
    if (!file.existsSync()) {
      throw ContentException(
        'A rendering resource is missing from the published book: $relative.',
      );
    }
    final rootPath = _directory.resolveSymbolicLinksSync();
    final targetPath = file.resolveSymbolicLinksSync();
    if (targetPath != rootPath && !path.isWithin(rootPath, targetPath)) {
      throw ContentException(
        'A rendering resource has an unsafe path: $relative.',
      );
    }
    return file;
  }

  String? _requiredRelativePath(String reference, String sourcePath) {
    final trimmed = reference.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('/__reader__/')) {
      return null;
    }
    final uri = Uri.tryParse(
      trimmed.startsWith('//') ? 'https:$trimmed' : trimmed,
    );
    if (uri == null) {
      throw ContentException(
        'A rendering resource has an unsafe path in $sourcePath.',
      );
    }
    if (uri.hasScheme || uri.hasAuthority) {
      throw ContentException(
        'A rendering resource is not available offline in $sourcePath: '
        '$trimmed.',
      );
    }
    String decoded;
    try {
      decoded = Uri.decodeComponent(uri.path);
    } on FormatException {
      throw ContentException(
        'A rendering resource has an unsafe path in $sourcePath.',
      );
    }
    if (decoded.contains('\\') || decoded.contains('\u0000')) {
      throw ContentException(
        'A rendering resource has an unsafe path in $sourcePath: $decoded.',
      );
    }
    final relative = decoded.startsWith('/')
        ? decoded.substring(1)
        : path.posix.join(path.posix.dirname(sourcePath), decoded);
    final normalised = path.posix.normalize(relative);
    if (normalised.isEmpty ||
        normalised == '.' ||
        normalised == '..' ||
        normalised.startsWith('../')) {
      throw ContentException(
        'A rendering resource has an unsafe path in $sourcePath: $decoded.',
      );
    }
    return normalised;
  }

  List<String> _linkRelationships(Element link) =>
      (link.attributes['rel'] ?? '').toLowerCase().split(RegExp(r'\s+'));

  bool _isRenderingLink(Element link) => _linkRelationships(link).any(
    (relationship) => relationship == 'stylesheet' || relationship == 'icon',
  );

  Uri? _remoteUri(String value, [Uri? base]) {
    final trimmed = value.trim();
    if (trimmed.startsWith('data:') ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('/_remote/') ||
        trimmed.startsWith('/_vendor/')) {
      return null;
    }
    final uri = Uri.tryParse(
      trimmed.startsWith('//') ? 'https:$trimmed' : trimmed,
    );
    if (uri == null) return null;
    final resolved = base == null ? uri : base.resolveUri(uri);
    return ['https', 'http'].contains(resolved.scheme) ? resolved : null;
  }

  Future<String> _cacheAsset(Uri uri) async {
    final key = uri.toString();
    final cached = _cached[key];
    if (cached != null) return cached;
    final digest = sha256.convert(utf8.encode(key)).toString();
    var basename = path.posix.basename(uri.path);
    if (basename.isEmpty) {
      basename = 'asset';
    }
    // Google Fonts CSS endpoints have no extension; keep an explicit CSS MIME type.
    final isCss =
        basename.endsWith('.css') || uri.host == 'fonts.googleapis.com';
    if (isCss && !basename.endsWith('.css')) basename += '.css';
    basename = basename.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final relative = '/_remote/$digest/$basename';
    _cached[key] = relative; // Break circular stylesheet imports.
    final file = File(path.join(_directory.path, relative.substring(1)));
    await file.parent.create(recursive: true);
    final bytes = await _download(uri);
    if (isCss) {
      await file.writeAsString(await _rewriteCss(utf8.decode(bytes), uri));
    } else {
      await file.writeAsBytes(bytes);
    }
    return relative;
  }

  Future<String> _rewriteCss(String source, Uri? base) async {
    var result = source;
    final patterns = [
      RegExp(r'''url\(\s*["']?([^"')]+)["']?\s*\)'''),
      RegExp(r'''@import\s*["']([^"']+)["']'''),
    ];
    for (final pattern in patterns) {
      final matches = pattern.allMatches(result).toList().reversed;
      for (final match in matches) {
        final uri = _remoteUri(match.group(1)!, base);
        if (uri == null) continue;
        final local = await _cacheAsset(uri);
        final original = match.group(0)!;
        final replacement = original.replaceFirst(match.group(1)!, local);
        result = result.replaceRange(match.start, match.end, replacement);
      }
    }
    return result;
  }

  Future<List<int>> _download(Uri uri) async {
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'QuartoReader/1.0';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ContentException(
        'An offline asset could not be downloaded from ${uri.host}. '
        'Please try again.',
      );
    }
    final builder = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 60),
    )) {
      builder.addAll(chunk);
      if (builder.length > 100 * 1024 * 1024) {
        throw const ContentException('An offline asset is too large.');
      }
    }
    return builder;
  }

  Future<void> _cacheMathJax(int major) async {
    if (!_mathVersions.add(major)) return;
    _progress(const DownloadProgress('Downloading offline equation support…'));
    final version = major == 3 ? '3.2.2' : '4.1.3';
    final bytes = await _download(
      Uri.parse('https://registry.npmjs.org/mathjax/-/mathjax-$version.tgz'),
    );
    final output = path.join(_directory.path, '_vendor', 'mathjax$major');
    await Isolate.run(() => _extractPackage(bytes, output));
    if (major == 4) {
      final font = await _download(
        Uri.parse(
          'https://registry.npmjs.org/@mathjax/mathjax-newcm-font/-/mathjax-newcm-font-4.1.3.tgz',
        ),
      );
      final fontOutput = path.join(
        _directory.path,
        '_vendor',
        'fonts',
        'mathjax-newcm-font',
      );
      await Isolate.run(() => _extractPackage(font, fontOutput));
    }
  }

  static void _extractPackage(List<int> compressed, String outputPath) {
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(compressed),
    );
    var total = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (!entry.name.startsWith('package/') ||
          entry.isSymbolicLink ||
          entry.name.contains('\\') ||
          entry.name.split('/').contains('..')) {
        throw const ContentException(
          'An equation package contains an unsafe path.',
        );
      }
      total += entry.size;
      if (total > 300 * 1024 * 1024) {
        throw const ContentException('An equation package is too large.');
      }
      final file = File(path.join(outputPath, entry.name.substring(8)));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.content);
    }
  }

  static String _mathConfiguration(int major) {
    final base = '/_vendor/mathjax$major';
    if (major == 3) {
      return '''
window.MathJax = window.MathJax || {};
window.MathJax.loader = window.MathJax.loader || {};
window.MathJax.loader.paths = Object.assign({}, window.MathJax.loader.paths, {mathjax: '$base/es5'});
window.MathJax.chtml = Object.assign({}, window.MathJax.chtml, {fontURL: '$base/es5/output/chtml/fonts/woff-v2'});
''';
    }
    return '''
window.MathJax = window.MathJax || {};
window.MathJax.loader = window.MathJax.loader || {};
window.MathJax.loader.paths = Object.assign({}, window.MathJax.loader.paths, {mathjax: '$base', fonts: '/_vendor/fonts'});
window.MathJax.output = Object.assign({}, window.MathJax.output, {fontPath: '/_vendor/fonts/%%FONT%%-font'});
window.MathJax.chtml = Object.assign({}, window.MathJax.chtml, {fontURL: '/_vendor/fonts/mathjax-newcm-font/chtml/woff2', dynamicPrefix: '/_vendor/fonts/mathjax-newcm-font/chtml/dynamic'});
''';
  }
}

class _SourceSetCandidate {
  final String url;
  final int start;
  final int end;

  const _SourceSetCandidate(this.url, this.start, this.end);
}

List<_SourceSetCandidate> _parseSourceSet(String input) {
  // Match the URL-splitting states in the WHATWG srcset parsing algorithm.
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
