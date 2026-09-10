import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:part_one/models/book_config.dart';
import 'package:part_one/models/book_content.dart';
import 'package:part_one/services/html_importer.dart';
import 'package:part_one/services/search_service.dart';

/// Parse the existing published output without modifying it or fetching assets.
void main(List<String> arguments) {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/check_local_book.dart CONFIG_JSON BOOK_DIRECTORY [SEARCH TERMS]',
    );
    exitCode = 64;
    return;
  }
  final config = BookConfig.fromJson(
    jsonDecode(File(arguments[0]).readAsStringSync()) as Map<String, dynamic>,
  );
  final directory = Directory(arguments[1]).absolute;
  final importer = HtmlImporter(config);
  final sections = <SearchSection>[];
  final pages = <String>{};
  final watch = Stopwatch()..start();
  final entry = importer.importPage(
    File(path.join(directory.path, config.entryPage)).readAsStringSync(),
    config.entryPage,
  );
  final chapters = entry.chapters;
  final inventory = <String>{config.entryPage};
  var chapterCount = 0;
  void collectChapters(List<ChapterNode> nodes) {
    for (final node in nodes) {
      if (node.href != null) {
        chapterCount++;
        inventory.add(Uri.decodeComponent(Uri.parse(node.href!).path));
      }
      collectChapters(node.children);
    }
  }

  collectChapters(chapters);
  final missing = <String>[];
  for (final relative in inventory) {
    final file = File(path.normalize(path.join(directory.path, relative)));
    if (!path.isWithin(directory.path, file.path) || !file.existsSync()) {
      missing.add(relative);
      continue;
    }
    try {
      final imported = relative == config.entryPage
          ? entry
          : importer.importPage(file.readAsStringSync(), relative);
      pages.add(relative);
      sections.addAll(imported.sections);
    } on FormatException {
      missing.add(relative);
    }
  }
  stdout.writeln(
    '${config.title}: ${pages.length} listed article pages, ${sections.length} sections, $chapterCount chapter links; import ${watch.elapsedMilliseconds} ms.',
  );
  if (missing.isNotEmpty || pages.isEmpty || chapters.isEmpty) {
    stderr.writeln('Invalid or missing chapter targets: $missing');
    exitCode = 1;
  }
  watch.reset();
  final search = SearchService(sections);
  stdout.writeln('Search index: ${watch.elapsedMilliseconds} ms.');
  final queries = arguments.length > 2
      ? arguments.skip(2)
      : [
          'propofol metabolism',
          'propof',
          'propofal',
          'GFR',
          'glomerular filtration rate',
        ];
  for (final query in queries) {
    watch.reset();
    final results = search.search(query, limit: 3);
    stdout.writeln('"$query": ${watch.elapsedMilliseconds} ms');
    for (final result in results) {
      stdout.writeln(
        '  ${result.section.href} — ${result.section.pageTitle} / ${result.section.heading}',
      );
      stdout.writeln('  ${result.snippet}');
    }
  }
}
