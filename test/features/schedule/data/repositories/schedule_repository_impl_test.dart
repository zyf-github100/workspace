import 'dart:convert';

import 'package:course_schedule_app/features/schedule/data/local/schedule_local_datasource.dart';
import 'package:course_schedule_app/features/schedule/data/repositories/schedule_repository_impl.dart';
import 'package:course_schedule_app/features/schedule/domain/entities/course.dart';
import 'package:course_schedule_app/features/schedule/domain/entities/semester.dart';
import 'package:course_schedule_app/features/settings/domain/entities/section_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleRepositoryImpl', () {
    test(
      'saves semesters and tracks the latest saved semester as current',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final repository = ScheduleRepositoryImpl(
          localDataSource: ScheduleLocalDataSource(),
        );
        final springSemester = _semester(
          id: 'semester-spring',
          name: '2026年春季学期',
          termStartDate: DateTime(2026, 2, 24),
        );
        final autumnSemester = _semester(
          id: 'semester-autumn',
          name: '2026年秋季学期',
          termStartDate: DateTime(2026, 9, 1),
        );

        await repository.saveSemester(springSemester);
        await repository.saveSemester(autumnSemester);

        final semesters = await repository.loadSemesters();
        final currentSemester = await repository.loadCurrentSemester();

        expect(semesters, hasLength(2));
        expect(semesters.first.id, 'semester-autumn');
        expect(currentSemester, isNotNull);
        expect(currentSemester!.id, 'semester-autumn');
        expect(currentSemester.sectionTimes, hasLength(2));
      },
    );

    test('switches and deletes semesters from local storage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repository = ScheduleRepositoryImpl(
        localDataSource: ScheduleLocalDataSource(),
      );
      final springSemester = _semester(
        id: 'semester-spring',
        name: '2026年春季学期',
        termStartDate: DateTime(2026, 2, 24),
      );
      final autumnSemester = _semester(
        id: 'semester-autumn',
        name: '2026年秋季学期',
        termStartDate: DateTime(2026, 9, 1),
      );

      await repository.saveSemester(springSemester);
      await repository.saveSemester(autumnSemester);
      await repository.setCurrentSemester('semester-spring');

      var currentSemester = await repository.loadCurrentSemester();
      expect(currentSemester, isNotNull);
      expect(currentSemester!.id, 'semester-spring');

      await repository.deleteSemester('semester-spring');

      currentSemester = await repository.loadCurrentSemester();
      final semesters = await repository.loadSemesters();
      expect(semesters, hasLength(1));
      expect(semesters.single.id, 'semester-autumn');
      expect(currentSemester, isNotNull);
      expect(currentSemester!.id, 'semester-autumn');
    });

    test(
      'migrates legacy current_semester storage into the new list format',
      () async {
        final legacySemester = _semester(
          id: 'semester-legacy',
          name: '2025年秋季学期',
          termStartDate: DateTime(2025, 9, 1),
        );
        final legacyJson = Map<String, dynamic>.from(legacySemester.toJson())
          ..remove('sectionTimes');

        SharedPreferences.setMockInitialValues(<String, Object>{
          'current_semester': jsonEncode(legacyJson),
        });

        final repository = ScheduleRepositoryImpl(
          localDataSource: ScheduleLocalDataSource(),
        );

        final currentSemester = await repository.loadCurrentSemester();
        final semesters = await repository.loadSemesters();

        expect(currentSemester, isNotNull);
        expect(currentSemester!.id, 'semester-legacy');
        expect(currentSemester.sectionTimes, isNotEmpty);
        expect(semesters, hasLength(1));
      },
    );

    test(
      'returns empty state when stored semesters json is corrupted',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'semesters': '{broken json',
          'current_semester_id': 'semester-1',
        });

        final repository = ScheduleRepositoryImpl(
          localDataSource: ScheduleLocalDataSource(),
        );

        final currentSemester = await repository.loadCurrentSemester();
        final semesters = await repository.loadSemesters();

        expect(currentSemester, isNull);
        expect(semesters, isEmpty);
      },
    );
  });
}

Semester _semester({
  required String id,
  required String name,
  required DateTime termStartDate,
}) {
  return Semester(
    id: id,
    name: name,
    termStartDate: termStartDate,
    totalWeeks: 16,
    courses: const <Course>[
      Course(
        id: 'course-1',
        name: '高等数学',
        teacher: '刘老师',
        location: 'A-203',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        weeks: <int>[1, 2, 3, 4],
        colorValue: 0xFF7CB7FF,
      ),
    ],
    sectionTimes: const <SectionTime>[
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
}
