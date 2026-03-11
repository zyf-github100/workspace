import 'dart:convert';

import 'package:course_schedule_app/features/schedule/data/local/schedule_local_datasource.dart';
import 'package:course_schedule_app/features/schedule/domain/entities/semester.dart';
import 'package:course_schedule_app/features/schedule/domain/repositories/schedule_repository.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  ScheduleRepositoryImpl({ScheduleLocalDataSource? localDataSource})
    : _localDataSource = localDataSource ?? ScheduleLocalDataSource();

  final ScheduleLocalDataSource _localDataSource;

  @override
  Future<Semester?> loadCurrentSemester() async {
    final store = await _loadStore();
    if (store.currentSemesterId == null) {
      return null;
    }

    for (final semester in store.semesters) {
      if (semester.id == store.currentSemesterId) {
        return semester;
      }
    }

    return null;
  }

  @override
  Future<List<Semester>> loadSemesters() async {
    final store = await _loadStore();
    return List<Semester>.from(store.semesters);
  }

  @override
  Future<void> saveSemester(Semester semester) async {
    final store = await _loadStore();
    final semesters = List<Semester>.from(store.semesters)
      ..removeWhere((item) => item.id == semester.id)
      ..add(semester);
    semesters.sort(
      (left, right) => right.termStartDate.compareTo(left.termStartDate),
    );

    await _persistStore(
      _ScheduleStore(semesters: semesters, currentSemesterId: semester.id),
    );
  }

  @override
  Future<void> setCurrentSemester(String semesterId) async {
    final store = await _loadStore();
    final exists = store.semesters.any((semester) => semester.id == semesterId);
    if (!exists) {
      return;
    }

    await _persistStore(
      _ScheduleStore(semesters: store.semesters, currentSemesterId: semesterId),
    );
  }

  @override
  Future<void> deleteSemester(String semesterId) async {
    final store = await _loadStore();
    final semesters = List<Semester>.from(store.semesters)
      ..removeWhere((semester) => semester.id == semesterId);
    final currentSemesterId = semesters.isEmpty
        ? null
        : store.currentSemesterId == semesterId
        ? semesters.first.id
        : store.currentSemesterId;

    await _persistStore(
      _ScheduleStore(
        semesters: semesters,
        currentSemesterId: currentSemesterId,
      ),
    );
  }

  @override
  Future<void> clearCurrentSemester() async {
    final currentSemester = await loadCurrentSemester();
    if (currentSemester == null) {
      return;
    }

    await deleteSemester(currentSemester.id);
  }

  Future<_ScheduleStore> _loadStore() async {
    final semestersJson = await _localDataSource.loadSemestersJson();
    final currentSemesterId = await _localDataSource.loadCurrentSemesterId();

    if (semestersJson != null && semestersJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(semestersJson) as List<dynamic>;
        final semesters = decoded
            .map((item) => Semester.fromJson(item as Map<String, dynamic>))
            .toList();
        final normalizedCurrentSemesterId = semesters.isEmpty
            ? null
            : currentSemesterId != null &&
                  semesters.any((semester) => semester.id == currentSemesterId)
            ? currentSemesterId
            : semesters.first.id;
        if (normalizedCurrentSemesterId != currentSemesterId) {
          await _persistStore(
            _ScheduleStore(
              semesters: semesters,
              currentSemesterId: normalizedCurrentSemesterId,
            ),
          );
        }

        return _ScheduleStore(
          semesters: semesters,
          currentSemesterId: normalizedCurrentSemesterId,
        );
      } on FormatException {
        await _localDataSource.clearSemestersJson();
        await _localDataSource.clearCurrentSemesterId();
      } on TypeError {
        await _localDataSource.clearSemestersJson();
        await _localDataSource.clearCurrentSemesterId();
      }
    }

    final legacyJson = await _localDataSource.loadLegacyCurrentSemesterJson();
    if (legacyJson == null || legacyJson.isEmpty) {
      return const _ScheduleStore(
        semesters: <Semester>[],
        currentSemesterId: null,
      );
    }

    try {
      final legacySemester = Semester.fromJson(
        jsonDecode(legacyJson) as Map<String, dynamic>,
      );
      final migratedStore = _ScheduleStore(
        semesters: <Semester>[legacySemester],
        currentSemesterId: legacySemester.id,
      );
      await _persistStore(migratedStore, clearLegacy: true);
      return migratedStore;
    } on FormatException {
      await _localDataSource.clearLegacyCurrentSemester();
    } on TypeError {
      await _localDataSource.clearLegacyCurrentSemester();
    }

    return const _ScheduleStore(
      semesters: <Semester>[],
      currentSemesterId: null,
    );
  }

  Future<void> _persistStore(
    _ScheduleStore store, {
    bool clearLegacy = true,
  }) async {
    final semestersJson = jsonEncode(
      store.semesters.map((semester) => semester.toJson()).toList(),
    );
    await _localDataSource.saveSemestersJson(semestersJson);

    if (store.currentSemesterId == null) {
      await _localDataSource.clearCurrentSemesterId();
    } else {
      await _localDataSource.saveCurrentSemesterId(store.currentSemesterId!);
    }

    if (clearLegacy) {
      await _localDataSource.clearLegacyCurrentSemester();
    }
  }
}

class _ScheduleStore {
  const _ScheduleStore({
    required this.semesters,
    required this.currentSemesterId,
  });

  final List<Semester> semesters;
  final String? currentSemesterId;
}
