import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';

/// A company the app can sign in to: its name, and the code that makes its address
/// (`<code>.marshrms.com`, or `<code>.uat.marshrms.com` in a UAT build — the user never sees it).
class CompanyOption {
  const CompanyOption(this.code, this.name);
  final String code;
  final String name;
}

/// Registered, active companies from the main site (GET /api/public/companies).
final companiesProvider = FutureProvider.autoDispose<List<CompanyOption>>((ref) async {
  final dio = Dio(BaseOptions(
    baseUrl: Env.urlForCompany(null),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ));
  final res = await dio.get<List<dynamic>>('public/companies');
  return (res.data ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((m) => CompanyOption('${m['code'] ?? ''}', '${m['name'] ?? m['code'] ?? ''}'))
      .where((c) => c.code.isNotEmpty)
      .toList();
});

/// Login field: shows the chosen company's name; tapping opens a searchable list.
/// If the list can't be loaded, the user can still type their company code.
class CompanyField extends ConsumerWidget {
  const CompanyField({super.key, required this.code, required this.onChanged});

  /// The chosen company code ('' = none chosen yet).
  final String code;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider);
    final name = companies.valueOrNull
        ?.where((c) => c.code == code)
        .map((c) => c.name)
        .firstOrNull;

    return FormField<String>(
      initialValue: code,
      validator: (_) => code.isEmpty ? 'Choose your company' : null,
      builder: (state) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          final picked = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => _CompanySheet(selected: code),
          );
          if (picked != null) {
            onChanged(picked);
            state.didChange(picked);
          }
        },
        child: InputDecorator(
          isEmpty: code.isEmpty,
          decoration: InputDecoration(
            labelText: 'Company',
            hintText: 'Choose your company',
            prefixIcon: const Icon(Icons.business_outlined),
            suffixIcon: companies.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : const Icon(Icons.arrow_drop_down),
            errorText: state.errorText,
          ),
          child: code.isEmpty ? null : Text(name ?? code, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Bottom sheet: search box + list of companies; falls back to typing the code.
class _CompanySheet extends ConsumerStatefulWidget {
  const _CompanySheet({required this.selected});
  final String selected;

  @override
  ConsumerState<_CompanySheet> createState() => _CompanySheetState();
}

class _CompanySheetState extends ConsumerState<_CompanySheet> {
  final _search = TextEditingController();
  bool _typing = false;
  String? _typedError;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _useTyped() {
    final code = _search.text.trim().toLowerCase();
    final error = code.isEmpty ? 'Enter your company code.' : Env.companyCodeError(code);
    if (error != null) {
      setState(() => _typedError = error);
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final companies = ref.watch(companiesProvider);
    final q = _search.text.trim().toLowerCase();

    Widget body;
    if (_typing) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Text('Ask your school or company office for the code.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    } else {
      body = companies.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Couldn't load the list of companies. Check your internet connection."),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: () => ref.invalidate(companiesProvider), child: const Text('Try again')),
              TextButton(onPressed: () => setState(() => _typing = true), child: const Text('Type the code instead')),
            ]),
          ]),
        ),
        data: (list) {
          final shown = list
              .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.code.contains(q))
              .toList();
          if (shown.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(list.isEmpty ? 'No companies are registered yet.' : 'No company matches "${_search.text.trim()}".'),
                TextButton(onPressed: () => setState(() => _typing = true), child: const Text('Type the code instead')),
              ]),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            itemCount: shown.length,
            itemBuilder: (_, i) {
              final c = shown[i];
              final selected = c.code == widget.selected;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
                ),
                title: Text(c.name),
                trailing: selected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                selected: selected,
                onTap: () => Navigator.of(context).pop(c.code),
              );
            },
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(_typing ? 'Enter company code' : 'Choose your company', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                autocorrect: false,
                textInputAction: _typing ? TextInputAction.done : TextInputAction.search,
                onSubmitted: (_) => _typing ? _useTyped() : null,
                onChanged: (_) => setState(() => _typedError = null),
                decoration: InputDecoration(
                  prefixIcon: Icon(_typing ? Icons.business_outlined : Icons.search),
                  hintText: _typing ? 'Company code' : 'Search by name',
                  errorText: _typedError,
                  suffixIcon: _typing
                      ? IconButton(icon: const Icon(Icons.arrow_forward), tooltip: 'Use this code', onPressed: _useTyped)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(child: body),
          ],
        ),
      ),
    );
  }
}
