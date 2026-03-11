import 'package:course_schedule_app/features/settings/data/local/settings_local_datasource.dart';
import 'package:course_schedule_app/features/settings/data/repositories/schedule_settings_repository_impl.dart';
import 'package:course_schedule_app/features/settings/domain/entities/schedule_settings.dart';
import 'package:course_schedule_app/features/settings/domain/entities/section_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleSettingsRepositoryImpl', () {
    test('returns defaults when local storage is empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repository = ScheduleSettingsRepositoryImpl(
        localDataSource: SettingsLocalDataSource(),
      );

      final settings = await repository.loadSettings();

      expect(settings.semesterName, isNotEmpty);
      expect(settings.sectionTimes, isNotEmpty);
    });

    test('saves and loads settings from local storage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repository = ScheduleSettingsRepositoryImpl(
        localDataSource: SettingsLocalDataSource(),
      );
      final settings = ScheduleSettings(
        semesterName: '2026年春季学期',
        termStartDate: DateTime(2026, 2, 24),
        sectionTimes: <SectionTime>[
          SectionTime(
            startSection: 1,
            endSection: 2,
            startTime: '08:00',
            endTime: '09:35',
          ),
          SectionTime(
            startSection: 3,
            endSection: 4,
            startTime: '10:00',
            endTime: '11:35',
          ),
        ],
      );

      await repository.saveSettings(settings);
      final loaded = await repository.loadSettings();

      expect(loaded.semesterName, '2026年春季学期');
      expect(loaded.termStartDate, DateTime(2026, 2, 24));
      expect(loaded.sectionTimes, hasLength(2));
      expect(loaded.sectionTimes.first.startTime, '08:00');
      expect(loaded.sectionTimes.last.endTime, '11:35');
    });

    test(
      'falls back to defaults when stored settings json is corrupted',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'schedule_settings': '{broken json',
        });

        final repository = ScheduleSettingsRepositoryImpl(
          localDataSource: SettingsLocalDataSource(),
        );

        final settings = await repository.loadSettings();

        expect(settings.semesterName, isNotEmpty);
        expect(settings.sectionTimes, isNotEmpty);
      },
    );
  });
}
