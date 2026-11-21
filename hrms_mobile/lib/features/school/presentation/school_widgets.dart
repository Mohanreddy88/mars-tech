import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource, XFile;
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/file_opener.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';

/// Shows a short message at the bottom of the screen.
void toast(BuildContext context, String text, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? scheme.error : null,
    ));
}

/// Runs [action]; shows the API's message if it fails. Returns true on success.
Future<bool> attempt(BuildContext context, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (done != null && context.mounted) toast(context, done);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, ApiException.from(e).message, error: true);
    return false;
  }
}

/// Downloads a protected file (with the login token) and opens it on the phone.
Future<void> openBytes(BuildContext context, Future<Uint8List> Function() download, String fileName) async {
  try {
    final bytes = await download();
    final file = await FileOpener.save(bytes, fileName);
    await FileOpener.open(file, mimeType: FileOpener.mimeFor(fileName));
  } catch (e) {
    if (context.mounted) toast(context, ApiException.from(e).message, error: true);
  }
}

/// Camera or gallery; the photo is resized so it stays under the 5 MB limit.
Future<PickedFile?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      ]),
    ),
  );
  if (source == null) return null;
  final XFile? photo;
  try {
    photo = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 80);
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.', error: true);
    return null;
  }
  if (photo == null) return null;
  final bytes = await photo.readAsBytes();
  if (bytes.length > PickedFile.maxBytes) {
    if (context.mounted) toast(context, 'The photo is larger than 5 MB.', error: true);
    return null;
  }
  final name = photo.name.contains('.') ? photo.name : '${photo.name}.jpg';
  return PickedFile(name: name, bytes: bytes);
}

/// A protected photo (daily report or chat), loaded with the login token. Tap for full screen.
class ProtectedPhoto extends ConsumerWidget {
  const ProtectedPhoto({super.key, required this.provider, this.size, this.radius = 10, this.fit = BoxFit.cover});

  final ProviderListenable<AsyncValue<Uint8List>> provider;
  final double? size;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(provider);
    final scheme = Theme.of(context).colorScheme;
    Widget box(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Container(width: size, height: size, color: scheme.surfaceContainerHighest, child: child),
        );
    return photo.when(
      loading: () => box(const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
      error: (_, __) => box(Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant)),
      data: (bytes) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
          ),
        )),
        child: box(Image.memory(bytes, fit: fit)),
      ),
    );
  }
}

/// ‹ Today, Sat 21 Nov › — previous / next school day (never past today).
class DayBar extends StatelessWidget {
  const DayBar({super.key, required this.date, required this.today, required this.onChanged});

  final String date;
  final String today;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isToday = date == today;
    final label = '${isToday ? 'Today, ' : ''}${DateFormat('EEE d MMM').format(ymdToDate(date))}';
    return Row(
      children: [
        IconButton(onPressed: () => onChanged(addDays(date, -1)), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: ymdToDate(date),
                firstDate: ymdToDate(today).subtract(const Duration(days: 365)),
                lastDate: ymdToDate(today),
              );
              if (picked != null) onChanged(dateToYmd(picked));
            },
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        IconButton(
          onPressed: isToday ? null : () => onChanged(addDays(date, 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Coloured pill: Paid / Part paid / Unpaid / Overdue / Present / Absent / Sent / Draft.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.neutral});
  final String text;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (tone) {
      PillTone.good => (const Color(0xFFDCFCE7), const Color(0xFF166534)),
      PillTone.info => (const Color(0xFFE0F2FE), const Color(0xFF075985)),
      PillTone.warn => (const Color(0xFFFEF3C7), const Color(0xFF92400E)),
      PillTone.bad => (scheme.errorContainer, scheme.onErrorContainer),
      PillTone.neutral => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

enum PillTone { good, info, warn, bad, neutral }

PillTone invoiceTone(Invoice i) => i.overdue
    ? PillTone.bad
    : switch (i.status) {
        'Paid' => PillTone.good,
        'Partial' => PillTone.info,
        _ => PillTone.neutral,
      };

/// "Sat 21 Nov" or "Sat 21 – Mon 23 Nov" for a note.
String noteWhen(ParentNote n) {
  final f = DateFormat('EEE d MMM');
  return n.fromDate == n.toDate
      ? f.format(ymdToDate(n.fromDate))
      : '${f.format(ymdToDate(n.fromDate))} – ${f.format(ymdToDate(n.toDate))}';
}

/// Malaysian numbers shown locally: +60123456789 → 012-345 6789.
String phoneText(String? stored) {
  if (stored == null || stored.isEmpty) return '';
  if (!stored.startsWith('+60')) return stored;
  final n = stored.substring(3);
  final d = '0$n';
  if (n.startsWith('1')) {
    return n.startsWith('11') || n.startsWith('15')
        ? '${d.substring(0, 3)}-${d.substring(3, 7)} ${d.substring(7)}'
        : '${d.substring(0, 3)}-${d.substring(3, 6)} ${d.substring(6)}';
  }
  if (n.startsWith('3') && d.length >= 10) return '${d.substring(0, 2)}-${d.substring(2, 6)} ${d.substring(6)}';
  return d;
}
