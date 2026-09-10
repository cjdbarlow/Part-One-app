import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/content_provider.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final content = context.watch<ContentProvider>();
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
              header: const Text('READING'),
              children: [
                CupertinoListTile(
                  title: const Text('Show sidebar'),
                  trailing: CupertinoSwitch(
                    value: settings.sidebarVisible,
                    onChanged: settings.setSidebarVisible,
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('CONTENT'),
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
