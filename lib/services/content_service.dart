import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import '../models/book_config.dart';
import '../models/book_content.dart';
import '../models/download_progress.dart';
import 'github_service.dart';
import 'offline_assets_service.dart';
import 'html_importer.dart';
import 'snapshot_archive.dart';

class ContentService {
  final BookConfig config;
  final Directory root;
  final GitHubService github;
  final OfflineAssetsService offlineAssets;
  ContentService({
    required this.config,
    required this.root,
    required this.github,
    required this.offlineAssets,
  });
  Directory? _installedDirectory;
  bool _installing = false;
  Directory? get installedDirectory => _installedDirectory;

  Future<BookContent?> loadInstalled() async {
    config.validate();
    try {
      final pointer =
          jsonDecode(
                await File(path.join(root.path, 'current.json')).readAsString(),
              )
              as Map<String, dynamic>;
      final snapshot = pointer['snapshot'] as String;
      if (!RegExp(r'^[a-f0-9]{40}-[0-9]+$').hasMatch(snapshot)) return null;
      final directory = Directory(path.join(root.path, 'snapshots', snapshot));
      final json =
          jsonDecode(
                await File(
                  path.join(directory.path, 'book.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      if (json['schemaVersion'] != 1) return null;
      final book = BookContent.fromJson(json);
      if (book.commit != snapshot.substring(0, 40) ||
          book.entryPage != config.entryPage) {
        return null;
      }
      final site = Directory(path.join(directory.path, 'site'));
      if (!await File(path.join(site.path, config.entryPage)).exists()) {
        return null;
      }
      _installedDirectory = site;
      return _excludePages(book);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<BookContent> install(
    String commit,
    void Function(DownloadProgress) progress,
  ) async {
    config.validate();
    if (_installing) {
      throw const ContentException('A content download is already running.');
    }
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(commit)) {
      throw const ContentException('Invalid content version.');
    }
    _installing = true;
    Directory? staging;
    try {
      await root.create(recursive: true);
      if (_installedDirectory == null) await loadInstalled();
      final previousSnapshot = _installedDirectory?.parent.path;
      DateTime? committedAt;
      try {
        committedAt = await github.commitDate(config, commit);
      } catch (_) {
        // Date metadata is optional and must not prevent offline content use.
      }
      staging = await root.createTemp('staging-');
      final archive = File(path.join(staging.path, 'download.zip'));
      await github.downloadSnapshot(config, commit, archive, progress);
      progress(const DownloadProgress('Unpacking content…'));
      final site = await Directory(path.join(staging.path, 'site')).create();
      final archivePath = archive.path;
      final sitePath = site.path;
      final contentPath = config.contentPath;
      await Isolate.run(
        () => extractSnapshot(archivePath, sitePath, contentPath),
      );
      await archive.delete();
      progress(const DownloadProgress('Preparing pages and search…'));
      final bookConfig = config;
      final book = await Isolate.run(
        () =>
            prepareBook(sitePath, bookConfig, commit, committedAt: committedAt),
      );
      await offlineAssets.prepare(
        site,
        progress,
        requiredHtmlPaths: _pagePaths(book),
      );
      await File(
        path.join(staging.path, 'book.json'),
      ).writeAsString(jsonEncode(book.toJson()), flush: true);
      final snapshotName = '$commit-${DateTime.now().microsecondsSinceEpoch}';
      final snapshots = await Directory(
        path.join(root.path, 'snapshots'),
      ).create(recursive: true);
      final completed = await staging.rename(
        path.join(snapshots.path, snapshotName),
      );
      staging = null;
      final nextPointer = File(path.join(root.path, 'current.next.json'));
      await nextPointer.writeAsString(
        jsonEncode({'snapshot': snapshotName}),
        flush: true,
      );
      // Both files are on the same filesystem: the old pointer survives until rename.
      await nextPointer.rename(path.join(root.path, 'current.json'));
      _installedDirectory = Directory(path.join(completed.path, 'site'));
      await _pruneSnapshots(snapshots, {completed.path, ?previousSnapshot});
      progress(const DownloadProgress('Content ready', 1));
      return _excludePages(book);
    } on ContentException {
      rethrow;
    } on FormatException {
      throw const ContentException(
        'The published content is not a supported rendered Quarto book.',
      );
    } on FileSystemException {
      throw const ContentException(
        'The content could not be saved. Check available storage and try again.',
      );
    } finally {
      _installing = false;
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<BookContent?> backfillCommittedAt(
    String commit,
    DateTime committedAt,
  ) async {
    config.validate();
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(commit)) return null;
    File? replacement;
    try {
      final pointerFile = File(path.join(root.path, 'current.json'));
      final pointer = jsonDecode(await pointerFile.readAsString());
      if (pointer is! Map<String, dynamic>) return null;
      final snapshot = pointer['snapshot'];
      if (snapshot is! String ||
          !RegExp(r'^[a-f0-9]{40}-[0-9]+$').hasMatch(snapshot) ||
          !snapshot.startsWith(commit)) {
        return null;
      }
      final directory = Directory(path.join(root.path, 'snapshots', snapshot));
      final metadataFile = File(path.join(directory.path, 'book.json'));
      final json = jsonDecode(await metadataFile.readAsString());
      if (json is! Map<String, dynamic> || json['schemaVersion'] != 1) {
        return null;
      }
      final current = BookContent.fromJson(json);
      if (current.commit != commit || current.committedAt != null) return null;
      final updated = BookContent(
        commit: current.commit,
        installedAt: current.installedAt,
        committedAt: committedAt.toUtc(),
        entryPage: current.entryPage,
        chapters: current.chapters,
        sections: current.sections,
        pageCount: current.pageCount,
      );
      replacement = File(path.join(directory.path, 'book.next.json'));
      await replacement.writeAsString(
        jsonEncode(updated.toJson()),
        flush: true,
      );
      final activePointer = jsonDecode(await pointerFile.readAsString());
      if (activePointer is! Map<String, dynamic> ||
          activePointer['snapshot'] != snapshot) {
        await replacement.delete();
        replacement = null;
        return null;
      }
      await replacement.rename(metadataFile.path);
      replacement = null;
      return _excludePages(updated);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } finally {
      if (replacement != null && await replacement.exists()) {
        await replacement.delete();
      }
    }
  }

  BookContent _excludePages(BookContent book) {
    if (config.excludedPages.isEmpty) return book;
    List<ChapterNode> filterChapters(List<ChapterNode> nodes) {
      final visible = <ChapterNode>[];
      for (final node in nodes) {
        final children = filterChapters(node.children);
        final href = node.href;
        if (href != null &&
            config.isPageExcluded(Uri.decodeComponent(Uri.parse(href).path))) {
          visible.addAll(children);
        } else if (href != null ||
            node.children.isEmpty ||
            children.isNotEmpty) {
          visible.add(
            ChapterNode(title: node.title, href: href, children: children),
          );
        }
      }
      return visible;
    }

    // Keep the full snapshot metadata on disk so config changes also work offline.
    return BookContent(
      commit: book.commit,
      installedAt: book.installedAt,
      committedAt: book.committedAt,
      entryPage: book.entryPage,
      chapters: filterChapters(book.chapters),
      sections: book.sections
          .where((section) => !config.isPageExcluded(section.pagePath))
          .toList(),
      pageCount:
          book.pageCount - _pagePaths(book).where(config.isPageExcluded).length,
    );
  }

  Future<void> _pruneSnapshots(
    Directory snapshots,
    Set<String> retained,
  ) async {
    try {
      await for (final entry in snapshots.list(followLinks: false)) {
        if (entry is Directory &&
            !retained.contains(entry.path) &&
            RegExp(
              r'^[a-f0-9]{40}-[0-9]+$',
            ).hasMatch(path.basename(entry.path))) {
          await entry.delete(recursive: true);
        }
      }
    } on FileSystemException {
      // Cleanup failure must not turn an already activated update into an error.
    }
  }
}

/// Used by installation and the read-only book validation tool on a temporary copy.
BookContent prepareBook(
  String directory,
  BookConfig config,
  String commit, {
  DateTime? committedAt,
}) {
  final root = Directory(directory);
  final entry = File(path.join(directory, config.entryPage));
  if (!entry.existsSync()) {
    throw const ContentException(
      'This GitHub branch contains no rendered book. Publish the HTML before downloading.',
    );
  }
  final importer = HtmlImporter(config);
  final first = importer.importPage(entry.readAsStringSync(), config.entryPage);
  if (first.chapters.isEmpty) {
    throw const ContentException(
      'The published book has no supported Quarto chapter navigation.',
    );
  }
  final pagePaths = <String>{config.entryPage};
  void collectChapterPaths(List<ChapterNode> nodes) {
    for (final node in nodes) {
      if (node.href != null) {
        final uri = Uri.parse(node.href!);
        final target = Uri.decodeComponent(uri.path);
        if (uri.hasScheme ||
            uri.hasAuthority ||
            target.startsWith('/') ||
            target.contains('\\') ||
            target.split('/').contains('..') ||
            !File(path.join(directory, target)).existsSync()) {
          throw ContentException(
            'A chapter is missing from the published book: ${node.title}.',
          );
        }
        pagePaths.add(target);
      }
      collectChapterPaths(node.children);
    }
  }

  collectChapterPaths(first.chapters);
  final sections = <SearchSection>[];
  var pageCount = 0;
  for (final file
      in root.listSync(recursive: true, followLinks: false).whereType<File>()) {
    final extension = path.extension(file.path).toLowerCase();
    if (extension != '.html' && extension != '.css') continue;
    final relative = path
        .relative(file.path, from: directory)
        .split(path.separator)
        .join('/');
    if (extension == '.css') {
      file.writeAsStringSync(
        importer.normaliseStylesheet(file.readAsStringSync()),
      );
      continue;
    }
    if (relative.startsWith('site_libs/')) continue;
    final source = file.readAsStringSync();
    ImportedPage page;
    try {
      page = relative == config.entryPage
          ? first
          : importer.importPage(source, relative);
    } on FormatException {
      if (pagePaths.contains(relative)) rethrow;
      continue; // Dependency documentation can also use the .html extension.
    }
    file.writeAsStringSync(page.html);
    if (pagePaths.contains(relative)) {
      sections.addAll(page.sections);
      pageCount++;
    }
  }
  return BookContent(
    commit: commit,
    installedAt: DateTime.now().toUtc(),
    committedAt: committedAt,
    entryPage: config.entryPage,
    chapters: first.chapters,
    sections: sections,
    pageCount: pageCount,
  );
}

Set<String> _pagePaths(BookContent book) {
  final pages = <String>{book.entryPage};
  void collect(List<ChapterNode> nodes) {
    for (final node in nodes) {
      final href = node.href;
      if (href != null) pages.add(Uri.decodeComponent(Uri.parse(href).path));
      collect(node.children);
    }
  }

  collect(book.chapters);
  return pages;
}
