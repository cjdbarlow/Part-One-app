import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;

import '../models/book_config.dart';
import '../models/book_content.dart';
import 'published_url_normaliser.dart';

class ImportedPage {
  final String html;
  final String title;
  final List<ChapterNode> chapters;
  final List<SearchSection> sections;
  final Set<String> localReferences;

  const ImportedPage({
    required this.html,
    required this.title,
    required this.chapters,
    required this.sections,
    required this.localReferences,
  });
}

class HtmlImporter {
  HtmlImporter(this._config);

  final BookConfig _config;

  ImportedPage importPage(String source, String pagePath) {
    final document = html_parser.parse(source);
    final normalisedPagePath = _normalisePath(pagePath);
    final generator = document
        .querySelector('meta[name="generator"]')
        ?.attributes['content'];
    final main = document.querySelector('main#quarto-document-content');

    if (generator == null ||
        !generator.toLowerCase().startsWith('quarto') ||
        main == null) {
      throw const FormatException('The page is not compatible Quarto HTML.');
    }

    _ensureHeadingAnchors(document, main, normalisedPagePath);

    final title = _pageTitle(document, main);
    final chapters = _extractChapters(document, normalisedPagePath);
    final references = _collectLocalReferences(document, normalisedPagePath);
    final sections = _extractSections(main, normalisedPagePath, title);

    _normalisePublishedReferences(document);
    _injectReaderAssets(document);

    return ImportedPage(
      html: document.outerHtml,
      title: title,
      chapters: chapters,
      sections: sections,
      localReferences: references,
    );
  }

  String normaliseStylesheet(String source) => _publishedUrls.css(source);

  PublishedUrlNormaliser get _publishedUrls => PublishedUrlNormaliser(
    publishedOrigin: _config.siteUrl,
    entryPage: _config.entryPage,
  );

  void _normalisePublishedReferences(Document document) {
    for (final element in document.querySelectorAll(
      '[href], [src], [poster]',
    )) {
      for (final attribute in const ['href', 'src', 'poster']) {
        final value = element.attributes[attribute];
        if (value != null) {
          element.attributes[attribute] = _publishedUrls.reference(value);
        }
      }
    }
    for (final element in document.querySelectorAll(
      'img[srcset], source[srcset]',
    )) {
      element.attributes['srcset'] = _publishedUrls.sourceSet(
        element.attributes['srcset']!,
      );
    }
    for (final style in document.querySelectorAll('style')) {
      style.text = _publishedUrls.css(style.text);
    }
    for (final element in document.querySelectorAll('[style]')) {
      element.attributes['style'] = _publishedUrls.css(
        element.attributes['style']!,
      );
    }
  }

  String _pageTitle(Document document, Element main) {
    final titleElement =
        main.querySelector('h1.title') ??
        main.querySelector('.quarto-title h1') ??
        main.querySelector('h1');
    final heading = titleElement == null ? '' : _labelText(titleElement);
    if (heading.isNotEmpty) return heading;

    final documentTitle = _normaliseText(
      document.querySelector('title')?.text ?? '',
    );
    if (documentTitle.isNotEmpty) {
      return documentTitle.split(RegExp(r'\s+[–—-]\s+')).first.trim();
    }
    return _config.title;
  }

  List<ChapterNode> _extractChapters(Document document, String pagePath) {
    final sidebar = document.querySelector('nav#quarto-sidebar');
    final rootList = sidebar?.querySelector('ul');
    if (rootList == null) return const [];
    return _parseChapterList(rootList, pagePath);
  }

  List<ChapterNode> _parseChapterList(Element list, String pagePath) {
    final chapters = <ChapterNode>[];
    for (final item in _directChildren(list, 'li')) {
      final containers = _directChildren(
        item,
        'div',
      ).where((element) => element.classes.contains('sidebar-item-container'));
      final container = containers.isEmpty ? null : containers.first;
      final link = container?.querySelector('.sidebar-item-text');
      final nestedLists = _directChildren(
        item,
        'ul',
      ).where((element) => element.classes.contains('sidebar-section'));
      final nestedList = nestedLists.isEmpty ? null : nestedLists.first;
      final children = nestedList == null
          ? const <ChapterNode>[]
          : _parseChapterList(nestedList, pagePath);

      final isSeparator =
          link?.querySelector('hr, .sidebar-divider') != null ||
          link?.classes.contains('sidebar-divider') == true;
      final title = link == null ? '' : _labelText(link);
      final rawHref = link?.attributes['href'];
      final href = rawHref == null
          ? null
          : _resolveLocalReference(rawHref, pagePath);

      if (isSeparator || title.isEmpty) {
        chapters.addAll(children);
        continue;
      }
      if (rawHref != null && href == null) {
        chapters.addAll(children);
        continue;
      }

      chapters.add(ChapterNode(title: title, href: href, children: children));
    }
    return chapters;
  }

  Set<String> _collectLocalReferences(Document document, String pagePath) {
    final references = <String>{};
    for (final element in document.querySelectorAll('[href], [src]')) {
      for (final attribute in const ['href', 'src']) {
        final value = element.attributes[attribute];
        if (value == null || value.trim().isEmpty) continue;
        final resolved = _resolveLocalReference(value, pagePath);
        if (resolved != null) references.add(resolved);
      }
    }
    return references;
  }

  String? _resolveLocalReference(String rawReference, String pagePath) {
    final reference = rawReference.trim();
    if (reference.isEmpty) return null;
    if (reference.startsWith('#')) return '$pagePath$reference';

    final uri = Uri.tryParse(reference);
    if (uri == null) return null;
    if (uri.scheme.isNotEmpty &&
        uri.scheme != 'http' &&
        uri.scheme != 'https') {
      return null;
    }

    String bookPath;
    if (uri.hasAuthority || uri.scheme == 'http' || uri.scheme == 'https') {
      if (!_sameOrigin(uri, _config.siteUrl)) return null;
      final containedPath = _pathWithinSite(uri.path);
      if (containedPath == null) return null;
      bookPath = containedPath.isEmpty ? _config.entryPage : containedPath;
    } else if (reference.startsWith('/')) {
      final containedPath = _pathWithinSite(uri.path);
      if (containedPath == null) return null;
      bookPath = containedPath.isEmpty ? _config.entryPage : containedPath;
    } else {
      final base = Uri.parse('https://quarto-reader.local/$pagePath');
      final resolved = base.resolveUri(uri);
      bookPath = resolved.path.replaceFirst(RegExp(r'^/+'), '');
    }

    final normalised = _normalisePath(bookPath);
    if (normalised.isEmpty || normalised == '.') return null;
    return Uri(
      path: normalised,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  bool _sameOrigin(Uri first, Uri second) {
    final firstPort = first.hasPort
        ? first.port
        : (first.scheme == 'http' ? 80 : 443);
    final secondPort = second.hasPort
        ? second.port
        : (second.scheme == 'http' ? 80 : 443);
    return first.host.toLowerCase() == second.host.toLowerCase() &&
        firstPort == secondPort;
  }

  String? _pathWithinSite(String uriPath) {
    var sitePath = _config.siteUrl.path;
    if (!sitePath.startsWith('/')) sitePath = '/$sitePath';
    if (!sitePath.endsWith('/')) sitePath = '$sitePath/';
    if (sitePath == '/') return uriPath.replaceFirst(RegExp(r'^/+'), '');

    final withoutTrailingSlash = sitePath.substring(0, sitePath.length - 1);
    if (uriPath == withoutTrailingSlash) return '';
    if (!uriPath.startsWith(sitePath)) return null;
    return uriPath.substring(sitePath.length);
  }

  String _normalisePath(String value) {
    final withoutLeadingSlash = value.replaceFirst(RegExp(r'^/+'), '');
    final normalised = path.posix.normalize(withoutLeadingSlash);
    if (normalised == '..' || normalised.startsWith('../')) return '';
    return normalised == '.' ? '' : normalised;
  }

  void _ensureHeadingAnchors(Document document, Element main, String pagePath) {
    var generatedIndex = 0;
    for (final heading in main.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
      if (_hasAncestorWithId(heading, 'title-block-header')) continue;
      if (heading.id.isNotEmpty) continue;

      final dataAnchor = heading.attributes['data-anchor-id'];
      if (dataAnchor != null && dataAnchor.isNotEmpty) {
        if (document.getElementById(dataAnchor) == null) {
          heading.id = dataAnchor;
        }
        continue;
      }

      final seed = '$pagePath|${_normaliseText(heading.text)}|$generatedIndex';
      heading.id = 'qr-section-${_stableHash(seed)}';
      generatedIndex++;
    }
  }

  bool _hasAncestorWithId(Element element, String id) {
    Element? parent = element.parent;
    while (parent != null) {
      if (parent.id == id) return true;
      parent = parent.parent;
    }
    return false;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  List<SearchSection> _extractSections(
    Element displayedMain,
    String pagePath,
    String pageTitle,
  ) {
    final main = displayedMain.clone(true);
    _removeSearchExcludedContent(main);

    final output = <SearchSection>[];
    var current = _SectionBuilder(heading: pageTitle, anchor: displayedMain.id);

    void flush() {
      final text = _normaliseText(current.text.toString());
      if (text.isEmpty) return;
      output.add(
        SearchSection(
          pagePath: pagePath,
          pageTitle: pageTitle,
          heading: current.heading,
          anchor: current.anchor,
          text: text,
          glossary: Map.unmodifiable(current.glossary),
        ),
      );
    }

    void walk(Node node) {
      if (node is Text) {
        current.text.write(' ${node.data} ');
        return;
      }
      if (node is! Element) return;

      if (_isHeading(node)) {
        flush();
        current = _SectionBuilder(
          heading: _labelText(node),
          anchor: _headingAnchor(node),
        );
        current.glossary.addAll(_glossaryWithin(node));
        return;
      }

      if (node.localName == 'img') {
        final alt = node.attributes['alt'];
        if (alt != null && alt.trim().isNotEmpty) current.text.write(' $alt ');
      }
      final glossaryTitle = node.attributes['title'];
      if ((node.classes.contains('glossary') || node.localName == 'abbr') &&
          glossaryTitle != null &&
          glossaryTitle.trim().isNotEmpty) {
        final abbreviation = _normaliseText(node.text);
        if (abbreviation.isNotEmpty) {
          current.glossary[abbreviation] = _normaliseText(glossaryTitle);
        }
      }

      final separatesText = _blockElements.contains(node.localName);
      if (separatesText) current.text.write(' ');
      for (final child in node.nodes.toList()) {
        walk(child);
      }
      if (separatesText || node.localName == 'br') current.text.write(' ');
    }

    for (final child in main.nodes.toList()) {
      walk(child);
    }
    flush();
    return output;
  }

  void _removeSearchExcludedContent(Element main) {
    const genericSelectors = [
      'script',
      'style',
      'nav',
      '#title-block-header',
      '.quarto-title-meta',
      '.quarto-page-breadcrumbs',
      '.page-navigation',
      '[hidden]',
      '[aria-hidden="true"]',
      '[data-reader-hidden="true"]',
      '.hidden',
      '.visually-hidden',
      '.screen-reader-only',
    ];
    for (final selector in [...genericSelectors, ..._config.hiddenSelectors]) {
      for (final element in main.querySelectorAll(selector).toList()) {
        element.remove();
      }
    }
  }

  String _headingAnchor(Element heading) {
    if (heading.id.isNotEmpty) return heading.id;
    final dataAnchor = heading.attributes['data-anchor-id'];
    if (dataAnchor != null && dataAnchor.isNotEmpty) return dataAnchor;
    return heading.parent?.id ?? '';
  }

  Map<String, String> _glossaryWithin(Element element) {
    final glossary = <String, String>{};
    final candidates = <Element>[
      if (element.classes.contains('glossary') || element.localName == 'abbr')
        element,
      ...element.querySelectorAll('.glossary[title], abbr[title]'),
    ];
    for (final candidate in candidates) {
      final abbreviation = _normaliseText(candidate.text);
      final expansion = _normaliseText(candidate.attributes['title'] ?? '');
      if (abbreviation.isNotEmpty && expansion.isNotEmpty) {
        glossary[abbreviation] = expansion;
      }
    }
    return glossary;
  }

  bool _isHeading(Element element) {
    return const {
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
    }.contains(element.localName);
  }

  String _labelText(Element element) {
    final clone = element.clone(true);
    for (final number in clone.querySelectorAll('.chapter-number').toList()) {
      number.remove();
    }
    return _normaliseText(clone.text);
  }

  String _normaliseText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Iterable<Element> _directChildren(Element element, String tagName) {
    return element.nodes.whereType<Element>().where(
      (child) => child.localName == tagName,
    );
  }

  void _injectReaderAssets(Document document) {
    final head = document.head;
    final body = document.body;
    if (head == null || body == null) return;

    body.attributes['data-quarto-reader'] = '';
    body.classes.add('qr-sidenotes-visible');

    final link = Element.tag('link')
      ..attributes.addAll({
        'rel': 'stylesheet',
        'href': '/__reader__/reader.css',
        'data-quarto-reader': 'asset',
      });
    head.insertBefore(link, head.firstChild);

    if (_config.hiddenSelectors.isNotEmpty) {
      final style = Element.tag('style')
        ..attributes['data-quarto-reader'] = 'book-hiding'
        ..text =
            '${_config.hiddenSelectors.join(',\n')} {\n'
            '  display: none !important;\n'
            '}\n'
            'body { padding-top: 0 !important; }';
      head.nodes.insert(1, style);
    }

    final script = Element.tag('script')
      ..attributes.addAll({
        'src': '/__reader__/reader.js',
        'defer': '',
        'data-quarto-reader': 'asset',
      });
    head.append(script);
  }
}

class _SectionBuilder {
  _SectionBuilder({required this.heading, required this.anchor});

  final String heading;
  final String anchor;
  final StringBuffer text = StringBuffer();
  final Map<String, String> glossary = {};
}

const _blockElements = {
  'address',
  'article',
  'aside',
  'blockquote',
  'caption',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'header',
  'li',
  'main',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
};
