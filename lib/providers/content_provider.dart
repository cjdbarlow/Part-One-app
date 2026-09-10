import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:isolate';
import '../models/book_content.dart';
import '../models/book_config.dart';
import '../models/download_progress.dart';
import '../services/content_service.dart';
import '../services/local_server.dart';
import '../services/search_service.dart';
import '../services/github_service.dart';

class ContentProvider extends ChangeNotifier {
  final ContentService service;
  final LocalServer server;
  ContentProvider({required this.service, required this.server});
  BookConfig get config => service.config;
  BookContent? content;
  SearchService? search;
  bool isInitialising = true;
  bool isChecking = false;
  bool isDownloading = false;
  String? availableCommit;
  String? error;
  DownloadProgress? progress;
  int revision = 0;
  bool _disposed = false;
  DateTime? _lastCheck;
  Future<void>? _checking;
  bool get hasContent => content != null;
  bool get updateAvailable =>
      hasContent &&
      availableCommit != null &&
      availableCommit != content!.commit;
  Future<void> initialise() async {
    try {
      final installed = await service.loadInstalled();
      if (installed != null) await _useContent(installed);
    } catch (_) {
      error =
          'The saved book could not be opened. Please download the content again.';
    } finally {
      isInitialising = false;
      _notify();
    }
    if (hasContent) unawaited(checkForUpdates());
  }

  Future<void> _useContent(BookContent book) async {
    final sections = book.sections;
    final index = await Isolate.run(() => SearchService(sections));
    server.useDirectory(service.installedDirectory!);
    content = book;
    search = index;
    revision++;
  }

  Future<void> checkForUpdates({bool force = false}) {
    if (_checking != null) return _checking!;
    if (isDownloading ||
        (!force &&
            _lastCheck != null &&
            DateTime.now().difference(_lastCheck!) <
                const Duration(minutes: 5))) {
      return Future.value();
    }
    return _checking = _check().whenComplete(() => _checking = null);
  }

  Future<void> _check() async {
    isChecking = true;
    error = null;
    _lastCheck = DateTime.now();
    _notify();
    try {
      final commit = await service.github.latestCommit(config);
      availableCommit = commit == content?.commit ? null : commit;
      final installed = content;
      if (installed != null && installed.committedAt == null) {
        try {
          final committedAt = await service.github.commitDate(
            config,
            installed.commit,
          );
          final backfilled = await service.backfillCommittedAt(
            installed.commit,
            committedAt,
          );
          if (backfilled != null &&
              content?.commit == installed.commit &&
              content?.committedAt == null) {
            content = backfilled;
          }
        } catch (_) {
          // Optional metadata must not conceal real update availability.
        }
      }
    } catch (exception) {
      error = _message(
        exception,
        'Updates could not be checked. Check your connection and try again.',
      );
    } finally {
      isChecking = false;
      _notify();
    }
  }

  Future<void> downloadContent() async {
    if (isDownloading) return;
    isDownloading = true;
    error = null;
    progress = const DownloadProgress('Preparing download…');
    _notify();
    try {
      if (_checking != null) await _checking;
      final commit =
          availableCommit ?? await service.github.latestCommit(config);
      final installed = await service.install(commit, (value) {
        progress = value;
        _notify();
      });
      await _useContent(installed);
      availableCommit = null;
    } catch (exception) {
      error = _message(
        exception,
        'Content could not be downloaded. Check your connection and available storage, then try again.',
      );
    } finally {
      isDownloading = false;
      progress = null;
      _notify();
    }
  }

  String _message(Object exception, String fallback) =>
      exception is ContentException ? exception.message : fallback;

  void clearError() {
    error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
