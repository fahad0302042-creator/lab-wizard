/// Minimal RFC 4180 CSV reader used by the Android import (IMPORT-01).
///
/// Handles quoted cells, doubled quotes, embedded line breaks, CR/LF line
/// endings, a UTF-8 byte-order mark and the common `;` / tab delimiters that
/// spreadsheet exports use in some locales.
library;

/// Splits [text] into rows of cells. Empty lines are dropped.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  var source = text;
  if (source.startsWith('\uFEFF')) source = source.substring(1);
  final separator = delimiter ?? detectDelimiter(source);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var cellStarted = false;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
    cellStarted = false;
  }

  void endRow() {
    if (cellStarted || row.isNotEmpty) endCell();
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (quoted) {
      if (char == '"') {
        final next = index + 1 < source.length ? source[index + 1] : null;
        if (next == '"') {
          cell.write('"');
          index++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
      continue;
    }
    if (char == '"') {
      quoted = true;
      cellStarted = true;
    } else if (char == separator) {
      cellStarted = true;
      endCell();
      cellStarted = true;
    } else if (char == '\r') {
      if (index + 1 < source.length && source[index + 1] == '\n') index++;
      endRow();
    } else if (char == '\n') {
      endRow();
    } else {
      cell.write(char);
      cellStarted = true;
    }
  }
  endRow();
  return rows;
}

/// Picks the delimiter that appears most often on the first line.
String detectDelimiter(String text) {
  final firstBreak = text.indexOf(RegExp(r'\r?\n'));
  final firstLine = firstBreak < 0 ? text : text.substring(0, firstBreak);
  var best = ',';
  var bestCount = -1;
  for (final candidate in const [',', ';', '\t', '|']) {
    final count = _countOutsideQuotes(firstLine, candidate);
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

int _countOutsideQuotes(String line, String needle) {
  var count = 0;
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (char == '"') {
      quoted = !quoted;
    } else if (!quoted && char == needle) {
      count++;
    }
  }
  return count;
}
