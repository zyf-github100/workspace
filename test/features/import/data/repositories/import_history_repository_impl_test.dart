import 'package:course_schedule_app/features/import/data/local/import_history_local_datasource.dart';
import 'package:course_schedule_app/features/import/data/repositories/import_history_repository_impl.dart';
import 'package:course_schedule_app/features/import/domain/entities/import_history_entry.dart';
import 'package:course_schedule_app/features/import/domain/entities/import_source_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ImportHistoryRepositoryImpl', () {
    test('stores entries in reverse chronological order', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repository = ImportHistoryRepositoryImpl(
        localDataSource: ImportHistoryLocalDataSource(),
      );

      await repository.saveHistoryEntry(
        _entry(
          id: '1',
          sourceFileName: 'spring.xlsx',
          importedAt: DateTime(2026, 3, 10, 8, 0),
        ),
      );
      await repository.saveHistoryEntry(
        _entry(
          id: '2',
          sourceFileName: 'spring.pdf',
          sourceType: ImportSourceType.pdf,
          importedAt: DateTime(2026, 3, 11, 9, 30),
        ),
      );

      final history = await repository.loadHistory();

      expect(history, hasLength(2));
      expect(history.first.id, '2');
      expect(history.first.sourceType, ImportSourceType.pdf);
      expect(history.last.id, '1');
    });

    test('keeps only the latest eight entries', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final repository = ImportHistoryRepositoryImpl(
        localDataSource: ImportHistoryLocalDataSource(),
      );

      for (var i = 0; i < 10; i++) {
        await repository.saveHistoryEntry(
          _entry(
            id: '$i',
            sourceFileName: 'schedule_$i.xlsx',
            importedAt: DateTime(2026, 3, 1).add(Duration(days: i)),
          ),
        );
      }

      final history = await repository.loadHistory();

      expect(history, hasLength(8));
      expect(history.first.id, '9');
      expect(history.last.id, '2');
    });

    test('returns empty history when stored json is corrupted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ImportHistoryLocalDataSource.historyKey: '{broken json',
      });

      final repository = ImportHistoryRepositoryImpl(
        localDataSource: ImportHistoryLocalDataSource(),
      );

      final history = await repository.loadHistory();

      expect(history, isEmpty);
    });
  });
}

ImportHistoryEntry _entry({
  required String id,
  required String sourceFileName,
  required DateTime importedAt,
  ImportSourceType sourceType = ImportSourceType.excel,
}) {
  return ImportHistoryEntry(
    id: id,
    sourceFileName: sourceFileName,
    sourceType: sourceType,
    semesterName: '2026年春季学期',
    courseCount: 18,
    warningCount: 1,
    importedAt: importedAt,
  );
}
