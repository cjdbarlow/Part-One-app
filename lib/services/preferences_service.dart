import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  final SharedPreferences preferences;
  final String bookId;
  PreferencesService(this.preferences, this.bookId);
  bool get sidenotesVisible => preferences.getBool('$bookId.sidenotes') ?? true;
  bool get sidebarVisible => preferences.getBool('$bookId.sidebar') ?? true;
  String? get lastHref => preferences.getString('$bookId.lastHref');
  Future<bool> saveSidenotes(bool value) =>
      preferences.setBool('$bookId.sidenotes', value);
  Future<bool> saveSidebar(bool value) =>
      preferences.setBool('$bookId.sidebar', value);
  Future<bool> saveLastHref(String value) =>
      preferences.setString('$bookId.lastHref', value);
}
