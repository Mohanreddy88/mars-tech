import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../auth/application/auth_controller.dart';
import '../data/leave_models.dart';
import '../data/leave_repository.dart';

/// Apply for leave: type (with remaining balance), dates, working days
/// (from the server, so weekends and public holidays are excluded),
/// reason and an optional supporting document (e.g. MC).
/// Pops `true` when a request was submitted.
class ApplyLeaveScreen extends ConsumerStatefulWidget {
  const ApplyLeaveScreen({super.key});

  @override
  ConsumerState<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends ConsumerState<ApplyLeaveScreen> {
  final _reason = TextEditingController();
  LeaveType? _type;
  DateTimeRange? _range;
  double? _days;
  bool _calculating = false;
  LeaveAttachmentFile? _attachment;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(activeLeaveTypesProvider);
    final balances = ref.watch(leaveBalancesProvider(DateTime.now().year));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Apply leave')),
      body: types.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(activeLeaveTypesProvider)),
        data: (types) {
          final balanceFor = {
            for (final b in balances.valueOrNull ?? const <LeaveBalanceItem>[])
              b.leaveTypeId: b.balanceDays
          };
          final selectedBalance = _type == null ? null : balanceFor[_type!.id];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              DropdownButtonFormField<LeaveType>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Leave type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: [
                  for (final t in types)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        balanceFor.containsKey(t.id)
                            ? '${t.name} (${Fmt.days(balanceFor[t.id]!)} left)'
                            : t.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting ? null : (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _submitting ? null : _pickDates,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Dates',
                    prefixIcon: Icon(Icons.date_range_outlined),
                  ),
                  child: Text(
                    _range == null
                        ? 'Select start and end date'
                        : isSameDay(_range!.start, _range!.end)
                            ? Fmt.date(_range!.start)
                            : '${Fmt.date(_range!.start)}  –  ${Fmt.date(_range!.end)}',
                    style: _range == null
                        ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                        : null,
                  ),
                ),
              ),
              if (_range != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _calculating
                      ? const LinearProgressIndicator()
                      : Text(
                          _days == null
                              ? ''
                              : '${Fmt.days(_days!)} of leave '
                                  '(weekends and public holidays not counted)'
                                  '${selectedBalance != null && _days! > selectedBalance ? ' — more than your balance' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: selectedBalance != null &&
                                    _days != null &&
                                    _days! > selectedBalance
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              if (_attachment == null)
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Attach photo (optional)'),
                )
              else
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(_attachment!.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${(_attachment!.bytes.length / 1024).toStringAsFixed(0)} KB'),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed:
                          _submitting ? null : () => setState(() => _attachment = null),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text('A photo of e.g. your medical certificate (max 5 MB). '
                    'PDF documents can be uploaded on the website.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Submit request'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: 'Leave dates',
    );
    if (picked == null) return;
    setState(() {
      _range = picked;
      _days = null;
      _calculating = true;
    });
    try {
      final days =
          await ref.read(leaveRepositoryProvider).workingDays(picked.start, picked.end);
      if (mounted && _range == picked) setState(() => _days = days);
    } catch (_) {
      // The server validates again on submit; the count is only a preview.
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    // Resize/compress so a phone photo stays well under the 5 MB limit
    // (and is re-encoded as JPEG, which the API accepts).
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 80,
      );
    } catch (e) {
      setState(() => _error = 'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.');
      return;
    }
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (bytes.length > LeaveAttachmentFile.maxBytes) {
      setState(() => _error = 'The photo is larger than 5 MB.');
      return;
    }
    final name = photo.name.contains('.') ? photo.name : '${photo.name}.jpg';
    setState(() {
      _error = null;
      _attachment = LeaveAttachmentFile(name: name, bytes: bytes);
    });
  }

  Future<void> _submit() async {
    final employeeId = ref.read(authControllerProvider)?.employeeId;
    String? problem;
    if (employeeId == null) {
      problem = 'Your login is not linked to an employee profile. Please contact HR.';
    } else if (_type == null) {
      problem = 'Choose a leave type.';
    } else if (_range == null) {
      problem = 'Choose the leave dates.';
    } else if (_days == 0) {
      problem = 'The selected dates are all weekends or public holidays.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(leaveRepositoryProvider);
    try {
      final id = await repo.apply(
        employeeId: employeeId!,
        leaveTypeId: _type!.id,
        start: _range!.start,
        end: _range!.end,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      var message = 'Leave request submitted';
      if (_attachment != null) {
        try {
          await repo.uploadAttachment(id, _attachment!);
        } catch (e) {
          // The request exists; tell the user the document still needs adding.
          message = 'Leave submitted, but the document could not be uploaded: '
              '${ApiException.from(e).message}';
        }
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
      navigator.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = ApiException.from(e).message;
        });
      }
    }
  }
}
