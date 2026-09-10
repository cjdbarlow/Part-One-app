import 'package:flutter/foundation.dart';
import '../services/preferences_service.dart';

class SettingsProvider extends ChangeNotifier {
  final PreferencesService preferences;
  SettingsProvider(this.preferences);
  bool get sidenotesVisible => preferences.sidenotesVisible;
  bool get sidebarVisible => preferences.sidebarVisible;
  String? get lastHref => preferences.lastHref;
  Future<void> setSidenotesVisible(bool value) async {
    await preferences.saveSidenotes(value);
    notifyListeners();
  }

  Future<void> setSidebarVisible(bool value) async {
    await preferences.saveSidebar(value);
    notifyListeners();
  }

  Future<void> setLastHref(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.path.startsWith('/') ||
        Uri.decodeComponent(uri.path).split('/').contains('..')) {
      return;
    }
    await preferences.saveLastHref(value);
  }
}
