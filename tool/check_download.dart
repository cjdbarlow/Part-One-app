import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:part_one/models/book_config.dart';
import 'package:part_one/services/content_service.dart';
import 'package:part_one/services/github_service.dart';
import 'package:part_one/services/offline_assets_service.dart';

/// Exercise a real first download in temporary storage without launching a browser.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/check_download.dart CONFIG_JSON');
    exitCode = 64;
    return;
  }
  final config = BookConfig.fromJson(
    jsonDecode(await File(arguments.single).readAsString())
        as Map<String, dynamic>,
  );
  final directory = await Directory.systemTemp.createTemp(
    'quarto-download-check-',
  );
  final client = http.Client();
  try {
    final github = GitHubService(client);
    final commit = await github.latestCommit(config);
    stdout.writeln('${config.title}: $commit');
    final content = ContentService(
      config: config,
      root: directory,
      github: github,
      offlineAssets: OfflineAssetsService(client),
    );
    String? lastMessage;
    final watch = Stopwatch()..start();
    final installed = await content.install(commit, (progress) {
      if (progress.message == lastMessage) return;
      lastMessage = progress.message;
      stdout.writeln(progress.message);
    });
    final restored = await content.loadInstalled();
    if (restored?.commit != commit) {
      throw StateError('Installed version could not be restored.');
    }
    stdout.writeln(
      'All required rendering assets passed installation validation.',
    );
    var size = 0;
    var files = 0;
    await for (final file
        in content.installedDirectory!
            .list(recursive: true)
            .where((file) => file is File)
            .cast<File>()) {
      size += await file.length();
      files++;
    }
    stdout.writeln(
      'Passed: ${installed.pageCount} pages, ${installed.sections.length} search sections, $files offline files, ${(size / (1024 * 1024)).toStringAsFixed(1)} MiB; ${watch.elapsed.inSeconds} seconds.',
    );
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    client.close();
    await directory.delete(recursive: true);
  }
}
