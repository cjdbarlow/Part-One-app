import 'dart:io';

import 'package:part_one/services/app_configuration_service.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/configure_app.dart\n'
      'Applies the single app configuration in assets/config/app.json.\n'
      'This command takes no arguments.',
    );
    exitCode = 64;
    return;
  }
  try {
    await configureApp(projectRoot: Directory.current);
    stdout.writeln('Configured app from assets/config/app.json.');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('Could not configure the app: ${error.message}');
    exitCode = 1;
  }
}
