/// Spreadsheet-safe CSV writing (REPORT-05).
///
/// * RFC 4180 quoting: cells containing the delimiter, quotes or line breaks
///   are wrapped in quotes with inner quotes doubled.
/// * Formula-injection guard: a cell whose text starts with `=`, `+`, `-`,
///   `@`, a tab or a carriage return is prefixed with an apostrophe so Excel,
///   LibreOffice and Sheets show it as text instead of evaluating it
///   (`=HYPERLINK(...)`, `-2+3+cmd|' /C calc'!A0`, …). Numbers passed as
///   [num] are written bare, so negative amounts stay numeric.
/// * CRLF line endings and an optional UTF-8 byte-order mark, which is what
///   makes Excel open the file with the right encoding and columns.
library;

import 'dart:convert';
import 'dart:typed_data';

const _dangerousStart = ['=', '+', '-', '@', '\t', '\r'];

/// One cell, escaped. Null becomes an empty cell.
String csvCell(Object? value, {String delimiter = ','}) {
  if (value == null) return '';
  if (value is num) {
    if (value.isNaN || value.isInfinite) return '';
    return value == value.roundToDouble() && value.abs() < 1e15
        ? value.toInt().toString()
        : value.toString();
  }
  var text = value is DateTime ? value.toIso8601String() : value.toString();
  var guarded = false;
  if (text.isNotEmpty && _dangerousStart.contains(text[0])) {
    text = "'$text";
    guarded = true;
  }
  final needsQuotes =
      guarded ||
      text.contains(delimiter) ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r') ||
      text.startsWith(' ') ||
      text.endsWith(' ');
  if (!needsQuotes) return text;
  return '"${text.replaceAll('"', '""')}"';
}

/// A whole document: header row plus [rows], CRLF-terminated lines.
String csvDocument(
  List<Object?> headers,
  Iterable<List<Object?>> rows, {
  String delimiter = ',',
  bool byteOrderMark = true,
}) {
  final buffer = StringBuffer();
  if (byteOrderMark) buffer.write('\uFEFF');
  void line(List<Object?> cells) {
    buffer.write(
      cells.map((cell) => csvCell(cell, delimiter: delimiter)).join(delimiter),
    );
    buffer.write('\r\n');
  }

  line(headers);
  rows.forEach(line);
  return buffer.toString();
}

/// UTF-8 bytes of [csv] for writing to a file or sharing.
Uint8List csvBytes(String csv) => Uint8List.fromList(utf8.encode(csv));

/// Undoes the injection guard when reading our own exports back
/// (`'=abc` → `=abc`); other apostrophes are left alone.
String csvUnguard(String cell) {
  if (cell.length >= 2 && cell[0] == "'" && _dangerousStart.contains(cell[1])) {
    return cell.substring(1);
  }
  return cell;
}
