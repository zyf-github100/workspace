import 'package:course_schedule_app/app/routes.dart';
import 'package:course_schedule_app/core/constants/app_constants.dart';
import 'package:course_schedule_app/core/utils/course_conflict_utils.dart';
import 'package:course_schedule_app/core/utils/parser_utils.dart';
import 'package:course_schedule_app/features/schedule/data/repositories/schedule_repository_impl.dart';
import 'package:course_schedule_app/features/schedule/domain/entities/course.dart';
import 'package:course_schedule_app/features/schedule/domain/entities/semester.dart';
import 'package:course_schedule_app/features/schedule/domain/repositories/schedule_repository.dart';
import 'package:course_schedule_app/features/schedule/presentation/widgets/course_detail_sheet.dart';
import 'package:course_schedule_app/features/schedule/presentation/widgets/day_selector.dart';
import 'package:course_schedule_app/features/schedule/presentation/widgets/schedule_grid.dart';
import 'package:course_schedule_app/features/schedule/presentation/widgets/week_selector.dart';
import 'package:course_schedule_app/features/settings/domain/entities/section_time.dart';
import 'package:course_schedule_app/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';

enum _ScheduleViewMode { week, day }

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, this.repository});

  final ScheduleRepository? repository;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final ScheduleRepository _repository;
  late Future<Semester?> _semesterFuture;
  int _selectedWeek = 1;
  int _selectedDay = DateTime.now().weekday;
  String? _lastLoadedSemesterVersion;
  _ScheduleViewMode _viewMode = _ScheduleViewMode.week;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ScheduleRepositoryImpl();
    _semesterFuture = _loadPageData();
  }

  Future<Semester?> _loadPageData() async {
    final semester = await _repository.loadCurrentSemester();
    final semesterVersion = semester == null
        ? null
        : _semesterVersion(semester);
    if (semester != null && semesterVersion != _lastLoadedSemesterVersion) {
      _selectedWeek = _currentWeekOfSemester(semester);
      _lastLoadedSemesterVersion = semesterVersion;
    } else if (semester == null) {
      _lastLoadedSemesterVersion = null;
    }
    return semester;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).pushNamed(AppRoutes.settings);
    if (!mounted) {
      return;
    }
    setState(() {
      _semesterFuture = _loadPageData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
            tooltip: '学期设置',
          ),
        ],
      ),
      body: Stack(
        children: [
          const _ScheduleBackdrop(),
          FutureBuilder<Semester?>(
            future: _semesterFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final semester = snapshot.data;
              if (semester == null) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: AppCard(
                    borderRadius: 30,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F6F1),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.calendar_view_week_outlined,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '还没有可展示的课表',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '先导入并确认课表，之后这里会展示保存后的真实课程表。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.importEntry);
                          },
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('去导入课表'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final totalWeeks = semester.totalWeeks < 1
                  ? 1
                  : semester.totalWeeks;
              if (_selectedWeek > totalWeeks) {
                _selectedWeek = totalWeeks;
              }

              final weekCourses =
                  semester.courses
                      .where((course) => course.weeks.contains(_selectedWeek))
                      .toList()
                    ..sort(_compareCourses);
              final dayCourses =
                  weekCourses
                      .where((course) => course.weekday == _selectedDay)
                      .toList()
                    ..sort(_compareCourses);
              final activeCourses = _viewMode == _ScheduleViewMode.week
                  ? weekCourses
                  : dayCourses;
              final dayCourseCounts = <int, int>{
                for (
                  var weekday = 1;
                  weekday <= AppConstants.weekdays.length;
                  weekday++
                )
                  weekday: weekCourses
                      .where((course) => course.weekday == weekday)
                      .length,
              };
              final conflicts = detectCourseConflicts(activeCourses);
              final conflictingCourseIds = <String>{
                for (final conflict in conflicts) conflict.firstKey,
                for (final conflict in conflicts) conflict.secondKey,
              };

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    AppCard(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF204937), Color(0xFF7EA7D6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderColor: Colors.white.withValues(alpha: 0.18),
                      borderRadius: 32,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _HeaderPill(
                                label: _viewMode == _ScheduleViewMode.week
                                    ? '周视图'
                                    : '日视图',
                              ),
                              const Spacer(),
                              _HeaderPill(label: '${activeCourses.length} 门课'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            semester.name,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _viewMode == _ScheduleViewMode.week
                                ? '第 $_selectedWeek 周 · 开学于 ${_formatDate(semester.termStartDate)}'
                                : '第 $_selectedWeek 周 · ${AppConstants.weekdayLabel(_selectedDay)}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.84),
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricBox(
                                  label: '当前课程',
                                  value: '${activeCourses.length}',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MetricBox(
                                  label: '冲突组数',
                                  value: '${conflicts.length}',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MetricBox(
                                  label: '节次分组',
                                  value: '${semester.sectionTimes.length}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      borderRadius: 28,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF6FAF6), Color(0xFFF0F5FA)],
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<_ScheduleViewMode>(
                                style: ButtonStyle(
                                  textStyle: WidgetStateProperty.all(
                                    const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                segments:
                                    const <ButtonSegment<_ScheduleViewMode>>[
                                      ButtonSegment<_ScheduleViewMode>(
                                        value: _ScheduleViewMode.week,
                                        icon: Icon(Icons.grid_view_rounded),
                                        label: Text('周视图'),
                                      ),
                                      ButtonSegment<_ScheduleViewMode>(
                                        value: _ScheduleViewMode.day,
                                        icon: Icon(
                                          Icons.calendar_view_day_rounded,
                                        ),
                                        label: Text('日视图'),
                                      ),
                                    ],
                                selected: <_ScheduleViewMode>{_viewMode},
                                showSelectedIcon: false,
                                onSelectionChanged: (selection) {
                                  setState(() {
                                    _viewMode = selection.first;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '周次',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          WeekSelector(
                            selectedWeek: _selectedWeek,
                            totalWeeks: totalWeeks,
                            onChanged: (week) {
                              setState(() {
                                _selectedWeek = week;
                              });
                            },
                          ),
                          if (_viewMode == _ScheduleViewMode.day) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '星期',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DaySelector(
                              selectedDay: _selectedDay,
                              courseCounts: dayCourseCounts,
                              onChanged: (day) {
                                setState(() {
                                  _selectedDay = day;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (conflicts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      AppCard(
                        color: const Color(0xFFFFF4F1),
                        borderColor: const Color(0xFFF2D7D1),
                        borderRadius: 26,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _viewMode == _ScheduleViewMode.week
                                  ? '第 $_selectedWeek 周有 ${conflicts.length} 组课程冲突'
                                  : '${AppConstants.weekdayLabel(_selectedDay)}有 ${conflicts.length} 组课程冲突',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            for (
                              var i = 0;
                              i < conflicts.length && i < 3;
                              i++
                            ) ...[
                              Text(
                                conflictSummary(
                                  conflicts[i],
                                  includeWeeks:
                                      _viewMode == _ScheduleViewMode.week,
                                ),
                              ),
                              if (i != conflicts.length - 1 && i < 2)
                                const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: activeCourses.isEmpty
                          ? AppCard(
                              borderRadius: 30,
                              child: Center(
                                child: Text(
                                  _viewMode == _ScheduleViewMode.week
                                      ? '第 $_selectedWeek 周暂无课程。'
                                      : '${AppConstants.weekdayLabel(_selectedDay)}暂无课程。',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            )
                          : _viewMode == _ScheduleViewMode.week
                          ? ScheduleGrid(
                              courses: weekCourses,
                              sectionTimes: semester.sectionTimes,
                              conflictingCourseIds: conflictingCourseIds,
                              onCoursesTap: (courses) {
                                _showCourseDetails(semester, courses);
                              },
                            )
                          : _DayScheduleList(
                              courses: dayCourses,
                              sectionTimes: semester.sectionTimes,
                              conflictingCourseIds: conflictingCourseIds,
                              onTap: (course) {
                                _showCourseDetails(semester, <Course>[course]);
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  int _compareCourses(Course left, Course right) {
    final weekdayCompare = left.weekday.compareTo(right.weekday);
    if (weekdayCompare != 0) {
      return weekdayCompare;
    }
    return left.startSection.compareTo(right.startSection);
  }

  int _currentWeekOfSemester(Semester semester) {
    final start = DateTime(
      semester.termStartDate.year,
      semester.termStartDate.month,
      semester.termStartDate.day,
    );
    final now = DateTime.now();
    final difference = now.difference(start).inDays;
    final week = difference < 0 ? 1 : (difference ~/ 7) + 1;
    return week.clamp(1, semester.totalWeeks);
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _semesterVersion(Semester semester) {
    return '${semester.id}|${semester.termStartDate.toIso8601String()}';
  }

  Future<void> _showCourseDetails(Semester semester, List<Course> courses) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return CourseDetailSheet(
          courses: courses,
          selectedWeek: _selectedWeek,
          sectionTimes: semester.sectionTimes,
        );
      },
    );
  }
}

class _ScheduleBackdrop extends StatelessWidget {
  const _ScheduleBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: const [
          Positioned(
            top: -70,
            left: -40,
            child: _GlowOrb(size: 180, color: Color(0x122D6B54)),
          ),
          Positioned(
            top: 120,
            right: -60,
            child: _GlowOrb(size: 220, color: Color(0x107AA8D7)),
          ),
          Positioned(
            bottom: 40,
            left: -40,
            child: _GlowOrb(size: 160, color: Color(0x10E8C4A5)),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayScheduleList extends StatelessWidget {
  const _DayScheduleList({
    required this.courses,
    required this.sectionTimes,
    required this.conflictingCourseIds,
    required this.onTap,
  });

  final List<Course> courses;
  final List<SectionTime> sectionTimes;
  final Set<String> conflictingCourseIds;
  final ValueChanged<Course> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: courses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final course = courses[index];
        return InkWell(
          onTap: () => onTap(course),
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFEFB),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: conflictingCourseIds.contains(course.id)
                    ? const Color(0xFFE36464)
                    : const Color(0xFFE2EAE3),
                width: conflictingCourseIds.contains(course.id) ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Color(course.colorValue),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F5EE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _courseTimeText(course, sectionTimes),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF24543E),
                              ),
                            ),
                          ),
                          if (conflictingCourseIds.contains(course.id))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE1E1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                '冲突',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        course.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _MetaChip(
                            icon: Icons.place_outlined,
                            label: course.location ?? '地点待定',
                          ),
                          _MetaChip(
                            icon: Icons.repeat_rounded,
                            label: '周数 ${weeksToText(course.weeks)}',
                          ),
                          if (course.teacher != null &&
                              course.teacher!.isNotEmpty)
                            _MetaChip(
                              icon: Icons.person_outline_rounded,
                              label: course.teacher!,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8BA094),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _courseTimeText(Course course, List<SectionTime> sectionTimes) {
    final startTime =
        course.startTime ??
        _slotForSection(sectionTimes, course.startSection)?.startTime;
    final endTime =
        course.endTime ??
        _slotForSection(sectionTimes, course.endSection)?.endTime;
    final sectionText = '${course.startSection}-${course.endSection}节';
    if (startTime != null && endTime != null) {
      return '$sectionText · $startTime-$endTime';
    }
    return sectionText;
  }

  SectionTime? _slotForSection(List<SectionTime> sectionTimes, int section) {
    for (final slot in sectionTimes) {
      if (section >= slot.startSection && section <= slot.endSection) {
        return slot;
      }
    }
    return null;
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF607469)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
