import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/school_admin.dart';
import '../data/school_models.dart' show ymdToDate, dateToYmd;
import 'school_widgets.dart' show phoneText;

// Form building blocks for the school setup screens (children, parents, families): every field
// is its own outlined box with space around it, dates included.

/// Space between form fields.
const formGap = SizedBox(height: 14);

/// [children] with [formGap] between them.
List<Widget> spaced(List<Widget> children) => [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) formGap, children[i]],
    ];

/// Text box without the "0/150" counter under it (the limit still applies).
InputDecoration boxDecoration(String label, {String? hint, String? helper, IconData? icon}) => InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      prefixIcon: icon == null ? null : Icon(icon),
      counterText: '',
    );

/// Small grey section title: "HEALTH AND SAFETY".
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.subtitle});
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: .6, color: theme.colorScheme.primary)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ]),
    );
  }
}

/// A date in an outlined box like the text fields: label, the date, a calendar icon, and ✕ to clear.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.initialDate,
    this.icon = Icons.cake_outlined,
  });

  final String label;
  /// yyyy-MM-dd or null.
  final String? value;
  final ValueChanged<String?> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  /// Where the calendar opens when no date is set.
  final DateTime? initialDate;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final set = value != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        var start = set ? ymdToDate(value!) : (initialDate ?? lastDate);
        if (start.isAfter(lastDate)) start = lastDate;
        if (start.isBefore(firstDate)) start = firstDate;
        final d = await showDatePicker(context: context, initialDate: start, firstDate: firstDate, lastDate: lastDate);
        if (d != null) onChanged(dateToYmd(d));
      },
      child: InputDecorator(
        isEmpty: !set,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Choose a date',
          prefixIcon: Icon(icon),
          suffixIcon: set
              ? IconButton(icon: const Icon(Icons.close), tooltip: 'Clear', onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_month_outlined),
        ),
        child: set ? Text(DateFormat('d MMM yyyy').format(ymdToDate(value!))) : null,
      ),
    );
  }
}

/// Bottom sheet: a searchable list. Returns the chosen item, or null if closed.
Future<T?> pickFromList<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) label,
  String Function(T)? subtitle,
  String searchHint = 'Search',
  List<Widget> actions = const [],
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _PickSheet<T>(
          title: title, items: items, label: label, subtitle: subtitle, searchHint: searchHint, actions: actions),
    );

class _PickSheet<T> extends StatefulWidget {
  const _PickSheet({required this.title, required this.items, required this.label, this.subtitle,
      required this.searchHint, required this.actions});
  final String title;
  final List<T> items;
  final String Function(T) label;
  final String Function(T)? subtitle;
  final String searchHint;
  final List<Widget> actions;

  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final shown = widget.items
        .where((i) => q.isEmpty ||
            widget.label(i).toLowerCase().contains(q) ||
            (widget.subtitle?.call(i).toLowerCase().contains(q) ?? false))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (widget.items.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: widget.searchHint, isDense: true),
              ),
            ),
          ...widget.actions,
          Flexible(
            child: shown.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('Nothing matches.'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final item = shown[i];
                      final sub = widget.subtitle?.call(item);
                      return ListTile(
                        title: Text(widget.label(item)),
                        subtitle: sub == null || sub.isEmpty ? null : Text(sub),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// "Mother: [Mounika ▾]" — one parent slot. Tapping lists the parents saved with this
/// relationship (searchable), "+ Add a new mother", and "None".
class ParentSlot extends StatelessWidget {
  const ParentSlot({
    super.key,
    required this.relationship,
    required this.parents,
    required this.selectedId,
    required this.onChanged,
    required this.onAddNew,
    this.label,
  });

  /// "Mother" or "Father".
  final String relationship;
  final List<ParentRecord> parents;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  /// Opens the parent form for a new mother/father; returns the new parent's id.
  final Future<int?> Function() onAddNew;
  /// Box label (default: the relationship), e.g. "Mother *".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final selected = parents.where((p) => p.id == selectedId).firstOrNull;
    final lower = relationship.toLowerCase();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        const none = -1, addNew = -2;
        final choices = parents.where((p) => p.relationship == relationship && (p.isActive || p.id == selectedId)).toList();
        final picked = await pickFromList<int>(
          context,
          title: 'Choose the $lower',
          items: [for (final p in choices) p.id],
          label: (id) => parents.firstWhere((p) => p.id == id).fullName,
          subtitle: (id) {
            final p = parents.firstWhere((x) => x.id == id);
            return [
              if (p.phone != null) phoneText(p.phone),
              if (p.children.isNotEmpty) 'Children: ${p.children.map((c) => c.fullName).join(', ')}',
            ].join(' · ');
          },
          searchHint: 'Search by name, phone or child',
          actions: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: Text('Add a new $lower'),
              onTap: () => Navigator.of(context).pop(addNew),
            ),
            if (selectedId != null)
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: Text('No $lower'),
                onTap: () => Navigator.of(context).pop(none),
              ),
            const Divider(height: 1),
          ],
        );
        if (picked == null) return;
        if (picked == none) {
          onChanged(null);
        } else if (picked == addNew) {
          final id = await onAddNew();
          if (id != null) onChanged(id);
        } else {
          onChanged(picked);
        }
      },
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: label ?? relationship,
          hintText: 'Not set — tap to choose or add',
          prefixIcon: Icon(relationship == 'Mother' ? Icons.face_3_outlined : Icons.face_6_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: selected == null
            ? null
            : Text(selected.phone == null ? selected.fullName : '${selected.fullName} · ${phoneText(selected.phone)}',
                overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// A required parent box ("Mother" / "Father") with "No mother on record" under it for single
/// parents. Ticking the box hides the picker: the child is saved with only the other parent.
class RequiredParentSlot extends StatelessWidget {
  const RequiredParentSlot({
    super.key,
    required this.relationship,
    required this.parents,
    required this.selectedId,
    required this.none,
    required this.onChanged,
    required this.onNoneChanged,
    required this.onAddNew,
    this.error,
  });

  /// "Mother" or "Father".
  final String relationship;
  final List<ParentRecord> parents;
  final int? selectedId;
  /// "No mother / father on record" is ticked.
  final bool none;
  final ValueChanged<int?> onChanged;
  final ValueChanged<bool> onNoneChanged;
  final Future<int?> Function() onAddNew;
  /// Shown under the picker, e.g. "Choose the father, or tick No father on record".
  final String? error;

  @override
  Widget build(BuildContext context) {
    final lower = relationship.toLowerCase();
    final other = relationship == 'Mother' ? 'father' : 'mother';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!none) ...[
        ParentSlot(
          relationship: relationship,
          label: '$relationship *',
          parents: parents,
          selectedId: selectedId,
          onChanged: onChanged,
          onAddNew: onAddNew,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
      ],
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: none,
        title: Text('No $lower on record'),
        subtitle: Text('Single $other: only the $other is linked'),
        onChanged: (v) => onNoneChanged(v ?? false),
      ),
    ]);
  }
}
