import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/book_config.dart';

Future<void> configureApp({required Directory projectRoot}) async {
  final configFile = File(
    path.join(projectRoot.path, 'assets', 'config', 'app.json'),
  );
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    BookConfig.fromJson(json);
  } on Object {
    throw const FormatException('Invalid app configuration.');
  }
  final applicationId = json['applicationId'];
  final displayName = json['displayName'] ?? json['title'];
  if (applicationId is! String ||
      !RegExp(
        r'^[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)+$',
      ).hasMatch(applicationId) ||
      displayName is! String ||
      displayName.trim().isEmpty ||
      displayName.contains(RegExp(r'[\u0000-\u001f]'))) {
    throw const FormatException('Invalid native app name or identifier.');
  }

  final gradleFile = File(
    path.join(projectRoot.path, 'android', 'app', 'build.gradle.kts'),
  );
  final manifestFile = File(
    path.join(
      projectRoot.path,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    ),
  );
  final infoFile = File(
    path.join(projectRoot.path, 'ios', 'Runner', 'Info.plist'),
  );
  final projectFile = File(
    path.join(projectRoot.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
  );
  final activityRoot = Directory(
    path.join(projectRoot.path, 'android', 'app', 'src', 'main'),
  );
  final activities = activityRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where(
        (file) =>
            path.basename(file.path) == 'MainActivity.kt' ||
            path.basename(file.path) == 'MainActivity.java',
      )
      .toList();
  if (activities.length != 1) {
    throw const FormatException('Expected exactly one Android MainActivity.');
  }
  final activityFile = activities.single;

  final gradle = await gradleFile.readAsString();
  final manifest = await manifestFile.readAsString();
  final info = await infoFile.readAsString();
  final project = await projectFile.readAsString();
  final activity = await activityFile.readAsString();
  final escapedName = _escapeXml(displayName.trim());

  final nextGradle = _replaceSingleGroup(
    _replaceSingleGroup(
      gradle,
      RegExp(r'(\bnamespace\s*=\s*")[^"]+(")'),
      applicationId,
      'Android namespace',
    ),
    RegExp(r'(\bapplicationId\s*=\s*")[^"]+(")'),
    applicationId,
    'Android application ID',
  );
  final nextManifest = _replaceSingleGroup(
    manifest,
    RegExp(r'(android:label\s*=\s*")[^"]*(")'),
    escapedName,
    'Android display name',
  );
  final nextInfo = _replaceSingleGroup(
    _replaceSingleGroup(
      info,
      RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
      escapedName,
      'iOS display name',
    ),
    RegExp(r'(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)'),
    escapedName,
    'iOS bundle name',
  );
  final packageMatch = RegExp(
    r'(^\s*package\s+)[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)*',
    multiLine: true,
  );
  final packageMatches = packageMatch.allMatches(activity).toList();
  if (packageMatches.length != 1) {
    throw const FormatException('Expected one Android MainActivity package.');
  }
  final package = packageMatches.single;
  final nextActivity = activity.replaceRange(
    package.start,
    package.end,
    '${package.group(1)}$applicationId',
  );

  final bundlePattern = RegExp(r'(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)([^;]+)(;)');
  final bundleMatches = bundlePattern.allMatches(project).toList();
  if (bundleMatches.isEmpty ||
      !bundleMatches.any(
        (match) => match.group(2)!.trim().endsWith('.RunnerTests'),
      ) ||
      !bundleMatches.any(
        (match) => !match.group(2)!.trim().endsWith('.RunnerTests'),
      )) {
    throw const FormatException(
      'Expected iOS app and test bundle identifiers.',
    );
  }
  final nextProject = project.replaceAllMapped(bundlePattern, (match) {
    final identifier = match.group(2)!.trim().endsWith('.RunnerTests')
        ? '$applicationId.RunnerTests'
        : applicationId;
    return '${match.group(1)}$identifier${match.group(3)}';
  });

  final extension = path.extension(activityFile.path);
  final nextActivityFile = File(
    path.joinAll([
      activityRoot.path,
      activityFile.path.contains('${path.separator}kotlin${path.separator}')
          ? 'kotlin'
          : 'java',
      ...applicationId.split('.'),
      'MainActivity$extension',
    ]),
  );
  await gradleFile.writeAsString(nextGradle);
  await manifestFile.writeAsString(nextManifest);
  await infoFile.writeAsString(nextInfo);
  await projectFile.writeAsString(nextProject);
  await nextActivityFile.parent.create(recursive: true);
  await nextActivityFile.writeAsString(nextActivity);
  if (nextActivityFile.path != activityFile.path) await activityFile.delete();
}

String _replaceSingleGroup(
  String source,
  RegExp pattern,
  String replacement,
  String field,
) {
  final matches = pattern.allMatches(source).toList();
  if (matches.length != 1) {
    throw FormatException('Expected exactly one $field setting.');
  }
  final match = matches.single;
  return source.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}$replacement${match.group(2)}',
  );
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
