import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../profile/data/profile_repository.dart' show banksProvider;
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Add (employee == null) or edit an employee — the web app's employee form.
/// Pops `true` when saved.
class EmployeeFormScreen extends ConsumerStatefulWidget {
  const EmployeeFormScreen({super.key, this.employee});

  final EmployeeSummary? employee;

  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  static const _dialCodes = ['+60', '+65', '+62', '+66', '+63', '+84', '+91', '+92', '+880', '+977', '+86', '+44', '+1'];

  late final EmployeeDraft _d =
      widget.employee == null ? EmployeeDraft() : EmployeeDraft.from(widget.employee!);
  bool get _isNew => widget.employee == null;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const <Department>[];
    final banks = ref.watch(banksProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Add employee' : 'Edit ${widget.employee!.name}')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const _Section('Personal'),
            _text('Full name', _d.name, (v) => _d.name = v, caps: TextCapitalization.words),
            _gap,
            _dropdown<String>('Gender', _d.gender, EmployeeDraft.genders, (g) => g,
                (v) => setState(() => _d.gender = v)),
            _gap,
            _dateField('Date of birth', _d.dateOfBirth, (v) => setState(() => _d.dateOfBirth = v),
                first: DateTime(1920), last: DateTime.now()),
            _gap,
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: EmployeeDraft.idNric, label: Text('NRIC')),
                ButtonSegment(value: EmployeeDraft.idPassport, label: Text('Passport')),
              ],
              selected: {_d.idType},
              onSelectionChanged: (s) => setState(() => _d.idType = s.first),
            ),
            _gap,
            _text(_d.idType == EmployeeDraft.idNric ? 'NRIC number (12 digits)' : 'Passport number',
                _d.idNumber, (v) => _d.idNumber = v,
                key: ValueKey(_d.idType),
                caps: TextCapitalization.characters,
                keyboard: _d.idType == EmployeeDraft.idNric ? TextInputType.number : TextInputType.text),
            if (_d.idType == EmployeeDraft.idPassport) ...[
              _gap,
              _text('Passport country', _d.idCountry, (v) => _d.idCountry = v,
                  caps: TextCapitalization.words),
            ],
            const _Section('Contact'),
            _text('Email (also the login)', _d.email, (v) => _d.email = v,
                keyboard: TextInputType.emailAddress),
            _gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: _dialCodes.contains(_d.phoneCountryCode) ? _d.phoneCountryCode : '+60',
                    decoration: const InputDecoration(labelText: 'Code'),
                    items: [for (final c in _dialCodes) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _d.phoneCountryCode = v ?? '+60'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _text('Mobile number', _d.phone, (v) => _d.phone = v,
                      keyboard: TextInputType.phone, digitsOnly: true),
                ),
              ],
            ),
            const _Section('Employment'),
            _dropdown<int>('Department', _d.departmentId, departments.map((d) => d.id).toList(),
                (id) => departments.firstWhere((d) => d.id == id).name,
                (v) => setState(() => _d.departmentId = v)),
            _gap,
            _text('Designation', _d.designation, (v) => _d.designation = v,
                caps: TextCapitalization.words),
            _gap,
            _dateField('Join date', _d.joinDate, (v) => setState(() => _d.joinDate = v),
                first: DateTime(1980), last: DateTime(DateTime.now().year + 1, 12, 31)),
            _gap,
            _text('Basic salary (monthly)', _d.salary == null ? '' : _fmtNum(_d.salary!),
                (v) => _d.salary = double.tryParse(v),
                keyboard: const TextInputType.numberWithOptions(decimal: true), prefix: 'RM ', decimal: true),
            if (!_isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Inactive employees cannot log in and are not paid'),
                value: _d.isActive,
                onChanged: (v) => setState(() => _d.isActive = v),
              ),
            const _Section('Bank & statutory'),
            _dropdown<int>('Bank', _d.bankId, banks.map((b) => b.id).toList(),
                (id) => banks.firstWhere((b) => b.id == id).name,
                (v) => setState(() => _d.bankId = v)),
            _gap,
            _text('Account number', _d.accountNumber, (v) => _d.accountNumber = v,
                keyboard: TextInputType.number),
            _gap,
            _text('Income tax number (optional)', _d.taxNumber, (v) => _d.taxNumber = v,
                caps: TextCapitalization.characters),
            _gap,
            Text('EPF rate overrides — leave empty to use the company rates',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            _gap,
            Row(children: [
              Expanded(
                child: _text('Employee EPF %', _d.epfEmployeeRateOverride == null ? '' : _fmtNum(_d.epfEmployeeRateOverride!),
                    (v) => _d.epfEmployeeRateOverride = v.trim().isEmpty ? null : double.tryParse(v),
                    keyboard: const TextInputType.numberWithOptions(decimal: true), decimal: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _text('Employer EPF %', _d.epfEmployerRateOverride == null ? '' : _fmtNum(_d.epfEmployerRateOverride!),
                    (v) => _d.epfEmployerRateOverride = v.trim().isEmpty ? null : double.tryParse(v),
                    keyboard: const TextInputType.numberWithOptions(decimal: true), decimal: true),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ],
            if (_isNew) ...[
              const SizedBox(height: 12),
              Text('A login is created for the employee and a "set your password" email is sent to this address.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_isNew ? 'Create employee' : 'Save changes'),
          ),
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: 12);

  static String _fmtNum(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  Widget _text(
    String label,
    String initial,
    ValueChanged<String> onChanged, {
    Key? key,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.none,
    String? prefix,
    bool digitsOnly = false,
    bool decimal = false,
  }) =>
      TextFormField(
        key: key,
        initialValue: initial,
        keyboardType: keyboard,
        textCapitalization: caps,
        inputFormatters: [
          if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
          if (decimal) FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        decoration: InputDecoration(labelText: label, prefixText: prefix),
        onChanged: onChanged,
      );

  Widget _dropdown<T>(String label, T? value, List<T> options, String Function(T) text,
          ValueChanged<T?> onChanged) =>
      DropdownButtonFormField<T>(
        initialValue: options.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [for (final o in options) DropdownMenuItem(value: o, child: Text(text(o)))],
        onChanged: onChanged,
      );

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPicked,
          {required DateTime first, required DateTime last}) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            firstDate: first,
            lastDate: last,
            initialDate: value ?? (label.startsWith('Date of birth') ? DateTime(1995) : DateTime.now()),
            initialDatePickerMode:
                label.startsWith('Date of birth') ? DatePickerMode.year : DatePickerMode.day,
          );
          if (picked != null) onPicked(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined)),
          child: Text(value == null ? 'Select' : Fmt.date(value)),
        ),
      );

  Future<void> _save() async {
    final problem = _d.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    try {
      final message = _isNew
          ? await repo.createEmployee(_d)
          : await repo.updateEmployee(widget.employee!.id, _d).then((_) => 'Employee updated');
      ref.invalidate(employeesProvider);
      ref.invalidate(adminDashboardProvider);
      messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
      navigator.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiException.from(e).message;
        });
      }
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 10),
        child: Text(text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );
}
