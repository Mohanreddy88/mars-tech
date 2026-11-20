import 'package:flutter/material.dart';

/// Small coloured label for a workflow status
/// (Draft, Pending, Submitted, Approved, Rejected, Cancelled, ...).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});

  /// Decides the colour.
  final String status;

  /// Text to show instead of [status] (e.g. "Active" in green).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status.toLowerCase()) {
      'approved' || 'processed' => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      'pending' || 'submitted' || 'under review' || 'pending approval' =>
        (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      'rejected' => (scheme.errorContainer, scheme.onErrorContainer),
      'cancelled' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      'not started' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer), // Draft, ...
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label ?? status,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
