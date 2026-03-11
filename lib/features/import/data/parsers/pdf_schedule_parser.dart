import 'package:course_schedule_app/features/import/domain/entities/import_draft.dart';
import 'package:course_schedule_app/features/import/domain/entities/import_file.dart';
import 'package:course_schedule_app/features/import/domain/entities/import_source_type.dart';
import 'package:course_schedule_app/features/import/domain/entities/parsed_course.dart';
import 'package:course_schedule_app/features/import/domain/services/schedule_parser.dart';
import 'package:course_schedule_app/features/settings/domain/entities/section_time.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfScheduleParser implements ScheduleParser {
  static const Map<String, String>
  _courseTitleFallbackByCode = <String, String>{
    // Known broken glyph case from Guangzhou Software University schedule PDFs.
    'GE4003': '就业指导',
  };

  @override
  Future<ImportDraft> parse(ImportFile file) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('无法读取 PDF 文件内容。');
    }

    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final layoutText = _normalizeText(
        extractor.extractText(layoutText: true),
      );
      final rawText = layoutText.isEmpty
          ? _normalizeText(extractor.extractText())
          : '';
      final extractedText = layoutText.isNotEmpty ? layoutText : rawText;
      if (extractedText.replaceAll(RegExp(r'\s+'), '').length < 8) {
        throw const FormatException('未从 PDF 中提取到足够文本，当前仅支持文本型 PDF。');
      }

      final textLines = _toLineSnapshots(extractor.extractTextLines());
      final courses = parseExtractedText(extractedText, textLines: textLines);
      final suggestedSectionTimes = _extractSuggestedSectionTimes(
        extractedText,
        courses,
      );
      if (courses.isEmpty) {
        throw const FormatException(
          '已提取到 PDF 文本，但未识别到课程。请尝试包含“周几、节次、周数”的文本型 PDF。',
        );
      }

      final warnings = <String>['PDF 当前使用规则解析，建议在确认页继续复核课程信息。'];
      if (courses.any((course) => course.weeks.isEmpty)) {
        warnings.add('部分课程未识别到周数，需要你在确认页补充。');
      }

      return ImportDraft(
        sourceFilePath: file.path,
        sourceFileName: file.name,
        sourceType: ImportSourceType.pdf,
        rawText: extractedText,
        parsedCourses: courses,
        warnings: warnings,
        suggestedSectionTimes: suggestedSectionTimes,
      );
    } finally {
      document.dispose();
    }
  }

  List<ParsedCourse> parseExtractedText(
    String text, {
    List<PdfTextLineSnapshot> textLines = const <PdfTextLineSnapshot>[],
  }) {
    final normalized = _normalizeText(text);
    final inlineCourses = _parseInlineCourses(normalized);
    final gridCourses = textLines.isEmpty
        ? const <ParsedCourse>[]
        : _parseGridCourses(normalized, textLines);
    return _pickPreferredCourses(gridCourses, inlineCourses);
  }

  List<PdfTextLineSnapshot> _toLineSnapshots(List<TextLine> textLines) {
    return textLines
        .map(
          (line) => PdfTextLineSnapshot(
            text: line.text,
            top: line.bounds.top,
            words: line.wordCollection
                .map(
                  (word) => PdfTextWordSnapshot(
                    text: word.text,
                    top: word.bounds.top,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  List<ParsedCourse> _parseInlineCourses(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final candidates = <String>{
      ...text
          .split(RegExp(r'\n{2,}'))
          .map((block) => block.trim())
          .where((block) => block.isNotEmpty),
      ...lines.where(_containsScheduleMarkers),
    };

    for (var i = 0; i < lines.length; i++) {
      if (!_containsScheduleMarkers(lines[i])) {
        continue;
      }

      final buffer = <String>[];
      if (i > 0 && !_containsScheduleMarkers(lines[i - 1])) {
        buffer.add(lines[i - 1]);
      }
      buffer.add(lines[i]);
      if (i + 1 < lines.length && !_containsScheduleMarkers(lines[i + 1])) {
        buffer.add(lines[i + 1]);
      }
      if (i + 2 < lines.length &&
          !_containsScheduleMarkers(lines[i + 1]) &&
          !_containsScheduleMarkers(lines[i + 2])) {
        buffer.add(lines[i + 2]);
      }
      candidates.add(buffer.join('\n'));
    }

    return _dedupeCourses(
      candidates.map(_tryParseBlock).whereType<ParsedCourse>(),
    );
  }

  List<ParsedCourse> _parseGridCourses(
    String text,
    List<PdfTextLineSnapshot> textLines,
  ) {
    final weekdayAnchors = _extractWeekdayAnchors(textLines);
    if (weekdayAnchors.length < 5) {
      return const <ParsedCourse>[];
    }

    final blocks = _extractGridBlocks(text);
    if (blocks.isEmpty) {
      return const <ParsedCourse>[];
    }

    final titles = blocks
        .map((block) => _normalizeLookupKey(block.title))
        .toSet();
    final anchorsByTitle = <String, List<PdfTextLineSnapshot>>{};
    for (final line in textLines) {
      final key = _normalizeLookupKey(line.text);
      if (!titles.contains(key)) {
        continue;
      }
      anchorsByTitle.putIfAbsent(key, () => <PdfTextLineSnapshot>[]).add(line);
    }

    final titleUsage = <String, int>{};
    final courses = <ParsedCourse>[];
    for (final block in blocks) {
      final key = _normalizeLookupKey(block.title);
      final nextIndex = titleUsage.update(
        key,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final titleAnchors = anchorsByTitle[key] ?? const <PdfTextLineSnapshot>[];
      final titleAnchor = nextIndex < titleAnchors.length
          ? titleAnchors[nextIndex]
          : null;
      final weekday = titleAnchor == null
          ? null
          : _resolveWeekday(titleAnchor.top, weekdayAnchors);
      final course = _tryParseBlock(
        block.text,
        inferredName: block.title,
        inferredWeekday: weekday,
      );
      if (course != null) {
        courses.add(course);
      }
    }

    return _dedupeCourses(courses);
  }

  List<_GridCourseBlock> _extractGridBlocks(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final blocks = <_GridCourseBlock>[];

    for (var i = 0; i < lines.length; i++) {
      if (!_looksLikeGridCourseTitle(lines, i)) {
        continue;
      }

      final title = lines[i];
      final buffer = <String>[title];
      var cursor = i + 1;
      while (cursor < lines.length) {
        if (_isBoundaryLine(lines[cursor]) ||
            _looksLikeGridCourseTitle(lines, cursor)) {
          break;
        }
        buffer.add(lines[cursor]);
        cursor++;
      }

      blocks.add(_GridCourseBlock(title: title, text: buffer.join('\n')));
      i = cursor - 1;
    }

    return blocks;
  }

  bool _looksLikeGridCourseTitle(List<String> lines, int index) {
    final line = lines[index];
    if (_isBoundaryLine(line) ||
        line.startsWith('(') ||
        line.startsWith(':') ||
        line.contains('教师:') ||
        line.contains('场地:')) {
      return false;
    }
    if (index + 1 >= lines.length) {
      return false;
    }
    final nextLine = lines[index + 1];
    return _extractSectionRange(nextLine) != null && nextLine.contains('周');
  }

  bool _isBoundaryLine(String line) {
    final normalized = line.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) {
      return true;
    }

    return RegExp(
          r'^(?:\d{1,2}|\d{2}:\d{2}|上午|中午|下午|晚上|时间段.*|节次|星期[一二三四五六日天]|.*课表|.*学年第.*学期|学号[:：].*|打印时间[:：].*)$',
        ).hasMatch(normalized) ||
        normalized.startsWith(':理论') ||
        normalized.startsWith(':实践');
  }

  List<_WeekdayAnchor> _extractWeekdayAnchors(
    List<PdfTextLineSnapshot> textLines,
  ) {
    for (final line in textLines) {
      final anchors = <_WeekdayAnchor>[];
      for (final word in line.words) {
        final weekday = _matchWeekday(word.text);
        if (weekday == null) {
          continue;
        }
        anchors.add(_WeekdayAnchor(weekday: weekday, top: word.top));
      }
      if (anchors.length >= 5) {
        anchors.sort((left, right) => right.top.compareTo(left.top));
        return anchors;
      }
    }

    return const <_WeekdayAnchor>[];
  }

  int? _resolveWeekday(double top, List<_WeekdayAnchor> anchors) {
    _WeekdayAnchor? bestAnchor;
    double? bestDistance;
    for (final anchor in anchors) {
      final distance = (anchor.top - top).abs();
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestAnchor = anchor;
      }
    }
    if (bestAnchor == null || bestDistance == null) {
      return null;
    }

    final threshold = anchors.length > 1
        ? _weekdaySpacingThreshold(anchors)
        : 80.0;
    if (bestDistance > threshold) {
      return null;
    }
    return bestAnchor.weekday;
  }

  double _weekdaySpacingThreshold(List<_WeekdayAnchor> anchors) {
    var minSpacing = double.infinity;
    for (var i = 1; i < anchors.length; i++) {
      final spacing = (anchors[i - 1].top - anchors[i].top).abs();
      if (spacing > 0 && spacing < minSpacing) {
        minSpacing = spacing;
      }
    }

    if (minSpacing == double.infinity) {
      return 80.0;
    }
    return minSpacing * 0.65;
  }

  List<ParsedCourse> _pickPreferredCourses(
    List<ParsedCourse> primary,
    List<ParsedCourse> fallback,
  ) {
    if (primary.isEmpty) {
      return fallback;
    }
    if (fallback.isEmpty) {
      return primary;
    }
    return _courseSetScore(primary) >= _courseSetScore(fallback)
        ? primary
        : fallback;
  }

  int _courseSetScore(List<ParsedCourse> courses) {
    return courses.length * 100 +
        courses.where((course) => course.weekday != null).length * 20 +
        courses.where((course) => course.startSection != null).length * 15 +
        courses.where((course) => course.endSection != null).length * 15 +
        courses.where((course) => course.location?.isNotEmpty == true).length *
            5 +
        courses.where((course) => course.teacher?.isNotEmpty == true).length *
            5 +
        courses.fold<int>(0, (score, course) => score + course.weeks.length);
  }

  List<SectionTime> _extractSuggestedSectionTimes(
    String text,
    List<ParsedCourse> courses,
  ) {
    if (courses.isEmpty) {
      return const <SectionTime>[];
    }

    final sectionTimes = _extractSectionClockTimes(text);
    if (sectionTimes.isEmpty) {
      return const <SectionTime>[];
    }

    final usedRanges =
        courses
            .where(
              (course) =>
                  course.startSection != null && course.endSection != null,
            )
            .map(
              (course) =>
                  (start: course.startSection!, end: course.endSection!),
            )
            .toSet()
            .toList()
          ..sort((left, right) => left.start.compareTo(right.start));

    final suggestedSlots = <SectionTime>[];
    for (final range in usedRanges) {
      final startClock = sectionTimes[range.start];
      final endClock = sectionTimes[range.end];
      if (startClock == null || endClock == null) {
        continue;
      }
      suggestedSlots.add(
        SectionTime(
          startSection: range.start,
          endSection: range.end,
          startTime: startClock.startTime,
          endTime: endClock.endTime,
        ),
      );
    }

    return suggestedSlots;
  }

  Map<int, _SingleSectionClockTime> _extractSectionClockTimes(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final sectionTimes = <int, _SingleSectionClockTime>{};

    for (var i = 0; i + 2 < lines.length; i++) {
      final section = int.tryParse(lines[i]);
      final startTime = _normalizeClock(lines[i + 1]);
      final endTime = _normalizeClock(lines[i + 2]);
      if (section == null || startTime == null || endTime == null) {
        continue;
      }

      sectionTimes[section] = _SingleSectionClockTime(
        startTime: startTime,
        endTime: endTime,
      );
    }

    return sectionTimes;
  }

  String? _normalizeClock(String input) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input.trim());
    if (match == null) {
      return null;
    }

    final hour = match.group(1)!.padLeft(2, '0');
    final minute = match.group(2)!;
    return '$hour:$minute';
  }

  List<ParsedCourse> _dedupeCourses(Iterable<ParsedCourse> courses) {
    final coursesByKey = <String, ParsedCourse>{};
    for (final course in courses) {
      final key = [
        course.name,
        course.weekday,
        course.startSection,
        course.endSection,
      ].join('|');
      final existing = coursesByKey[key];
      if (existing == null || _courseScore(course) > _courseScore(existing)) {
        coursesByKey[key] = course;
      }
    }
    return coursesByKey.values.toList();
  }

  ParsedCourse? _tryParseBlock(
    String block, {
    String? inferredName,
    int? inferredWeekday,
  }) {
    final weekday = inferredWeekday ?? _matchWeekday(block);
    final section = _extractSectionRange(block);
    if (weekday == null || section == null) {
      return null;
    }

    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !RegExp(r'^第?\d+页$').hasMatch(line))
        .toList();
    if (lines.isEmpty) {
      return null;
    }

    final rawName = inferredName ?? _extractName(lines, block);
    final name = _resolveCourseName(rawName, block);
    if (name == null || name.trim().length < 2) {
      return null;
    }

    final teacher = _extractTeacher(block);
    final location = _extractLocation(block, lines, name, teacher);
    final note = _extractNote(lines, name, teacher, location);

    return ParsedCourse(
      name: name.trim(),
      teacher: teacher,
      location: location,
      weekday: weekday,
      startSection: section.start,
      endSection: section.end,
      weeks: _extractWeeks(block),
      note: note,
    );
  }

  bool _containsScheduleMarkers(String text) {
    return _matchWeekday(text) != null && _extractSectionRange(text) != null;
  }

  String _normalizeText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _normalizeLookupKey(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _resolveCourseName(String? rawName, String block) {
    final normalizedName = rawName?.trim();
    if (normalizedName != null &&
        normalizedName.isNotEmpty &&
        !_looksLikeGarbledCourseName(normalizedName)) {
      return normalizedName;
    }

    final courseCode = _extractCourseCode(block);
    final fallbackName = courseCode == null
        ? null
        : _courseTitleFallbackByCode[courseCode];
    if (fallbackName != null && fallbackName.isNotEmpty) {
      return fallbackName;
    }

    return normalizedName;
  }

  String? _extractCourseCode(String block) {
    final match = RegExp(
      r'(?:教学班[:：][^\n]*?-)?([A-Z]{2,4}\d{4})',
      caseSensitive: false,
    ).firstMatch(block);
    return match?.group(1)?.toUpperCase();
  }

  bool _looksLikeGarbledCourseName(String input) {
    if (input.isEmpty) {
      return true;
    }

    if (input.contains('�')) {
      return true;
    }

    const allowedExtraCharacters = <String>{
      ' ',
      '-',
      '_',
      '/',
      '(',
      ')',
      '（',
      '）',
      '·',
      '&',
      '.',
      '《',
      '》',
      'Ⅰ',
      'Ⅱ',
      'Ⅲ',
      'Ⅳ',
      'Ⅴ',
      'Ⅵ',
      'Ⅶ',
      'Ⅷ',
    };

    var unusualCharacterCount = 0;
    for (final rune in input.runes) {
      final character = String.fromCharCode(rune);
      final isChinese = rune >= 0x4E00 && rune <= 0x9FFF;
      final isAsciiLetterOrDigit =
          (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A);
      if (isChinese ||
          isAsciiLetterOrDigit ||
          allowedExtraCharacters.contains(character)) {
        continue;
      }
      unusualCharacterCount++;
    }

    return unusualCharacterCount > 0;
  }

  String? _extractName(List<String> lines, String block) {
    final weekdayMatch = RegExp(
      r'(周[一二三四五六日天]|星期[一二三四五六日天])',
    ).firstMatch(block);

    for (final line in lines) {
      if (_containsScheduleMarkers(line)) {
        final inlineMatch = RegExp(
          r'(周[一二三四五六日天]|星期[一二三四五六日天])',
        ).firstMatch(line);
        if (inlineMatch != null) {
          final prefix = line.substring(0, inlineMatch.start).trim();
          final cleaned = _cleanInlineName(prefix);
          if (cleaned.isNotEmpty) {
            return cleaned;
          }
        }
        continue;
      }

      if (_extractWeeks(line).isNotEmpty ||
          _looksLikeTeacher(line) ||
          _looksLikeLocation(line)) {
        continue;
      }

      return line;
    }

    if (weekdayMatch != null) {
      final prefix = block.substring(0, weekdayMatch.start).trim();
      final cleaned = _cleanInlineName(prefix);
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }

    return null;
  }

  String _cleanInlineName(String input) {
    return input
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[:：-]+$'), '')
        .trim();
  }

  String? _extractTeacher(String block) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    for (var index = 0; index < lines.length; index++) {
      final labeledMatch = RegExp(
        r'(?:教师|老师)[:：]\s*([^\s/]{1,20})',
      ).firstMatch(lines[index]);
      if (labeledMatch == null) {
        continue;
      }

      var candidate = labeledMatch.group(1) ?? '';
      if (index + 1 < lines.length) {
        final continuationMatch = RegExp(
          r'^([\u4e00-\u9fa5]{1,2})/',
        ).firstMatch(lines[index + 1]);
        if (continuationMatch != null) {
          candidate += continuationMatch.group(1) ?? '';
        }
      }

      return _cleanTeacher(candidate);
    }

    final match = RegExp(
      r'([\u4e00-\u9fa5]{1,4}(?:老师|教授|讲师))',
    ).firstMatch(block);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  String? _cleanTeacher(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final normalized = value.trim();
    final nameMatch = RegExp(r'^[\u4e00-\u9fa5]{1,4}').firstMatch(normalized);
    if (nameMatch != null) {
      return nameMatch.group(0);
    }

    final token = normalized.split('/').first.trim();
    return token.isEmpty ? null : token;
  }

  String? _extractLocation(
    String block,
    List<String> lines,
    String name,
    String? teacher,
  ) {
    final labeledMatch = RegExp(
      r'(?:场地|地点|教室)[:：]\s*([^/\s]+)',
      caseSensitive: false,
    ).firstMatch(block);
    if (labeledMatch != null) {
      return labeledMatch.group(1)?.trim();
    }

    for (final line in lines) {
      if (line == name || line == teacher) {
        continue;
      }
      if (_containsScheduleMarkers(line) || _extractWeeks(line).isNotEmpty) {
        continue;
      }
      if (_looksLikeLocation(line)) {
        return line;
      }
    }

    final tokens = block
        .split(RegExp(r'[\s\n]+'))
        .where((token) => token.isNotEmpty);
    for (final token in tokens) {
      if (token == name || token == teacher) {
        continue;
      }
      if (_looksLikeLocation(token) &&
          _matchWeekday(token) == null &&
          _extractSectionRange(token) == null &&
          _extractWeeks(token).isEmpty) {
        return token;
      }
    }

    return null;
  }

  String? _extractNote(
    List<String> lines,
    String name,
    String? teacher,
    String? location,
  ) {
    final notes = <String>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line == name || line == teacher || line == location) {
        continue;
      }
      if (_containsScheduleMarkers(line) || _extractWeeks(line).isNotEmpty) {
        continue;
      }
      if (index + 1 < lines.length &&
          _containsScheduleMarkers(lines[index + 1]) &&
          !_looksLikeTeacher(line) &&
          !_looksLikeLocation(line)) {
        continue;
      }
      if (_looksLikeTeacher(line) || _looksLikeLocation(line)) {
        continue;
      }
      notes.add(line);
    }

    return notes.isEmpty ? null : notes.join(' / ');
  }

  int? _matchWeekday(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), '');
    const mappings = <String, int>{
      '周一': 1,
      '星期一': 1,
      '周二': 2,
      '星期二': 2,
      '周三': 3,
      '星期三': 3,
      '周四': 4,
      '星期四': 4,
      '周五': 5,
      '星期五': 5,
      '周六': 6,
      '星期六': 6,
      '周日': 7,
      '星期日': 7,
      '星期天': 7,
      '周天': 7,
    };

    for (final entry in mappings.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  _SectionRange? _extractSectionRange(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), '');
    final rangeMatch = RegExp(
      r'第?(\d{1,2})[-~至](\d{1,2})节?',
    ).firstMatch(normalized);
    if (rangeMatch != null) {
      final start = int.tryParse(rangeMatch.group(1)!);
      final end = int.tryParse(rangeMatch.group(2)!);
      if (start != null && end != null) {
        return _SectionRange(start: start, end: end);
      }
    }

    final singleMatch = RegExp(r'第?(\d{1,2})节').firstMatch(normalized);
    if (singleMatch != null) {
      final section = int.tryParse(singleMatch.group(1)!);
      if (section != null) {
        return _SectionRange(start: section, end: section);
      }
    }

    return null;
  }

  List<int> _extractWeeks(String input) {
    final normalized = input
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('，', ',')
        .replaceAll('、', ',')
        .replaceAll('至', '-')
        .replaceAll('~', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-');

    final segmentPattern = RegExp(
      r'(?:第)?\d{1,2}(?:\s*-\s*\d{1,2})?(?:\s*,\s*\d{1,2}(?:\s*-\s*\d{1,2})?)*\s*周(?:\s*\((单|双)\))?(?:\s*[单双]周?)?',
    );
    final weeks = <int>{};

    for (final match in segmentPattern.allMatches(normalized)) {
      final segment = match.group(0)!;
      final isOdd = segment.contains('单');
      final isEven = segment.contains('双');
      final numbersOnly = segment
          .replaceAll('第', '')
          .replaceAll(RegExp(r'周|\(|\)|单|双'), '')
          .trim();

      for (final part in numbersOnly.split(',')) {
        final piece = part.trim();
        if (piece.isEmpty) {
          continue;
        }

        if (piece.contains('-')) {
          final range = piece
              .split('-')
              .map((value) => int.tryParse(value.trim()))
              .toList();
          if (range.length != 2 || range[0] == null || range[1] == null) {
            continue;
          }

          for (var week = range[0]!; week <= range[1]!; week++) {
            if (isOdd && week.isEven) {
              continue;
            }
            if (isEven && week.isOdd) {
              continue;
            }
            weeks.add(week);
          }
        } else {
          final week = int.tryParse(piece);
          if (week != null) {
            if (isOdd && week.isEven) {
              continue;
            }
            if (isEven && week.isOdd) {
              continue;
            }
            weeks.add(week);
          }
        }
      }
    }

    return weeks.toList()..sort();
  }

  bool _looksLikeTeacher(String line) {
    return line.contains('老师') ||
        line.contains('教授') ||
        line.contains('讲师') ||
        line.startsWith('教师');
  }

  bool _looksLikeLocation(String line) {
    return RegExp(
      r'(\d|[A-Z]-\d|教|楼|室|馆|机房|实验|校区|Room|Lab)',
      caseSensitive: false,
    ).hasMatch(line);
  }

  int _courseScore(ParsedCourse course) {
    return (course.teacher?.isNotEmpty == true ? 1 : 0) +
        (course.location?.isNotEmpty == true ? 1 : 0) +
        course.weeks.length +
        (course.note?.isNotEmpty == true ? 1 : 0);
  }
}

class PdfTextLineSnapshot {
  const PdfTextLineSnapshot({
    required this.text,
    required this.top,
    this.words = const <PdfTextWordSnapshot>[],
  });

  final String text;
  final double top;
  final List<PdfTextWordSnapshot> words;
}

class PdfTextWordSnapshot {
  const PdfTextWordSnapshot({required this.text, required this.top});

  final String text;
  final double top;
}

class _GridCourseBlock {
  const _GridCourseBlock({required this.title, required this.text});

  final String title;
  final String text;
}

class _WeekdayAnchor {
  const _WeekdayAnchor({required this.weekday, required this.top});

  final int weekday;
  final double top;
}

class _SectionRange {
  const _SectionRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _SingleSectionClockTime {
  const _SingleSectionClockTime({
    required this.startTime,
    required this.endTime,
  });

  final String startTime;
  final String endTime;
}
