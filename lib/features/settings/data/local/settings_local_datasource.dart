import 'package:shared_preferences/shared_preferences.dart';

class SettingsLocalDataSource {
  static const _settingsKey = 'schedule_settings';

  Future<String?> loadSettingsJson() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_settingsKey);
  }

  Future<void> saveSettingsJson(String json) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_settingsKey, json);
  }

  Future<void> clearSettingsJson() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_settingsKey);
  }
}
