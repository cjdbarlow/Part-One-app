import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/content_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _disclaimerLink = TapGestureRecognizer();

  @override
  void dispose() {
    _disclaimerLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentProvider>();
    final disclaimer = content.config.disclaimer;
    _disclaimerLink.onTap = disclaimer == null
        ? null
        : () => launchUrl(disclaimer.url);
    final installed = content.content;
    final contentMessage =
        content.error ??
        (content.updateAvailable
            ? 'An update is available. Use the button at the bottom of the sidebar to download it.'
            : installed == null
            ? 'The book has not been downloaded yet.'
            : null);
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('Content'),
              footer: contentMessage == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        contentMessage,
                        style: content.error == null
                            ? null
                            : const TextStyle(color: CupertinoColors.systemRed),
                      ),
                    ),
              children: [
                if (installed != null) ...[
                  CupertinoListTile(
                    title: const Text('Last updated'),
                    subtitle: Text(
                      installed.committedAt == null
                          ? 'Not available'
                          : _dateTime(installed.committedAt!),
                      maxLines: 2,
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('Downloaded'),
                    subtitle: Text(_date(installed.installedAt), maxLines: 2),
                  ),
                  CupertinoListTile(
                    title: const Text('Content version'),
                    subtitle: Text(
                      installed.commit.substring(0, 7),
                      maxLines: 2,
                    ),
                  ),
                ],
                CupertinoListTile(
                  title: Text(
                    'Check for updates',
                    style: TextStyle(
                      color: CupertinoTheme.of(context).primaryColor,
                    ),
                  ),
                  trailing: content.isChecking
                      ? const CupertinoActivityIndicator()
                      : null,
                  onTap: content.isChecking || content.isDownloading
                      ? null
                      : () => content.checkForUpdates(force: true),
                ),
              ],
            ),
            if (disclaimer != null)
              CupertinoListSection.insetGrouped(
                header: const Text('Disclaimer'),
                footer: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${disclaimer.text} '),
                      TextSpan(
                        text: disclaimer.linkText,
                        style: TextStyle(
                          color: CupertinoColors.activeBlue.resolveFrom(
                            context,
                          ),
                        ),
                        recognizer: _disclaimerLink,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                children: [],
              ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _dateTime(DateTime value) {
    final date = value.toLocal();
    return '${_date(date)}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
