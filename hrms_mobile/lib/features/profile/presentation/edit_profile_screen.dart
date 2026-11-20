import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';

/// Edit the details an employee may change themselves: mobile number and
/// salary bank account. Pops `true` when saved.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final EmployeeProfile profile;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _account = TextEditingController(text: widget.profile.accountNumber ?? '');
  late int? _bankId = widget.profile.bankId;
  bool _saving = false;

  @override
  void dispose() {
    _phone.dispose();
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(banksProvider);
    final code = widget.profile.phoneCountryCode ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Edit details')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            TextFormField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: const Icon(Icons.phone_outlined),
                prefixText: code.isEmpty ? null : '$code ',
                helperText: '7–12 digits, without the country code',
              ),
              // Same rule as the API.
              validator: (v) => v == null || v.isEmpty || RegExp(r'^\d{7,12}$').hasMatch(v)
                  ? null
                  : 'Mobile number must be 7–12 digits.',
            ),
            const SizedBox(height: 16),
            banks.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(ApiException.from(e).message),
              data: (list) => DropdownButtonFormField<int>(
                initialValue: list.any((b) => b.id == _bankId) ? _bankId : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Bank',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: [
                  for (final b in list) DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: _saving ? null : (v) => setState(() => _bankId = v),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _account,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
              decoration: const InputDecoration(
                labelText: 'Account number',
                prefixIcon: Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your email, name and job details are managed by HR.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).update(
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            bankId: _bankId,
            accountNumber: _account.text.trim().isEmpty ? null : _account.text.trim(),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Details updated')));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
      if (mounted) setState(() => _saving = false);
    }
  }
}
