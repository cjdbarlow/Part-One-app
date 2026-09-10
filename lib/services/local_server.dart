import 'dart:io';
import 'package:path/path.dart' as path;

class LocalServer {
  HttpServer? _server;
  late Directory _contentDirectory;
  late Directory _readerAssets;

  Future<void> start(Directory contentDirectory, Directory readerAssets) async {
    await close();
    _contentDirectory = contentDirectory;
    _readerAssets = readerAssets;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_serve);
  }

  Uri uriFor(String href) {
    final uri = Uri.parse(href);
    if (uri.hasScheme || uri.hasAuthority || !_safePath(uri.path)) {
      throw const FormatException('Not a local book page.');
    }
    return baseUri.resolveUri(uri);
  }

  Uri get baseUri {
    final server = _server;
    if (server == null) throw StateError('The local reader is not running.');
    return Uri(scheme: 'http', host: '127.0.0.1', port: server.port, path: '/');
  }

  void useDirectory(Directory directory) {
    _contentDirectory = directory;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final decoded = Uri.decodeComponent(request.uri.path);
      if (!_safePath(decoded)) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      var relative = decoded.replaceFirst(RegExp(r'^/'), '');
      var root = _contentDirectory;
      if (relative.startsWith('__reader__/')) {
        relative = relative.substring('__reader__/'.length);
        root = _readerAssets;
      }
      if (relative.isEmpty || relative.endsWith('/')) relative += 'index.html';
      final file = File(path.join(root.path, relative));
      if (!await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final realRoot = await root.resolveSymbolicLinks();
      final realFile = await file.resolveSymbolicLinks();
      if (!path.isWithin(realRoot, realFile)) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      response.headers.set(HttpHeaders.contentTypeHeader, _mimeType(relative));
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.contentLength = await file.length();
      if (request.method == 'GET') await response.addStream(file.openRead());
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
    } on FileSystemException {
      response.statusCode = HttpStatus.notFound;
    } on HttpException {
      // The WebView may abandon an asset request when navigating away.
    } finally {
      await response.close();
    }
  }

  static bool _safePath(String value) =>
      !value.contains('\\') &&
      !value.contains('\u0000') &&
      !value.split('/').contains('..');

  static String _mimeType(String file) =>
      switch (path.extension(file).toLowerCase()) {
        '.html' => 'text/html; charset=utf-8',
        '.css' => 'text/css; charset=utf-8',
        '.js' || '.mjs' => 'text/javascript; charset=utf-8',
        '.json' => 'application/json; charset=utf-8',
        '.svg' => 'image/svg+xml',
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp',
        '.gif' => 'image/gif',
        '.ico' => 'image/x-icon',
        '.woff' => 'font/woff',
        '.woff2' => 'font/woff2',
        '.ttf' => 'font/ttf',
        '.otf' => 'font/otf',
        '.pdf' => 'application/pdf',
        '.wasm' => 'application/wasm',
        _ => 'application/octet-stream',
      };

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}
