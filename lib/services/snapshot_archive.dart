import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'github_service.dart';

/// Extract only regular files below a GitHub archive's single top-level folder.
void extractSnapshot(
  String archivePath,
  String outputPath,
  String contentPath,
) {
  final input = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    String? topLevel;
    var totalSize = 0;
    var count = 0;
    for (final entry in archive) {
      final name = entry.name;
      if (name.startsWith('/') ||
          name.contains('\\') ||
          name.contains('\u0000') ||
          name.split('/').contains('..') ||
          entry.isSymbolicLink) {
        throw const ContentException(
          'The downloaded archive contains an unsafe file path.',
        );
      }
      final parts = name.split('/');
      topLevel ??= parts.first;
      if (parts.first != topLevel) {
        throw const ContentException(
          'The downloaded archive has an unexpected structure.',
        );
      }
      var relative = parts.skip(1).join('/');
      if (contentPath.isNotEmpty) {
        if (!relative.startsWith('$contentPath/')) continue;
        relative = relative.substring(contentPath.length + 1);
      }
      if (!entry.isFile || relative.isEmpty) continue;
      totalSize += entry.size;
      if (++count > 50000 || totalSize > 2 * 1024 * 1024 * 1024) {
        throw const ContentException(
          'The expanded content exceeds the supported book size.',
        );
      }
      final destination = path.normalize(path.join(outputPath, relative));
      if (!path.isWithin(outputPath, destination)) {
        throw const ContentException(
          'The downloaded archive contains an unsafe file path.',
        );
      }
      Directory(path.dirname(destination)).createSync(recursive: true);
      final output = OutputFileStream(destination);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
  } finally {
    input.closeSync();
  }
}
