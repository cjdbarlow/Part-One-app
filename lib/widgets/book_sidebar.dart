import 'package:flutter/cupertino.dart';
import '../models/book_content.dart';
import '../theme/app_colours.dart';

class BookSidebar extends StatefulWidget {
  final List<ChapterNode> chapters;
  final String currentHref;
  final ValueChanged<String> onNavigate;
  final Widget? footer;
  const BookSidebar({
    super.key,
    required this.chapters,
    required this.currentHref,
    required this.onNavigate,
    this.footer,
  });
  @override
  State<BookSidebar> createState() => _BookSidebarState();
}

class _BookSidebarState extends State<BookSidebar> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _expandCurrent();
  }

  @override
  void didUpdateWidget(covariant BookSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentHref != widget.currentHref ||
        oldWidget.chapters != widget.chapters) {
      _expandCurrent();
    }
  }

  bool _isCurrent(String? href) =>
      href != null &&
      Uri.parse(href).path == Uri.parse(widget.currentHref).path;

  void _expandCurrent() {
    bool visit(List<ChapterNode> nodes, String parent) {
      var containsCurrent = false;
      for (var index = 0; index < nodes.length; index++) {
        final node = nodes[index];
        final key = '$parent/$index';
        final childIsCurrent = visit(node.children, key);
        if (childIsCurrent) _expanded.add(key);
        containsCurrent =
            containsCurrent || childIsCurrent || _isCurrent(node.href);
      }
      return containsCurrent;
    }

    visit(widget.chapters, '');
  }

  List<_VisibleChapter> _visibleChapters() {
    final items = <_VisibleChapter>[];
    void visit(List<ChapterNode> nodes, String parent, int depth) {
      for (var index = 0; index < nodes.length; index++) {
        final node = nodes[index];
        final key = '$parent/$index';
        items.add(_VisibleChapter(node, key, depth));
        if (_expanded.contains(key)) visit(node.children, key, depth + 1);
      }
    }

    visit(widget.chapters, '', 0);
    return items;
  }

  void _toggle(String key) => setState(() {
    if (!_expanded.remove(key)) _expanded.add(key);
  });

  @override
  Widget build(BuildContext context) {
    final items = _visibleChapters();
    return ColoredBox(
      color: CupertinoDynamicColor.resolve(
        AppColours.sidebarBackground,
        context,
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              key: const PageStorageKey('book-chapters'),
              padding: EdgeInsets.only(
                top: 8,
                bottom:
                    8 +
                    (widget.footer == null
                        ? MediaQuery.paddingOf(context).bottom
                        : 0),
              ),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  _chapterRow(context, items[index]),
            ),
          ),
          if (widget.footer case final footer?) ...[
            Container(
              height: .5,
              color: CupertinoDynamicColor.resolve(
                AppColours.separator,
                context,
              ),
            ),
            SafeArea(top: false, child: footer),
          ],
        ],
      ),
    );
  }

  Widget _chapterRow(BuildContext context, _VisibleChapter item) {
    final node = item.node;
    final selected = _isCurrent(node.href);
    final expanded = _expanded.contains(item.key);
    final accent = CupertinoTheme.of(context).primaryColor;
    return Padding(
      padding: EdgeInsets.only(left: 8 + item.depth * 14, right: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: .12) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (node.children.isNotEmpty)
              Semantics(
                label: '${expanded ? 'Collapse' : 'Expand'} ${node.title}',
                expanded: expanded,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => _toggle(item.key),
                  child: Icon(
                    expanded
                        ? CupertinoIcons.chevron_down
                        : CupertinoIcons.chevron_right,
                    size: 14,
                  ),
                ),
              )
            else
              const SizedBox(width: 44),
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                alignment: Alignment.centerLeft,
                onPressed: () => node.href == null
                    ? _toggle(item.key)
                    : widget.onNavigate(node.href!),
                child: Semantics(
                  selected: selected,
                  child: Text(
                    node.title,
                    style: TextStyle(
                      fontSize: 16,
                      color: selected
                          ? accent
                          : CupertinoTheme.of(
                              context,
                            ).textTheme.textStyle.color,
                      fontWeight: selected || node.children.isNotEmpty
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibleChapter {
  final ChapterNode node;
  final String key;
  final int depth;
  const _VisibleChapter(this.node, this.key, this.depth);
}
