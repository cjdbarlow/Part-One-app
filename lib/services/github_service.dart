import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/book_config.dart';
import '../models/download_progress.dart';

class ContentException implements Exception {
  final String message;
  const ContentException(this.message);
  @override
  String toString() => message;
}

class GitHubService {
  final http.Client client;
  GitHubService(this.client);

  Future<String> latestCommit(BookConfig config) async {
    final json = await _commit(config, config.branch);
    final commit = json['sha'];
    if (commit is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(commit)) {
      throw const ContentException(
        'GitHub returned an invalid content version.',
      );
    }
    return commit;
  }

  Future<DateTime> commitDate(BookConfig config, String commit) async {
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(commit)) {
      throw const ContentException('Invalid content version.');
    }
    final json = await _commit(config, commit);
    if (json['sha'] != commit) {
      throw const ContentException(
        'GitHub returned invalid content date metadata.',
      );
    }
    final details = json['commit'];
    final committer = details is Map<String, dynamic>
        ? details['committer']
        : null;
    final value = committer is Map<String, dynamic> ? committer['date'] : null;
    if (value is! String) {
      throw const ContentException(
        'GitHub returned invalid content date metadata.',
      );
    }
    try {
      return DateTime.parse(value).toUtc();
    } on FormatException {
      throw const ContentException(
        'GitHub returned invalid content date metadata.',
      );
    }
  }

  Future<Map<String, dynamic>> _commit(BookConfig config, String ref) async {
    config.validate();
    final uri = Uri(
      scheme: 'https',
      host: 'api.github.com',
      pathSegments: ['repos', config.owner, config.repository, 'commits', ref],
    );
    final response = await client
        .get(
          uri,
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'QuartoReader',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 404) {
      throw ContentException(
        'The published book could not be found on GitHub ($ref). '
        'Please try again after the publisher has made it available.',
      );
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const ContentException(
        'GitHub is limiting requests. Please try again later.',
      );
    }
    if (response.statusCode != 200) {
      throw ContentException(
        'GitHub could not check for updates (${response.statusCode}). Please try again.',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const ContentException(
        'GitHub returned an invalid content version.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ContentException(
        'GitHub returned an invalid content version.',
      );
    }
    return decoded;
  }

  Future<void> downloadSnapshot(
    BookConfig config,
    String commit,
    File target,
    void Function(DownloadProgress) progress,
  ) async {
    config.validate();
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(commit)) {
      throw const ContentException('Invalid content version.');
    }
    final uri = Uri.https(
      'codeload.github.com',
      '/${config.owner}/${config.repository}/zip/$commit',
    );
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'QuartoReader';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ContentException(
        'The content download failed (${response.statusCode}). Please try again.',
      );
    }
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received > 1024 * 1024 * 1024) {
          throw const ContentException('This content download is too large.');
        }
        sink.add(chunk);
        final total = response.contentLength;
        progress(
          DownloadProgress(
            'Downloading content…',
            total != null && total > 0 ? received / total : null,
          ),
        );
      }
      await sink.flush();
      if (response.contentLength != null &&
          received != response.contentLength) {
        throw const ContentException(
          'The content download was interrupted. Please try again.',
        );
      }
    } finally {
      await sink.close();
    }
  }
}
