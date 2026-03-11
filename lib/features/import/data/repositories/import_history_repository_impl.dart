import 'dart:convert';

import 'package:course_schedule_app/features/import/data/local/import_history_local_datasource.dart';
import 'package:course_schedule_app/features/import/domain/entities/import_history_entry.dart';
import 'package:course_schedule_app/features/import/domain/repositories/import_history_repository.dart';

class ImportHistoryRepositoryImpl implements ImportHistoryRepository {
  ImportHistoryRepositoryImpl({ImportHistoryLocalDataSource? localDataSource})
    : _localDataSource = localDataSource ?? ImportHistoryLocalDataSource();

  static const int _maxEntries = 8;

  final ImportHistoryLocalDataSource _localDataSource;

  @override
  Future<List<ImportHistoryEntry>> loadHistory() async {
    final historyJson = await _localDataSource.loadHistoryJson();
    if (historyJson == null || historyJson.isEmpty) {
      return const <ImportHistoryEntry>[];
    }

    try {
      final decoded = jsonDecode(historyJson) as List<dynamic>;
      final entries =
          decoded
              .map(
                (item) =>
                    ImportHistoryEntry.fromJson(item as Map<String, dynamic>),
              )
              .toList()
            ..sort(
              (left, right) => right.importedAt.compareTo(left.importedAt),
            );
      return entries;
    } on FormatException {
      await _localDataSource.clearHistoryJson();
      return const <ImportHistoryEntry>[];
    } on TypeError {
      await _localDataSource.clearHistoryJson();
      return const <ImportHistoryEntry>[];
    }
  }

  @override
  Future<void> saveHistoryEntry(ImportHistoryEntry entry) async {
    final entries = await loadHistory();
    final updatedEntries = <ImportHistoryEntry>[
      entry,
      ...entries.where((item) => item.id != entry.id),
    ]..sort((left, right) => right.importedAt.compareTo(left.importedAt));

    final trimmedEntries = updatedEntries.take(_maxEntries).toList();
    final encoded = jsonEncode(
      trimmedEntries.map((item) => item.toJson()).toList(),
    );
    await _localDataSource.saveHistoryJson(encoded);
  }
}
