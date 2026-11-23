import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../data/master_models.dart';
import '../data/master_repository.dart';
import '../../../school/data/school_repository.dart';
import '../../../school/presentation/school_times_screen.dart';

// ── Company settings ──────────────────────────────────────────────────────

/// Company details printed on payslips, EA forms and emails. (The logo is
/// managed on the website.)
class CompanySettingsScreen extends ConsumerWidget {
  const CompanySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(companySettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Company settings')),
      body: s.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(companySettingsProvider)),
        data: (settings) => _SettingsForm(settings: settings),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final CompanySettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final CompanySettings _s = widget.settings;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget field(String label, String value, ValueChanged<String> onChanged,
            {int maxLines = 1, TextInputType? keyboard, TextCapitalization caps = TextCapitalization.none}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            initialValue: value,
            maxLines: maxLines,
            keyboardType: keyboard,
            textCapitalization: caps,
            decoration: InputDecoration(labelText: label),
            onChanged: onChanged,
          ),
        );
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 0, 10),
          child: Text(t, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        );

    Color? swatch;
    if (CompanySettings.isHexColor(_s.brandColor)) {
      swatch = Color(int.parse('FF${_s.brandColor.substring(1)}', radix: 16));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const SchoolFeaturesSwitch(),
        heading('Company'),
        field('Legal name', _s.legalName, (v) => _s.legalName = v, caps: TextCapitalization.words),
        field('Display name (short)', _s.displayName, (v) => _s.displayName = v, caps: TextCapitalization.words),
        field('Registration no. (SSM)', _s.registrationNo, (v) => _s.registrationNo = v),
        field('Address', _s.address, (v) => _s.address = v, maxLines: 3),
        field('Phone', _s.phone, (v) => _s.phone = v, keyboard: TextInputType.phone),
        field('Website', _s.website, (v) => _s.website = v, keyboard: TextInputType.url),
        heading('Tax (for EA forms)'),
        field('Employer tax no. (E number)', _s.employerTaxNo, (v) => _s.employerTaxNo = v),
        field('LHDN branch', _s.taxBranch, (v) => _s.taxBranch = v, caps: TextCapitalization.words),
        heading('HR officer (signs documents)'),
        field('Name', _s.hrOfficerName, (v) => _s.hrOfficerName = v, caps: TextCapitalization.words),
        field('Position', _s.hrOfficerPosition, (v) => _s.hrOfficerPosition = v, caps: TextCapitalization.words),
        heading('Branding'),
        Row(children: [
          Expanded(
            child: TextFormField(
              initialValue: _s.brandColor,
              decoration: const InputDecoration(labelText: 'Brand colour (#RRGGBB)'),
              onChanged: (v) => setState(() => _s.brandColor = v.trim()),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: swatch ?? theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text('The company logo is changed on the website.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final problem = _s.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(masterRepositoryProvider).saveCompanySettings(_s);
      messenger.showSnackBar(const SnackBar(content: Text('Company settings saved')));
    } catch (e) {
      _error = ApiException.from(e).message;
    }
    if (mounted) setState(() => _saving = false);
  }
}

// ── Statutory rates (view only) ───────────────────────────────────────────

/// EPF / SOCSO / EIS / PCB rate sets by effective date. Editing the rate
/// tables is done on the website.
class StatutoryRatesScreen extends ConsumerWidget {
  const StatutoryRatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(rateSetsProvider);
    final theme = Theme.of(context);
    String pct(double v) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v}%';
    String upTo(double? v) => v == null ? 'and above' : 'up to ${Fmt.money(v)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Statutory rates')),
      body: sets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(rateSetsProvider)),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text('Payroll uses the newest set whose effective date is on or before the payroll month. '
                'Rate tables are edited on the website.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final s in list) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  shape: const Border(),
                  initiallyExpanded: s.isCurrent,
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('From ${Fmt.date(s.effectiveFrom)}'
                      '${s.isCurrent ? ' · in use now' : ''} · ${s.payrollsUsing} payslips'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row('EPF employee', pct(s.epfEmployee)),
                    _row('EPF employer', '${pct(s.epfEmployer)} up to ${Fmt.money(s.epfThreshold)}, '
                        '${pct(s.epfEmployerAbove)} above'),
                    _row('EIS employee / employer', '${pct(s.eisEmployee)} / ${pct(s.eisEmployer)}'),
                    _row('EIS wage ceiling', Fmt.money(s.eisCeiling)),
                    _row('PCB personal relief', Fmt.money(s.taxRelief)),
                    if (s.socsoBands.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('SOCSO (${s.socsoBands.length} bands)', style: theme.textTheme.titleSmall),
                      for (final (limit, emp, er) in s.socsoBands.take(6))
                        _row('Wage ${upTo(limit)}', '${Fmt.money(emp)} / ${Fmt.money(er)}'),
                      if (s.socsoBands.length > 6)
                        Text('… ${s.socsoBands.length - 6} more bands (employee / employer)',
                            style: theme.textTheme.bodySmall),
                    ],
                    if (s.taxBands.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Income tax bands', style: theme.textTheme.titleSmall),
                      for (final (limit, rate) in s.taxBands) _row('Chargeable income ${upTo(limit)}', pct(rate)),
                    ],
                    if (s.notes?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      Text(s.notes!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(k)),
          const SizedBox(width: 8),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}


/// School features on / off for this company (schools only). Saved straight away; the School
/// section (More tab) appears or disappears at once.
class SchoolFeaturesSwitch extends ConsumerStatefulWidget {
  const SchoolFeaturesSwitch({super.key});

  @override
  ConsumerState<SchoolFeaturesSwitch> createState() => _SchoolFeaturesSwitchState();
}

class _SchoolFeaturesSwitchState extends ConsumerState<SchoolFeaturesSwitch> {
  bool _saving = false;

  Future<void> _set(bool on) async {
    setState(() => _saving = true);
    try {
      await ref.read(schoolRepositoryProvider).setEnabled(on);
      ref.invalidate(schoolMeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(on ? 'School features are on. See More → School.' : 'School features are off.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiException.from(e).message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(schoolMeProvider);
    final on = me.valueOrNull?.enabled ?? false;
    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(children: [
        SwitchListTile(
          secondary: const Icon(Icons.school_outlined),
          title: const Text('School features'),
          subtitle: const Text('Classes, children, parent logins, attendance, daily reports, messages and fees'),
          value: on,
          onChanged: _saving || me.isLoading ? null : _set,
        ),
        if (on) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('School day timings'),
            subtitle: const Text('Start, late, automatic absent and check-out'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchoolTimesScreen())),
          ),
        ],
      ]),
    );
  }
}
