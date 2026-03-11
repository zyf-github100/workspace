import 'package:shared_preferences/shared_preferences.dart';

class ImportHistoryLocalDataSource {
  static const historyKey = 'import_history_entries';

  Future<String?> loadHistoryJson() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(historyKey);
  }

  Future<void> saveHistoryJson(String json) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(historyKey, json);
  }

  Future<void> clearHistoryJson() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(historyKey);
  }
}
