import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/notebook_widgets.dart';
import '../../inventory/domain/models.dart';
import '../domain/csv_parser.dart';
import '../domain/import_plan.dart';

/// A CSV file chosen for import.
class ImportSource {
  const ImportSource({required this.name, required this.text});

  final String name;
  final String text;
}

/// Opens the system file picker and reads the chosen CSV as UTF-8.
Future<ImportSource?> pickCsvFile() async {
  const group = XTypeGroup(
    label: 'CSV',
    extensions: ['csv', 'txt'],
    mimeTypes: ['text/csv', 'text/comma-separated-values', 'text/plain'],
  );
  final file = await openFile(acceptedTypeGroups: const [group]);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return ImportSource(
    name: file.name.isEmpty ? 'import.csv' : file.name,
    text: utf8.decode(bytes, allowMalformed: true),
  );
}

/// CSV import flow (IMPORT-01): pick a file, map its columns, review the
/// validated rows with duplicate warnings, import, and read the report.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, this.pickFile = pickCsvFile, this.initial});

  final Future<ImportSource?> Function() pickFile;

  /// Skips the picker; used by tests and by share-to-app entry points.
  final ImportSource? initial;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  ImportSource? _source;
  List<List<String>> _table = const [];
  bool _hasHeader = true;
  Map<ImportField, int> _mapping = {};
  ImportTarget _target = ImportTarget.chemicals;
  bool _importDuplicates = false;
  bool _picking = false;
  bool _running = false;
  int _done = 0;
  int _total = 0;
  _ImportResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _load(initial);
  }

  List<String> get _headers {
    if (_table.isEmpty) return const [];
    final width = _table
        .map((row) => row.length)
        .reduce((a, b) => a > b ? a : b);
    return [
      for (var index = 0; index < width; index++)
        _hasHeader && index < _table.first.length
            ? _table.first[index].trim()
            : 'column ${index + 1}',
    ];
  }

  /// Parses [source] and resets the mapping. Callers wrap it in setState
  /// when the widget is already built.
  void _load(ImportSource source) {
    final table = parseCsv(source.text);
    _source = source;
    _result = null;
    if (table.isEmpty) {
      _table = const [];
      _error = 'The file has no rows.';
      return;
    }
    final hasHeader = looksLikeHeader(table.first);
    final mapping = hasHeader
        ? autoMapHeaders(table.first)
        : <ImportField, int>{};
    _table = table;
    _hasHeader = hasHeader;
    _mapping = mapping;
    _target = mapping.containsKey(ImportField.type)
        ? ImportTarget.auto
        : ImportTarget.chemicals;
    _error = null;
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final source = await widget.pickFile();
      if (!mounted) return;
      if (source != null) setState(() => _load(source));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  List<ImportRow> _rows(InventoryState state) => _table.isEmpty
      ? const []
      : buildImportRows(
          rows: _table,
          mapping: _mapping,
          target: _target,
          hasHeader: _hasHeader,
          existingChemicals: state.chemicals,
          existingApparatus: state.apparatus,
        );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final rows = _rows(state);
    final summary = ImportSummary.of(rows);
    final result = _result;
    final importable = rows
        .where(
          (row) => !row.hasErrors && (_importDuplicates || !row.isDuplicate),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('import CSV')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverList.list(
              children: [
                if (result != null)
                  _ReportCard(
                    result: result,
                    fileName: _source?.name ?? 'import.csv',
                    onShare: _shareReport,
                    onDone: () => Navigator.of(context).maybePop(),
                    onImportMore: () => setState(() {
                      _result = null;
                      _source = null;
                      _table = const [];
                    }),
                  )
                else ...[
                  _FileCard(
                    source: _source,
                    rowCount: _table.isEmpty
                        ? 0
                        : _table.length - (_hasHeader ? 1 : 0),
                    picking: _picking,
                    error: _error,
                    onPick: _running ? null : _pick,
                  ),
                  if (_table.isNotEmpty) ...[
                    const SizedBox(height: 13),
                    _MappingCard(
                      headers: _headers,
                      hasHeader: _hasHeader,
                      mapping: _mapping,
                      target: _target,
                      enabled: !_running,
                      onHeaderChanged: (value) => setState(() {
                        _hasHeader = value;
                        if (value) _mapping = autoMapHeaders(_table.first);
                      }),
                      onTargetChanged: (value) =>
                          setState(() => _target = value),
                      onFieldMapped: (field, column) => setState(() {
                        if (column == null) {
                          _mapping.remove(field);
                        } else {
                          _mapping[field] = column;
                        }
                      }),
                    ),
                    const SizedBox(height: 13),
                    _SummaryCard(
                      summary: summary,
                      importDuplicates: _importDuplicates,
                      enabled: !_running,
                      onImportDuplicates: (value) =>
                          setState(() => _importDuplicates = value),
                    ),
                    const SizedBox(height: 8),
                    const PageHeading('preview', fontSize: 27),
                  ],
                ],
              ],
            ),
          ),
          if (result == null && _table.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => _RowTile(
                  row: rows[index],
                  skipped:
                      rows[index].hasErrors ||
                      (rows[index].isDuplicate && !_importDuplicates),
                ),
              ),
            ),
          if (result == null && _table.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_running) ...[
                      LinearProgressIndicator(
                        value: _total == 0 ? null : _done / _total,
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton.icon(
                      key: const Key('import-submit'),
                      onPressed: _running || importable.isEmpty
                          ? null
                          : () => _run(importable),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: _running
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _running
                            ? 'Importing $_done of $_total…'
                            : importable.isEmpty
                            ? 'Nothing to import'
                            : 'Import ${importable.length} item${importable.length == 1 ? '' : 's'}',
                      ),
                    ),
                    if (summary.errors > 0 || summary.duplicates > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (summary.errors > 0)
                            '${summary.errors} row${summary.errors == 1 ? '' : 's'} with errors will be skipped',
                          if (summary.duplicates > 0 && !_importDuplicates)
                            '${summary.duplicates} duplicate${summary.duplicates == 1 ? '' : 's'} will be skipped',
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.mutedInkColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _run(List<ImportRow> rows) async {
    final allRows = _rows(ref.read(inventoryProvider));
    final problems = <(ImportRow, String)>[
      for (final row in allRows)
        if (row.hasErrors)
          (row, row.issues.where((issue) => issue.isError).join('; '))
        else if (row.isDuplicate && !_importDuplicates)
          (row, 'skipped as duplicate of ${row.duplicates.first.name}'),
    ];
    setState(() {
      _running = true;
      _done = 0;
      _total = rows.length;
    });
    final controller = ref.read(inventoryProvider.notifier);
    var imported = 0;
    for (final row in rows) {
      try {
        if (row.kind == ItemKind.chemical) {
          await controller.addChemical(
            name: row.name,
            formula: row.subtitle,
            unit: row.unit,
            quantity: row.quantity,
            threshold: row.threshold,
            notes: row.notes,
            details: row.details,
          );
        } else {
          await controller.addApparatus(
            name: row.name,
            category: row.subtitle,
            quantity: row.quantity,
            threshold: row.threshold,
            notes: row.notes,
            details: row.gear,
          );
        }
        imported++;
      } catch (error) {
        problems.add((row, friendlyErrorMessage(error)));
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    problems.sort((a, b) => a.$1.line.compareTo(b.$1.line));
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = _ImportResult(imported: imported, problems: problems);
    });
  }

  Future<void> _shareReport() async {
    final result = _result;
    if (result == null) return;
    final report = buildImportReport(
      fileName: _source?.name ?? 'import.csv',
      imported: result.imported,
      problems: result.problems,
    );
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/lab-wizard-import-report.txt');
      await file.writeAsString(report, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Lab Wizard import report',
          text: 'Lab Wizard import report',
          files: [XFile(file.path, mimeType: 'text/plain')],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share: ${friendlyErrorMessage(error)}'),
        ),
      );
    }
  }
}

class _ImportResult {
  const _ImportResult({required this.imported, required this.problems});

  final int imported;
  final List<(ImportRow, String)> problems;
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.source,
    required this.rowCount,
    required this.picking,
    required this.error,
    required this.onPick,
  });

  final ImportSource? source;
  final int rowCount;
  final bool picking;
  final String? error;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading('file', fontSize: 27, trailing: SizedBox.shrink()),
          if (source == null)
            Text(
              'Pick a CSV file. The app\'s own "Share inventory CSV" export '
              'imports directly; other files can be mapped column by column '
              'in the next step.',
              style: TextStyle(color: context.mutedInkColor),
            )
          else
            Text(
              '${source!.name} · $rowCount data row${rowCount == 1 ? '' : 's'}',
              key: const Key('import-file-summary'),
            ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error!, style: TextStyle(color: context.marginRedColor)),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('import-pick'),
            onPressed: picking ? null : onPick,
            icon: picking
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_outlined),
            label: Text(
              source == null ? 'Choose CSV file' : 'Choose another file',
            ),
          ),
        ],
      ),
    );
  }
}

class _MappingCard extends StatelessWidget {
  const _MappingCard({
    required this.headers,
    required this.hasHeader,
    required this.mapping,
    required this.target,
    required this.enabled,
    required this.onHeaderChanged,
    required this.onTargetChanged,
    required this.onFieldMapped,
  });

  final List<String> headers;
  final bool hasHeader;
  final Map<ImportField, int> mapping;
  final ImportTarget target;
  final bool enabled;
  final ValueChanged<bool> onHeaderChanged;
  final ValueChanged<ImportTarget> onTargetChanged;
  final void Function(ImportField field, int? column) onFieldMapped;

  @override
  Widget build(BuildContext context) {
    final fields = ImportField.values.where((field) {
      if (field == ImportField.type) return target == ImportTarget.auto;
      if (target == ImportTarget.chemicals) return !field.apparatusOnly;
      if (target == ImportTarget.apparatus) return !field.chemicalOnly;
      return true;
    });
    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeading(
            'columns',
            fontSize: 27,
            trailing: SizedBox.shrink(),
          ),
          SegmentedButton<ImportTarget>(
            key: const Key('import-target'),
            segments: const [
              ButtonSegment(
                value: ImportTarget.chemicals,
                label: Text('chemicals'),
              ),
              ButtonSegment(
                value: ImportTarget.apparatus,
                label: Text('apparatus'),
              ),
              ButtonSegment(value: ImportTarget.auto, label: Text('by type')),
            ],
            selected: {target},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (values) => onTargetChanged(values.first)
                : null,
          ),
          SwitchListTile(
            key: const Key('import-has-header'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('first row is a header'),
            value: hasHeader,
            onChanged: enabled ? onHeaderChanged : null,
          ),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      field == ImportField.name || field == ImportField.type
                          ? '${field.label} *'
                          : field.label,
                      style: TextStyle(
                        color: context.mutedInkColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: Key('import-map-${field.name}'),
                        isExpanded: true,
                        isDense: true,
                        value: mapping[field] ?? -1,
                        style: TextStyle(color: context.inkColor, fontSize: 14),
                        items: [
                          DropdownMenuItem(
                            value: -1,
                            child: Text(
                              'not imported',
                              style: TextStyle(color: context.mutedInkColor),
                            ),
                          ),
                          for (var index = 0; index < headers.length; index++)
                            DropdownMenuItem(
                              value: index,
                              child: Text(
                                headers[index].isEmpty
                                    ? 'column ${index + 1}'
                                    : headers[index],
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: enabled
                            ? (value) => onFieldMapped(
                                field,
                                value == null || value < 0 ? null : value,
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.importDuplicates,
    required this.enabled,
    required this.onImportDuplicates,
  });

  final ImportSummary summary;
  final bool importDuplicates;
  final bool enabled;
  final ValueChanged<bool> onImportDuplicates;

  @override
  Widget build(BuildContext context) {
    return NotebookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _Count(
                key: const Key('import-count-ready'),
                label: 'ready',
                value: summary.ready,
                color: context.healthyColor,
              ),
              _Count(
                label: 'with warnings',
                value: summary.withWarnings,
                color: context.lowColor,
              ),
              _Count(
                key: const Key('import-count-duplicates'),
                label: 'duplicates',
                value: summary.duplicates,
                color: context.lowColor,
              ),
              _Count(
                key: const Key('import-count-errors'),
                label: 'errors',
                value: summary.errors,
                color: context.marginRedColor,
              ),
            ],
          ),
          SwitchListTile(
            key: const Key('import-duplicates'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('import duplicates too'),
            subtitle: const Text(
              'Rows that match an item already on the shelf are skipped '
              'unless this is on.',
            ),
            value: importDuplicates,
            onChanged: enabled ? onImportDuplicates : null,
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: TextStyle(
              color: value == 0 ? context.mutedInkColor : color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          TextSpan(
            text: label,
            style: TextStyle(color: context.mutedInkColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.skipped});

  final ImportRow row;
  final bool skipped;

  @override
  Widget build(BuildContext context) {
    final color = row.hasErrors
        ? context.marginRedColor
        : row.isDuplicate || row.hasWarnings
        ? context.lowColor
        : context.healthyColor;
    final icon = row.hasErrors
        ? Icons.error_outline
        : row.isDuplicate
        ? Icons.content_copy_outlined
        : row.hasWarnings
        ? Icons.warning_amber_outlined
        : Icons.check_circle_outline;
    final notes = [
      for (final match in row.duplicates)
        'matches ${match.name} (${match.reason})',
      ...row.issues.map((issue) => issue.message),
    ];
    return ListTile(
      key: Key('import-row-${row.line}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        row.summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          decoration: skipped ? TextDecoration.lineThrough : null,
          color: skipped ? context.mutedInkColor : context.inkColor,
        ),
      ),
      subtitle: notes.isEmpty
          ? Text(
              'line ${row.line}'
              '${row.kind == null ? '' : ' · ${row.kind!.name}'}',
            )
          : Text('line ${row.line} · ${notes.join(' · ')}'),
      trailing: skipped
          ? Text(
              'skip',
              style: TextStyle(
                fontFamily: 'Caveat',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.mutedInkColor,
              ),
            )
          : null,
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.result,
    required this.fileName,
    required this.onShare,
    required this.onDone,
    required this.onImportMore,
  });

  final _ImportResult result;
  final String fileName;
  final VoidCallback onShare;
  final VoidCallback onDone;
  final VoidCallback onImportMore;

  @override
  Widget build(BuildContext context) {
    final problems = result.problems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotebookCard(
          key: const Key('import-report'),
          tape: NotebookTape.yellow,
          accent: problems.isEmpty ? context.healthyColor : context.lowColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                'import finished',
                fontSize: 27,
                trailing: SizedBox.shrink(),
              ),
              Text(
                '${result.imported} item${result.imported == 1 ? '' : 's'} '
                'imported from $fileName'
                '${problems.isEmpty ? '.' : ' · ${problems.length} not imported.'}',
              ),
              if (problems.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final (row, reason) in problems.take(50))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'line ${row.line}: ${row.summary} — $reason',
                      style: TextStyle(
                        color: context.mutedInkColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (problems.length > 50)
                  Text(
                    '…and ${problems.length - 50} more in the shared report.',
                    style: TextStyle(
                      color: context.mutedInkColor,
                      fontSize: 13,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (problems.isNotEmpty)
                    OutlinedButton.icon(
                      key: const Key('import-share-report'),
                      onPressed: onShare,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share report'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onImportMore,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Import another file'),
                  ),
                  FilledButton.icon(
                    onPressed: onDone,
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
