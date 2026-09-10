import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/book_config.dart';
import 'pages/reader_page.dart';
import 'providers/content_provider.dart';
import 'providers/settings_provider.dart';
import 'services/content_service.dart';
import 'services/github_service.dart';
import 'services/local_server.dart';
import 'services/offline_assets_service.dart';
import 'services/preferences_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReaderBootstrap());
}

class ReaderBootstrap extends StatefulWidget {
  const ReaderBootstrap({super.key});
  @override
  State<ReaderBootstrap> createState() => _ReaderBootstrapState();
}

class _ReaderBootstrapState extends State<ReaderBootstrap> {
  late Future<_ReaderSession> _loading = _initialise();
  _ReaderSession? _session;

  Future<_ReaderSession> _initialise() async {
    final config = BookConfig.fromJson(
      jsonDecode(await rootBundle.loadString('assets/config/app.json'))
          as Map<String, dynamic>,
    );
    final support = await getApplicationSupportDirectory();
    final root = await Directory(
      // Retain the original directory so installed Part One books still open.
      path.join(support.path, 'quarto_reader', config.id),
    ).create(recursive: true);
    final readerAssets = await Directory(
      path.join(root.path, 'reader_assets'),
    ).create(recursive: true);
    for (final name in ['reader.css', 'reader.js']) {
      final bytes = await rootBundle.load('assets/reader/$name');
      await File(path.join(readerAssets.path, name)).writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }
    final empty = await Directory(path.join(root.path, 'empty')).create();
    final server = LocalServer();
    final client = http.Client();
    ContentProvider? content;
    SettingsProvider? settings;
    try {
      await server.start(empty, readerAssets);
      final preferences = await SharedPreferences.getInstance();
      settings = SettingsProvider(PreferencesService(preferences, config.id));
      content = ContentProvider(
        service: ContentService(
          config: config,
          root: root,
          github: GitHubService(client),
          offlineAssets: OfflineAssetsService(client),
        ),
        server: server,
      );
      await content.initialise();
      final session = _ReaderSession(content, settings, client, server);
      if (!mounted) {
        session.dispose();
      } else {
        _session = session;
      }
      return session;
    } catch (_) {
      content?.dispose();
      settings?.dispose();
      client.close();
      await server.close();
      rethrow;
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReaderSession>(
    future: _loading,
    builder: (context, snapshot) {
      final session = snapshot.data;
      if (session != null) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: session.content),
            ChangeNotifierProvider.value(value: session.settings),
          ],
          child: CupertinoApp(
            title: session.content.config.title,
            debugShowCheckedModeBanner: false,
            locale: const Locale('en', 'AU'),
            supportedLocales: const [Locale('en', 'AU')],
            theme: CupertinoThemeData(
              brightness: Brightness.light,
              primaryColor: Color(session.content.config.accentColour),
            ),
            home: const ReaderPage(),
          ),
        );
      }
      return CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(brightness: Brightness.light),
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: Center(
              child: snapshot.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'The reader could not start. Please try again.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          CupertinoButton.filled(
                            onPressed: () =>
                                setState(() => _loading = _initialise()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : const CupertinoActivityIndicator(),
            ),
          ),
        ),
      );
    },
  );
}

class _ReaderSession {
  final ContentProvider content;
  final SettingsProvider settings;
  final http.Client client;
  final LocalServer server;
  _ReaderSession(this.content, this.settings, this.client, this.server);

  void dispose() {
    content.dispose();
    settings.dispose();
    client.close();
    server.close();
  }
}
