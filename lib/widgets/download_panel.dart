import 'package:flutter/cupertino.dart';
import '../models/download_progress.dart';

class DownloadPanel extends StatelessWidget {
  final String title;
  final bool isDownloading;
  final DownloadProgress? progress;
  final String? error;
  final VoidCallback onDownload;
  const DownloadPanel({
    super.key,
    required this.title,
    required this.isDownloading,
    this.progress,
    this.error,
    required this.onDownload,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.book,
              size: 64,
              color: CupertinoTheme.of(context).primaryColor,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: CupertinoTheme.of(
                context,
              ).textTheme.navLargeTitleTextStyle,
            ),
            const SizedBox(height: 12),
            const Text(
              'Download the book to read and search without an internet connection.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (isDownloading) DownloadProgressView(progress: progress),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
                ),
              ),
            CupertinoButton.filled(
              onPressed: isDownloading ? null : onDownload,
              child: Text(
                isDownloading
                    ? 'Downloading…'
                    : error == null
                    ? 'Download content'
                    : 'Try download again',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ContentUpdateFooter extends StatelessWidget {
  final bool updateAvailable;
  final bool isDownloading;
  final bool isChecking;
  final DownloadProgress? progress;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onCheck;
  const ContentUpdateFooter({
    super.key,
    required this.updateAvailable,
    required this.isDownloading,
    required this.isChecking,
    this.progress,
    this.error,
    required this.onDownload,
    required this.onCheck,
  });
  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDownloading)
            DownloadProgressView(progress: progress)
          else if (updateAvailable)
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .08),
                border: Border.all(color: accent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CupertinoButton(
                minimumSize: const Size(44, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                onPressed: onDownload,
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.arrow_down_circle, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Update content', textAlign: TextAlign.left),
                    ),
                  ],
                ),
              ),
            )
          else if (isChecking)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CupertinoActivityIndicator(),
                SizedBox(width: 10),
                Flexible(child: Text('Checking for updates…')),
              ],
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 13,
                ),
              ),
            ),
            if (!updateAvailable && !isDownloading)
              CupertinoButton(
                onPressed: onCheck,
                child: const Text('Try checking again'),
              ),
          ],
        ],
      ),
    );
  }
}

class DownloadProgressView extends StatelessWidget {
  final DownloadProgress? progress;
  const DownloadProgressView({super.key, this.progress});
  @override
  Widget build(BuildContext context) {
    final fraction = progress?.fraction;
    final percent = fraction == null
        ? null
        : '${(fraction.clamp(0, 1) * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 8),
          Text(
            progress?.message ?? 'Preparing download…',
            textAlign: TextAlign.center,
          ),
          if (percent != null) ...[
            const SizedBox(height: 4),
            Text(percent, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
