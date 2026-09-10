import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/book_content.dart';
import '../models/search_result.dart';
import '../providers/content_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_colours.dart';
import '../widgets/article_view.dart';
import '../widgets/book_sidebar.dart';
import '../widgets/download_panel.dart';
import 'search_page.dart';
import 'settings_page.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, this.articleBuilder = buildArticleView});

  final ArticleBuilder articleBuilder;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  static const _tabletWidth = 760.0;
  BookContent? _seenContent;
  int? _seenRevision;
  String? _currentHref;
  ArticleHighlight? _highlight;
  ArticleNavigationController? _articleController;
  bool _canGoBack = false;
  String? _navigationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<ContentProvider>().checkForUpdates());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final content = context.watch<ContentProvider>();
    final book = content.content;
    if (identical(book, _seenContent) && content.revision == _seenRevision) {
      return;
    }
    final revisionChanged =
        _seenRevision != null && content.revision != _seenRevision;
    final previousHref = _currentHref;
    _seenContent = book;
    _seenRevision = content.revision;
    if (revisionChanged) {
      _articleController = null;
      _canGoBack = false;
    }
    if (book == null) {
      _currentHref = null;
      _highlight = null;
      _articleController = null;
      _canGoBack = false;
      return;
    }

    final settings = context.read<SettingsProvider>();
    final preferred = previousHref ?? settings.lastHref;
    _currentHref = _existingHref(content, preferred) ?? book.entryPage;
    if (previousHref != null && _currentHref != previousHref) {
      _highlight = null;
    }
    unawaited(settings.setLastHref(_currentHref!));
  }

  String? _existingHref(ContentProvider content, String? href) {
    final directory = content.service.installedDirectory;
    if (directory == null || href == null || href.isEmpty) return null;
    try {
      final uri = Uri.parse(href);
      final decoded = Uri.decodeComponent(uri.path);
      if (uri.hasScheme ||
          uri.hasAuthority ||
          decoded.startsWith('/') ||
          decoded.contains('\\') ||
          decoded.split('/').contains('..') ||
          content.config.isPageExcluded(decoded)) {
        return null;
      }
      return File(path.join(directory.path, decoded)).existsSync()
          ? href
          : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentProvider>();
    final settings = context.watch<SettingsProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= _tabletWidth;

    return PopScope<void>(
      canPop: !(_canGoBack || (!isTablet && settings.sidebarVisible)),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!isTablet && settings.sidebarVisible) {
          unawaited(settings.setSidebarVisible(false));
        } else {
          unawaited(_goBack());
        }
      },
      child: CupertinoPageScaffold(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (content.hasContent)
                _ReaderToolbar(
                  title: _currentTitle(content),
                  canGoBack: _canGoBack,
                  sidebarVisible: settings.sidebarVisible,
                  sidenotesVisible: settings.sidenotesVisible,
                  onBack: _goBack,
                  onToggleSidebar: () => unawaited(
                    settings.setSidebarVisible(!settings.sidebarVisible),
                  ),
                  onSearch: content.search == null ? null : _openSearch,
                  onToggleSidenotes: () => unawaited(
                    settings.setSidenotesVisible(!settings.sidenotesVisible),
                  ),
                  onSettings: _openSettings,
                ),
              Expanded(child: _body(content, settings, isTablet)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    ContentProvider content,
    SettingsProvider settings,
    bool isTablet,
  ) {
    if (content.isInitialising) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (!content.hasContent) {
      return SafeArea(
        top: false,
        child: DownloadPanel(
          title: content.config.title,
          isDownloading: content.isDownloading,
          progress: content.progress,
          error: content.error,
          onDownload: content.downloadContent,
        ),
      );
    }

    final article = _article(content, settings);
    final readingArea = ColoredBox(
      color: CupertinoColors.white,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_navigationError case final error?)
              _NavigationErrorBanner(
                message: error,
                onDismiss: () => setState(() => _navigationError = null),
              ),
            Expanded(child: article),
          ],
        ),
      ),
    );
    final sidebar = _sidebar(content);
    return Stack(
      children: [
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          left: isTablet && settings.sidebarVisible ? 320 : 0,
          child: readingArea,
        ),
        if (isTablet && settings.sidebarVisible)
          Positioned(top: 0, bottom: 0, left: 0, width: 320, child: sidebar),
        if (!isTablet && settings.sidebarVisible) ...[
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('sidebar-scrim'),
              onTap: () => unawaited(settings.setSidebarVisible(false)),
              child: const ColoredBox(color: Color(0x33000000)),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: .86,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: sidebar,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _article(ContentProvider content, SettingsProvider settings) {
    final revision = content.revision;
    bool revisionIsActive() => mounted && _seenRevision == revision;
    return KeyedSubtree(
      key: ValueKey(revision),
      child: widget.articleBuilder(
        context,
        ArticleViewConfiguration(
          localOrigin: content.server.baseUri,
          publishedOrigin: content.config.siteUrl,
          href: _currentHref ?? content.content!.entryPage,
          revision: revision,
          sidenotesVisible: settings.sidenotesVisible,
          highlight: _highlight,
          onHrefChanged: (href) {
            if (revisionIsActive()) _articleHrefChanged(href);
          },
          onCanGoBackChanged: (value) {
            if (revisionIsActive() && value != _canGoBack) {
              setState(() => _canGoBack = value);
            }
          },
          onControllerReady: (controller) {
            if (revisionIsActive()) _articleController = controller;
          },
          onNavigationError: (message) {
            if (revisionIsActive()) {
              setState(() => _navigationError = message);
            }
          },
        ),
      ),
    );
  }

  Widget _sidebar(ContentProvider content) => BookSidebar(
    chapters: content.content!.chapters,
    currentHref: _currentHref ?? content.content!.entryPage,
    onNavigate: (href) => _navigate(href),
    footer:
        content.updateAvailable ||
            content.isDownloading ||
            content.isChecking ||
            content.error != null
        ? ContentUpdateFooter(
            updateAvailable: content.updateAvailable,
            isDownloading: content.isDownloading,
            isChecking: content.isChecking,
            progress: content.progress,
            error: content.error,
            onDownload: content.downloadContent,
            onCheck: () => content.checkForUpdates(force: true),
          )
        : null,
  );

  String _currentTitle(ContentProvider content) {
    final currentPath = Uri.parse(
      _currentHref ?? content.content!.entryPage,
    ).path;
    String? findTitle(List<ChapterNode> nodes) {
      for (final node in nodes) {
        if (node.href != null && Uri.parse(node.href!).path == currentPath) {
          return node.title;
        }
        final childTitle = findTitle(node.children);
        if (childTitle != null) return childTitle;
      }
      return null;
    }

    return findTitle(content.content!.chapters) ?? content.config.title;
  }

  void _articleHrefChanged(String href) {
    if (!mounted || href == _currentHref) return;
    final highlightPath = _highlight == null
        ? null
        : Uri.parse(_currentHref ?? '').path;
    setState(() {
      _currentHref = href;
      if (highlightPath != Uri.parse(href).path) _highlight = null;
      _navigationError = null;
    });
    unawaited(context.read<SettingsProvider>().setLastHref(href));
  }

  void _navigate(String href, {ArticleHighlight? highlight}) {
    setState(() {
      _currentHref = href;
      _highlight = highlight;
      _navigationError = null;
    });
    final settings = context.read<SettingsProvider>();
    unawaited(settings.setLastHref(href));
    if (MediaQuery.sizeOf(context).width < _tabletWidth &&
        settings.sidebarVisible) {
      unawaited(settings.setSidebarVisible(false));
    }
  }

  Future<void> _goBack() async {
    final handled = await _articleController?.goBack() ?? false;
    if (!handled && mounted && _canGoBack) {
      setState(() => _canGoBack = false);
    }
  }

  Future<void> _openSearch() async {
    final result = await Navigator.of(context).push<SearchResult>(
      CupertinoPageRoute(
        builder: (_) => Consumer<ContentProvider>(
          builder: (context, content, child) =>
              SearchPage(search: content.search!),
        ),
      ),
    );
    if (!mounted || result == null) return;
    _navigate(
      result.section.href,
      highlight: ArticleHighlight(
        anchor: result.section.anchor,
        terms: result.matchedTerms,
      ),
    );
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push<void>(CupertinoPageRoute(builder: (_) => const SettingsPage()));
  }
}

class _ReaderToolbar extends StatelessWidget {
  const _ReaderToolbar({
    required this.title,
    required this.canGoBack,
    required this.sidebarVisible,
    required this.sidenotesVisible,
    required this.onBack,
    required this.onToggleSidebar,
    required this.onSearch,
    required this.onToggleSidenotes,
    required this.onSettings,
  });

  final String title;
  final bool canGoBack;
  final bool sidebarVisible;
  final bool sidenotesVisible;
  final VoidCallback onBack;
  final VoidCallback onToggleSidebar;
  final VoidCallback? onSearch;
  final VoidCallback onToggleSidenotes;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: CupertinoTheme.of(context).barBackgroundColor,
      border: Border(
        bottom: BorderSide(
          width: .5,
          color: CupertinoDynamicColor.resolve(AppColours.separator, context),
        ),
      ),
    ),
    child: SizedBox(
      height: 52,
      child: Row(
        children: [
          if (canGoBack)
            _ToolbarButton(
              label: 'Back in article',
              icon: CupertinoIcons.back,
              onPressed: onBack,
            ),
          _ToolbarButton(
            label: sidebarVisible ? 'Hide sidebar' : 'Show sidebar',
            icon: CupertinoIcons.sidebar_left,
            onPressed: onToggleSidebar,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _ToolbarButton(
            label: 'Search book',
            icon: CupertinoIcons.search,
            onPressed: onSearch,
          ),
          _ToolbarButton(
            label: sidenotesVisible
                ? 'Hide margin content'
                : 'Show margin content',
            icon: CupertinoIcons.text_badge_minus,
            onPressed: onToggleSidenotes,
          ),
          _ToolbarButton(
            label: 'Open settings',
            icon: CupertinoIcons.settings,
            onPressed: onSettings,
          ),
        ],
      ),
    ),
  );
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Icon(icon, size: 21, semanticLabel: null),
    ),
  );
}

class _NavigationErrorBanner extends StatelessWidget {
  const _NavigationErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      color: CupertinoColors.systemYellow.withValues(alpha: .18),
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Expanded(child: Text(message, maxLines: 2)),
          CupertinoButton(
            padding: const EdgeInsets.all(12),
            onPressed: onDismiss,
            child: const Icon(
              CupertinoIcons.xmark,
              size: 18,
              semanticLabel: 'Dismiss message',
            ),
          ),
        ],
      ),
    ),
  );
}
