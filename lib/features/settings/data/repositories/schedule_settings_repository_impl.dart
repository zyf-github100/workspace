import 'dart:convert';

import 'package:course_schedule_app/features/settings/data/local/settings_local_datasource.dart';
import 'package:course_schedule_app/features/settings/domain/entities/schedule_settings.dart';
import 'package:course_schedule_app/features/settings/domain/repositories/schedule_settings_repository.dart';

class ScheduleSettingsRepositoryImpl implements ScheduleSettingsRepository {
  ScheduleSettingsRepositoryImpl({SettingsLocalDataSource? localDataSource})
    : _localDataSource = localDataSource ?? SettingsLocalDataSource();

  final SettingsLocalDataSource _localDataSource;

  @override
  Future<ScheduleSettings> loadSettings() async {
    final json = await _localDataSource.loadSettingsJson();
    if (json == null || json.isEmpty) {
      return ScheduleSettings.defaults();
    }

    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return ScheduleSettings.fromJson(decoded);
    } on FormatException {
      await _localDataSource.clearSettingsJson();
      return ScheduleSettings.defaults();
    } on TypeError {
      await _localDataSource.clearSettingsJson();
      return ScheduleSettings.defaults();
    }
  }

  @override
  Future<void> saveSettings(ScheduleSettings settings) async {
    final json = jsonEncode(settings.toJson());
    await _localDataSource.saveSettingsJson(json);
  }
}
