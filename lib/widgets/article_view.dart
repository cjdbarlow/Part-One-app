import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum ArticleNavigationKind { local, localRedirect, external, blocked }

class ArticleNavigation {
  const ArticleNavigation(this.kind, this.uri);

  final ArticleNavigationKind kind;
  final Uri uri;
}

ArticleNavigation resolveArticleNavigation(
  String url, {
  required Uri localOrigin,
  required Uri publishedOrigin,
}) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) {
    return ArticleNavigation(ArticleNavigationKind.blocked, Uri());
  }
  final target = parsed.hasScheme || parsed.hasAuthority
      ? parsed
      : localOrigin.resolveUri(parsed);

  if (_sameOrigin(target, localOrigin)) {
    return ArticleNavigation(ArticleNavigationKind.local, target);
  }
  if (_sameOrigin(target, publishedOrigin)) {
    final basePath = _directoryPath(publishedOrigin.path);
    if (target.path.startsWith(basePath)) {
      final relativePath = target.path.substring(basePath.length);
      final local = localOrigin.resolveUri(
        Uri(
          path: relativePath,
          query: target.hasQuery ? target.query : null,
          fragment: target.hasFragment ? target.fragment : null,
        ),
      );
      return ArticleNavigation(ArticleNavigationKind.localRedirect, local);
    }
  }
  if (const {'http', 'https', 'mailto', 'tel'}.contains(target.scheme)) {
    return ArticleNavigation(ArticleNavigationKind.external, target);
  }
  return ArticleNavigation(ArticleNavigationKind.blocked, target);
}

String? localHrefForUrl(Uri uri, Uri localOrigin) {
  if (!_sameOrigin(uri, localOrigin)) return null;
  final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  return Uri(
    path: path,
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  ).toString();
}

bool _sameOrigin(Uri first, Uri second) =>
    first.scheme == second.scheme &&
    first.host == second.host &&
    first.port == second.port;

String _directoryPath(String path) {
  if (path.isEmpty || path == '/') return '/';
  return path.endsWith('/') ? path : '$path/';
}

class ArticleHighlight {
  const ArticleHighlight({required this.anchor, required this.terms});

  final String anchor;
  final List<String> terms;
}

String articleHighlightScript(ArticleHighlight highlight, {int requestId = 0}) {
  return '(() => {${_highlightStatements(highlight, requestId)}})()';
}

String articleSidenoteScript(bool visible) =>
    'window.quartoReader?.setSidenotesVisible(${jsonEncode(visible)})';

String articlePresentationScript({
  required bool sidenotesVisible,
  ArticleHighlight? highlight,
  int requestId = 0,
}) {
  final highlightStatements = highlight == null
      ? ''
      : _highlightStatements(highlight, requestId);
  return '(() => {'
      '${articleSidenoteScript(sidenotesVisible)};'
      '$highlightStatements'
      '})()';
}

String _highlightStatements(ArticleHighlight highlight, int requestId) {
  final payload = jsonEncode({
    'anchor': highlight.anchor,
    'terms': highlight.terms,
  });
  return 'const highlightRequest = $requestId;'
      'window.__quartoReaderHighlightRequest = highlightRequest;'
      'const targetDocument = document;'
      'const applyHighlight = () => {'
      'if (window.__quartoReaderHighlightRequest !== highlightRequest || '
      'document !== targetDocument) return;'
      'window.quartoReader?.highlight($payload);'
      '};'
      'const mathReady = window.MathJax?.startup?.promise;'
      'if (!mathReady) return applyHighlight();'
      'return Promise.resolve(mathReady).then(applyHighlight, applyHighlight);';
}

abstract interface class ArticleNavigationController {
  Future<bool> goBack();
}

class ArticleViewConfiguration {
  const ArticleViewConfiguration({
    required this.localOrigin,
    required this.publishedOrigin,
    required this.href,
    required this.revision,
    required this.sidenotesVisible,
    required this.onHrefChanged,
    required this.onCanGoBackChanged,
    required this.onControllerReady,
    required this.onNavigationError,
    this.highlight,
  });

  final Uri localOrigin;
  final Uri publishedOrigin;
  final String href;
  final int revision;
  final bool sidenotesVisible;
  final ArticleHighlight? highlight;
  final ValueChanged<String> onHrefChanged;
  final ValueChanged<bool> onCanGoBackChanged;
  final ValueChanged<ArticleNavigationController> onControllerReady;
  final ValueChanged<String> onNavigationError;
}

typedef ArticleBuilder =
    Widget Function(
      BuildContext context,
      ArticleViewConfiguration configuration,
    );

Widget buildArticleView(
  BuildContext context,
  ArticleViewConfiguration configuration,
) => ArticleView(configuration: configuration);

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

class ArticleView extends StatefulWidget {
  const ArticleView({
    super.key,
    required this.configuration,
    this.launchExternal = _launchExternally,
  });

  final ArticleViewConfiguration configuration;
  final ExternalUrlLauncher launchExternal;

  @override
  State<ArticleView> createState() => _ArticleViewState();
}

class _ArticleViewState extends State<ArticleView>
    implements ArticleNavigationController {
  late final WebViewController _controller;
  int _pageGeneration = 0;
  int _bridgeRequest = 0;
  String? _finishedHref;
  String? _reportedHref;
  bool _ready = false;

  ArticleViewConfiguration get configuration => widget.configuration;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_initialise());
  }

  Future<void> _initialise() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(CupertinoColors.white);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
        onPageStarted: (_) {
          _pageGeneration++;
          _finishedHref = null;
        },
        onPageFinished: _onPageFinished,
        onUrlChange: _onUrlChange,
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) {
            configuration.onNavigationError(
              'This page could not be opened. Please try again.',
            );
          }
        },
      ),
    );
    if (!mounted) return;
    _ready = true;
    configuration.onControllerReady(this);
    await _load(configuration.href);
  }

  @override
  void didUpdateWidget(covariant ArticleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready) return;
    final old = oldWidget.configuration;
    if (old.href != configuration.href ||
        old.revision != configuration.revision) {
      if (old.revision == configuration.revision &&
          _reportedHref == configuration.href) {
        _reportedHref = null;
        return;
      }
      unawaited(_load(configuration.href));
      return;
    }
    if (old.sidenotesVisible != configuration.sidenotesVisible) {
      unawaited(
        _applyPresentation(
          generation: _pageGeneration,
          requestId: ++_bridgeRequest,
        ),
      );
      return;
    }
    if (!identical(old.highlight, configuration.highlight) &&
        configuration.highlight != null) {
      unawaited(
        _applyHighlight(
          configuration.highlight!,
          generation: _pageGeneration,
          requestId: ++_bridgeRequest,
        ),
      );
    }
  }

  Future<void> _load(String href) async {
    _finishedHref = null;
    await _controller.loadRequest(configuration.localOrigin.resolve(href));
  }

  Future<NavigationDecision> _onNavigationRequest(
    NavigationRequest request,
  ) async {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final navigation = resolveArticleNavigation(
      request.url,
      localOrigin: configuration.localOrigin,
      publishedOrigin: configuration.publishedOrigin,
    );
    switch (navigation.kind) {
      case ArticleNavigationKind.local:
        return NavigationDecision.navigate;
      case ArticleNavigationKind.localRedirect:
        await _controller.loadRequest(navigation.uri);
        return NavigationDecision.prevent;
      case ArticleNavigationKind.external:
        try {
          final launched = await widget.launchExternal(navigation.uri);
          if (!launched) _showExternalNavigationError();
        } catch (_) {
          _showExternalNavigationError();
        }
        return NavigationDecision.prevent;
      case ArticleNavigationKind.blocked:
        configuration.onNavigationError('This link cannot be opened.');
        return NavigationDecision.prevent;
    }
  }

  void _showExternalNavigationError() =>
      configuration.onNavigationError('The external link could not be opened.');

  void _onUrlChange(UrlChange change) {
    final value = change.url;
    if (value == null) return;
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    final href = localHrefForUrl(uri, configuration.localOrigin);
    if (href != null) {
      _reportedHref = href == configuration.href ? null : href;
      configuration.onHrefChanged(href);
    }
    unawaited(_controller.canGoBack().then(configuration.onCanGoBackChanged));
  }

  Future<void> _onPageFinished(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final href = localHrefForUrl(uri, configuration.localOrigin);
    if (href == null || !_samePage(href, configuration.href)) return;
    final generation = _pageGeneration;
    _finishedHref = href;
    await _applyPresentation(
      generation: generation,
      requestId: ++_bridgeRequest,
    );
  }

  bool _samePage(String first, String second) =>
      Uri.parse(first).path == Uri.parse(second).path;

  Future<void> _applyPresentation({
    required int generation,
    required int requestId,
  }) async {
    if (_finishedHref == null ||
        !_samePage(_finishedHref!, configuration.href) ||
        generation != _pageGeneration) {
      return;
    }
    await _controller.runJavaScript(
      articlePresentationScript(
        sidenotesVisible: configuration.sidenotesVisible,
        highlight: configuration.highlight,
        requestId: requestId,
      ),
    );
  }

  Future<void> _applyHighlight(
    ArticleHighlight highlight, {
    required int requestId,
    required int generation,
  }) async {
    if (_finishedHref == null ||
        !_samePage(_finishedHref!, configuration.href) ||
        generation != _pageGeneration) {
      return;
    }
    await _controller.runJavaScript(
      articleHighlightScript(highlight, requestId: requestId),
    );
  }

  @override
  Future<bool> goBack() async {
    if (!await _controller.canGoBack()) return false;
    await _controller.goBack();
    return true;
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
