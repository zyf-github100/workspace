import 'package:course_schedule_app/app/routes.dart';
import 'package:course_schedule_app/features/schedule/domain/entities/course.dart';
import 'package:course_schedule_app/features/schedule/domain/entities/semester.dart';
import 'package:course_schedule_app/features/schedule/domain/repositories/schedule_repository.dart';
import 'package:course_schedule_app/features/schedule/presentation/pages/schedule_page.dart';
import 'package:course_schedule_app/features/settings/domain/entities/section_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'schedule page switches to day view and filters courses by weekday',
    (WidgetTester tester) async {
      final repository = _FakeScheduleRepository(
        currentSemester: Semester(
          id: 'semester-1',
          name: '2026年春季学期',
          termStartDate: DateTime(2026, 2, 24),
          totalWeeks: 16,
          courses: const <Course>[
            Course(
              id: 'course-1',
              name: '高等数学',
              weekday: 1,
              startSection: 1,
              endSection: 2,
              startTime: '08:00',
              endTime: '09:35',
              weeks: <int>[3],
              colorValue: 0xFF7CB7FF,
            ),
            Course(
              id: 'course-2',
              name: '大学英语',
              weekday: 2,
              startSection: 3,
              endSection: 4,
              startTime: '10:00',
              endTime: '11:35',
              weeks: <int>[3],
              colorValue: 0xFF8ACB88,
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
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: SchedulePage(repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('日视图'));
      await tester.pumpAndSettle();
      final mondayChip = find.widgetWithText(ChoiceChip, '周一').first;
      await tester.ensureVisible(mondayChip);
      await tester.tap(mondayChip);
      await tester.pumpAndSettle();

      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('周数 3'), findsOneWidget);
      expect(find.text('大学英语'), findsNothing);
    },
  );

  testWidgets(
    'schedule page still renders late-section courses when section settings are incomplete',
    (WidgetTester tester) async {
      final repository = _FakeScheduleRepository(
        currentSemester: Semester(
          id: 'semester-2',
          name: '2026年春季学期',
          termStartDate: DateTime(2026, 2, 24),
          totalWeeks: 16,
          courses: const <Course>[
            Course(
              id: 'course-late',
              name: '晚间课程',
              weekday: 2,
              startSection: 13,
              endSection: 14,
              startTime: '19:00',
              endTime: '20:20',
              weeks: <int>[3],
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
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: SchedulePage(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('晚间课程'), findsOneWidget);
      expect(find.text('13-14节'), findsOneWidget);
      expect(find.text('19:00-20:20'), findsOneWidget);
    },
  );

  testWidgets(
    'schedule page recalculates current week after semester changes in settings',
    (WidgetTester tester) async {
      final repository = _MutableScheduleRepository(
        semester: Semester(
          id: 'semester-spring',
          name: '2026年春季学期',
          termStartDate: DateTime(2026, 2, 24),
          totalWeeks: 16,
          courses: const <Course>[],
          sectionTimes: const <SectionTime>[
            SectionTime(
              startSection: 1,
              endSection: 2,
              startTime: '08:00',
              endTime: '09:35',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.settings) {
              return MaterialPageRoute<void>(
                builder: (_) => _SettingsStub(
                  onOpen: () {
                    repository.semester = Semester(
                      id: 'semester-late',
                      name: '2026年夏季学期',
                      termStartDate: DateTime(2026, 3, 10),
                      totalWeeks: 16,
                      courses: const <Course>[],
                      sectionTimes: const <SectionTime>[
                        SectionTime(
                          startSection: 1,
                          endSection: 2,
                          startTime: '08:00',
                          endTime: '09:35',
                        ),
                      ],
                    );
                  },
                ),
              );
            }

            return null;
          },
          home: SchedulePage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第 3 周 · 开学于 2026-02-24'), findsOneWidget);

      await tester.tap(find.byTooltip('学期设置'));
      await tester.pumpAndSettle();

      expect(find.text('第 1 周 · 开学于 2026-03-10'), findsOneWidget);
      expect(find.text('2026年夏季学期'), findsOneWidget);
    },
  );
}

class _FakeScheduleRepository implements ScheduleRepository {
  _FakeScheduleRepository({this.currentSemester});

  final Semester? currentSemester;

  @override
  Future<void> clearCurrentSemester() async {}

  @override
  Future<void> deleteSemester(String semesterId) async {}

  @override
  Future<Semester?> loadCurrentSemester() async => currentSemester;

  @override
  Future<List<Semester>> loadSemesters() async => currentSemester == null
      ? const <Semester>[]
      : <Semester>[currentSemester!];

  @override
  Future<void> saveSemester(Semester semester) async {}

  @override
  Future<void> setCurrentSemester(String semesterId) async {}
}

class _MutableScheduleRepository implements ScheduleRepository {
  _MutableScheduleRepository({required this.semester});

  Semester? semester;

  @override
  Future<void> clearCurrentSemester() async {}

  @override
  Future<void> deleteSemester(String semesterId) async {}

  @override
  Future<Semester?> loadCurrentSemester() async => semester;

  @override
  Future<List<Semester>> loadSemesters() async =>
      semester == null ? const <Semester>[] : <Semester>[semester!];

  @override
  Future<void> saveSemester(Semester semester) async {
    this.semester = semester;
  }

  @override
  Future<void> setCurrentSemester(String semesterId) async {}
}

class _SettingsStub extends StatefulWidget {
  const _SettingsStub({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_SettingsStub> createState() => _SettingsStubState();
}

class _SettingsStubState extends State<_SettingsStub> {
  @override
  void initState() {
    super.initState();
    widget.onOpen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}
