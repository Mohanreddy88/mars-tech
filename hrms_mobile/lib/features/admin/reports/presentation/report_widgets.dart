import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/file_opener.dart';

/// Chart building blocks for the report screens, all single-series in the
/// brand colour: one hue, the value always written as text next to the
/// mark (identity never by colour alone), thin bars with 4px rounded data
/// ends anchored at a shared baseline, recessive track instead of grid lines.

/// Horizontal bars: one row per category, label above, value at the end.
/// [max] fixes the scale (e.g. 100 for percentages); default = largest value.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.rows, required this.format, this.max});

  /// (label, value)
  final List<(String, double)> rows;
  final String Function(double) format;
  final double? max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final top = max ?? rows.fold<double>(0, (m, r) => r.$2 > m ? r.$2 : m);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text('No data', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      );
    }
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              label: '$label: ${format(value)}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(label, style: text.bodyMedium, overflow: TextOverflow.ellipsis)),
                    Text(format(value), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 4),
                  // Track (recessive) + bar from the shared left baseline.
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: top <= 0 ? 0 : (value / top).clamp(0, 1).toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Vertical bars over time. Tap a bar to select it (the mobile stand-in for
/// hover); [details] renders the selected point below the chart.
class ColumnChart extends StatefulWidget {
  const ColumnChart({
    super.key,
    required this.labels,
    required this.values,
    required this.format,
    required this.details,
    this.height = 160,
  });

  final List<String> labels;
  final List<double> values;
  final String Function(double) format;
  final Widget Function(int index) details;
  final double height;

  @override
  State<ColumnChart> createState() => _ColumnChartState();
}

class _ColumnChartState extends State<ColumnChart> {
  late int _selected = widget.values.isEmpty ? -1 : widget.values.length - 1; // latest month

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final values = widget.values;
    if (values.isEmpty) {
      return Text('No data', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant));
    }
    final top = values.reduce((a, b) => a > b ? a : b);
    final selected = _selected.clamp(0, values.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  // Hit target is the whole column, wider than the bar.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selected = i),
                    child: Semantics(
                      button: true,
                      selected: i == selected,
                      label: '${widget.labels[i]}: ${widget.format(values[i])}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.5,
                            child: Container(
                              height: top <= 0 ? 0 : (values[i] / top) * (widget.height - 8),
                              decoration: BoxDecoration(
                                color: i == selected ? scheme.primary : scheme.primary.withValues(alpha: 0.45),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: scheme.outlineVariant), // baseline
        const SizedBox(height: 4),
        Row(children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Text(
                widget.labels[i].split(' ').first, // "Nov 2026" -> "Nov"
                textAlign: TextAlign.center,
                style: text.labelSmall?.copyWith(
                  color: i == selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: i == selected ? FontWeight.w700 : null,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        widget.details(selected),
      ],
    );
  }
}

/// Grid of labelled figures (stat tiles).
class FigureGrid extends StatelessWidget {
  const FigureGrid(this.figures, {super.key});

  /// (label, value)
  final List<(String, String)> figures;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (label, value) in figures)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Titled card section.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null)
              Text(subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// App-bar action: download an Excel export and open the share sheet.
class ExcelExportButton extends StatefulWidget {
  const ExcelExportButton({super.key, required this.download});

  final Future<(List<int>, String)> Function() download;

  @override
  State<ExcelExportButton> createState() => _ExcelExportButtonState();
}

class _ExcelExportButtonState extends State<ExcelExportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Export to Excel',
        onPressed: _busy ? null : _export,
        icon: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.file_download_outlined),
      );

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final (bytes, name) = await widget.download();
      final file = await FileOpener.save(bytes, name);
      await FileOpener.share(file,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', subject: name);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
