import 'package:shared_preferences/shared_preferences.dart';

class ScheduleLocalDataSource {
  static const _semestersKey = 'semesters';
  static const _currentSemesterIdKey = 'current_semester_id';
  static const _legacyCurrentSemesterKey = 'current_semester';

  Future<String?> loadSemestersJson() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_semestersKey);
  }

  Future<void> saveSemestersJson(String json) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_semestersKey, json);
  }

  Future<void> clearSemestersJson() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_semestersKey);
  }

  Future<String?> loadCurrentSemesterId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_currentSemesterIdKey);
  }

  Future<void> saveCurrentSemesterId(String semesterId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_currentSemesterIdKey, semesterId);
  }

  Future<void> clearCurrentSemesterId() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_currentSemesterIdKey);
  }

  Future<String?> loadLegacyCurrentSemesterJson() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_legacyCurrentSemesterKey);
  }

  Future<void> clearLegacyCurrentSemester() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyCurrentSemesterKey);
  }
}
