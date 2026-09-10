import 'package:flutter/cupertino.dart';
import 'dart:async';
import '../services/search_service.dart';
import '../models/search_result.dart';
import '../theme/app_colours.dart';

class SearchPage extends StatefulWidget {
  final SearchService search;
  const SearchPage({super.key, required this.search});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  String _query = '';

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _search(query));
  }

  void _search(String query) {
    if (!mounted) return;
    setState(() {
      _query = query.trim();
      _results = widget.search.search(_query);
    });
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) {
      _debounce?.cancel();
      _results = widget.search.search(_query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('Search')),
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: CupertinoSearchTextField(
              controller: _controller,
              autofocus: true,
              placeholder: 'Search all content',
              onChanged: _onChanged,
              onSubmitted: (query) {
                _debounce?.cancel();
                _search(query);
              },
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _query.isEmpty
                            ? 'Search titles, headings and the full text.'
                            : 'No results',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: CupertinoDynamicColor.resolve(
                            AppColours.secondaryText,
                            context,
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _results.length,
                    separatorBuilder: (context, index) => Container(
                      height: .5,
                      color: CupertinoDynamicColor.resolve(
                        AppColours.separator,
                        context,
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      final section = result.section;
                      return CupertinoButton(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        onPressed: () => Navigator.of(context).pop(result),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section.pageTitle,
                              style: TextStyle(
                                fontSize: 17,
                                color: CupertinoTheme.of(
                                  context,
                                ).textTheme.textStyle.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (section.heading != section.pageTitle) ...[
                              const SizedBox(height: 4),
                              Text(
                                section.heading,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              result.snippet,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: CupertinoDynamicColor.resolve(
                                  AppColours.secondaryText,
                                  context,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
