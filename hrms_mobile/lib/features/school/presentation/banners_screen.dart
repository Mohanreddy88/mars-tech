import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/banners.dart';
import '../data/school_admin.dart';
import 'banner_carousel.dart';
import 'school_widgets.dart';
import 'setup_widgets.dart';

// School → Banners (admins): advert-style slides on the parent home. Same as the website.

final _classesProvider = FutureProvider.autoDispose<List<ClassItem>>((ref) => ref.watch(schoolAdminProvider).classes());

String _date(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : DateFormat('d MMM yyyy').format(d);
}

/// The banners in slide order: preview, who sees it, dates and status; reorder, switch off, edit.
class BannersScreen extends ConsumerWidget {
  const BannersScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, SchoolBanner? b) async {
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => BannerFormScreen(banner: b)));
    if (saved == true) ref.invalidate(bannersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(bannersProvider);
    final repo = ref.read(bannersRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Banners')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('New banner'),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(bannersProvider)),
        data: (banners) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(bannersProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text('Slides at the top of the parent home, in the app and on the website — events, offers, reminders.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (banners.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Text('No banners yet.\nAdd one — e.g. "Holiday camp: register now" with a photo and a button.',
                      textAlign: TextAlign.center),
                ),
              for (var i = 0; i < banners.length; i++)
                _BannerTile(
                  banner: banners[i],
                  first: i == 0,
                  last: i == banners.length - 1,
                  onEdit: () => _edit(context, ref, banners[i]),
                  onMove: (up) async {
                    if (await attempt(context, () => repo.move(banners[i].id, up: up))) ref.invalidate(bannersProvider);
                  },
                  onToggle: () async {
                    final b = banners[i];
                    final save = BannerSave.of(b)..isActive = !b.isActive;
                    if (await attempt(context, () => repo.save(b.id, save), done: b.isActive ? 'Switched off' : 'Switched on')) {
                      ref.invalidate(bannersProvider);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerTile extends StatelessWidget {
  const _BannerTile({required this.banner, required this.first, required this.last, required this.onEdit,
      required this.onMove, required this.onToggle});

  final SchoolBanner banner;
  final bool first, last;
  final VoidCallback onEdit;
  final ValueChanged<bool> onMove;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final b = banner;
    final tone = switch (b.status) { 'Live' => PillTone.good, 'Scheduled' => PillTone.warn, 'Ended' => PillTone.bad, _ => PillTone.neutral };
    final dates = b.startsOn == null && b.endsOn == null
        ? 'Always'
        : '${b.startsOn == null ? '…' : _date(b.startsOn!)} – ${b.endsOn == null ? '…' : _date(b.endsOn!)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 150, child: Opacity(opacity: b.isActive ? 1 : .55, child: BannerSlide(banner: b))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Pill(b.status, tone: tone), const SizedBox(width: 8),
                    Flexible(child: Text(b.className == null ? 'All parents' : '${b.className} parents', overflow: TextOverflow.ellipsis))]),
                  const SizedBox(height: 4),
                  Text(dates, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              IconButton(onPressed: first ? null : () => onMove(true), icon: const Icon(Icons.arrow_upward), tooltip: 'Earlier'),
              IconButton(onPressed: last ? null : () => onMove(false), icon: const Icon(Icons.arrow_downward), tooltip: 'Later'),
              IconButton(
                onPressed: onToggle,
                icon: Icon(b.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                tooltip: b.isActive ? 'Switch off' : 'Switch on',
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// New or edit banner, with a live preview at the top.
class BannerFormScreen extends ConsumerStatefulWidget {
  const BannerFormScreen({super.key, this.banner});
  final SchoolBanner? banner;

  @override
  ConsumerState<BannerFormScreen> createState() => _BannerFormScreenState();
}

class _BannerFormScreenState extends ConsumerState<BannerFormScreen> {
  late final BannerSave f = widget.banner == null ? BannerSave(title: '') : BannerSave.of(widget.banner!);
  late final _title = TextEditingController(text: f.title);
  late final _text = TextEditingController(text: f.text);
  late final _button = TextEditingController(text: f.buttonText);
  late final _web = TextEditingController(text: f.link.startsWith('https://') ? f.link : '');
  late String _kind = f.link.isEmpty ? 'none' : f.link.startsWith('https://') ? 'web' : 'page';
  late String _page = bannerPages.containsKey(f.link) ? f.link : 'fees';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _text, _button, _web]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _link => switch (_kind) { 'page' => _page, 'web' => _web.text.trim(), _ => '' };

  SchoolBanner get _preview {
    final link = _link;
    return SchoolBanner(
      id: widget.banner?.id ?? 0,
      title: _title.text.trim().isEmpty ? 'Your headline' : _title.text.trim(),
      text: _text.text.trim(),
      buttonText: link.isEmpty ? null : (_button.text.trim().isEmpty ? 'Find out more' : _button.text.trim()),
      link: link.isEmpty ? null : link,
      theme: f.theme,
      imageVersion: widget.banner?.imageVersion,
    );
  }

  Future<void> _pick() async {
    final photo = await pickPhoto(context);
    if (photo == null) return;
    if (photo.bytes.length > 3 * 1024 * 1024) {
      if (mounted) toast(context, 'The picture must be 3 MB or smaller.', error: true);
      return;
    }
    setState(() {
      f.image = photo;
      f.removeImage = false;
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter a headline.');
      return;
    }
    if (_kind == 'web' && !_web.text.trim().startsWith('https://')) {
      setState(() => _error = 'The web address must start with https://');
      return;
    }
    f
      ..title = _title.text.trim()
      ..text = _text.text.trim()
      ..buttonText = _button.text.trim()
      ..link = _link;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(bannersRepositoryProvider).save(widget.banner?.id, f);
      if (mounted) {
        toast(context, 'Banner saved');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final b = widget.banner!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${b.title}"?'),
        content: const Text('Parents stop seeing it straight away. To hide it for now, switch it off instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await attempt(context, () => ref.read(bannersRepositoryProvider).delete(b.id), done: 'Banner deleted') && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = ref.watch(_classesProvider).valueOrNull ?? const <ClassItem>[];
    final hasSavedImage = widget.banner?.imageVersion != null && !f.removeImage;
    final hasImage = f.image != null || hasSavedImage;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.banner == null ? 'New banner' : 'Edit banner'),
        actions: [
          if (widget.banner != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Delete'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SizedBox(
            height: 170,
            child: BannerSlide(banner: _preview, localImage: f.image?.bytes, useSavedImage: hasSavedImage),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 80,
            decoration: boxDecoration('Headline', hint: 'e.g. Holiday camp — register now'),
            onChanged: (_) => setState(() {}),
          ),
          formGap,
          TextField(
            controller: _text,
            maxLength: 200,
            decoration: boxDecoration('Text (optional)', hint: 'e.g. 7–18 December · art, swimming and science'),
            onChanged: (_) => setState(() {}),
          ),
          const SectionTitle('Colour'),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final t in bannerThemes)
              GestureDetector(
                onTap: () => setState(() => f.theme = t),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: bannerColors[t]!),
                    border: Border.all(color: f.theme == t ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3),
                  ),
                  child: f.theme == t ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                ),
              ),
          ]),
          const SectionTitle('Picture (optional)', subtitle: 'JPG or PNG up to 3 MB. Wide photos look best.'),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.image_outlined),
              label: Text(hasImage ? 'Change picture' : 'Choose picture'),
            ),
            const SizedBox(width: 8),
            if (hasImage)
              TextButton(
                onPressed: () => setState(() {
                  f.image = null;
                  f.removeImage = true;
                }),
                child: const Text('Remove'),
              ),
          ]),
          const SectionTitle('Button'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _kind,
            isExpanded: true,
            decoration: boxDecoration('The button opens'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('No button')),
              DropdownMenuItem(value: 'page', child: Text('A page in the parent app / portal')),
              DropdownMenuItem(value: 'web', child: Text('A web address')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? 'none'),
          ),
          if (_kind != 'none') ...[
            formGap,
            TextField(
              controller: _button,
              maxLength: 30,
              decoration: boxDecoration('Button text', hint: 'Find out more'),
              onChanged: (_) => setState(() {}),
            ),
            formGap,
            if (_kind == 'page')
              DropdownButtonFormField<String>(
                value: _page,
                isExpanded: true,
                decoration: boxDecoration('Page'),
                items: [for (final e in bannerPages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _page = v ?? 'fees'),
              )
            else
              TextField(
                controller: _web,
                keyboardType: TextInputType.url,
                decoration: boxDecoration('Web address', hint: 'https://forms.gle/… or https://wa.me/60…'),
                onChanged: (_) => setState(() {}),
              ),
          ],
          const SectionTitle('Who and when'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            value: classes.any((c) => c.id == f.classId) ? f.classId : null,
            isExpanded: true,
            decoration: boxDecoration('Shown to'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All parents')),
              for (final c in classes.where((c) => c.isActive || c.id == f.classId))
                DropdownMenuItem(value: c.id, child: Text('Parents of ${c.name}')),
            ],
            onChanged: (v) => setState(() => f.classId = v),
          ),
          formGap,
          DateField(
            label: 'From (optional)',
            value: f.startsOn,
            icon: Icons.event_outlined,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 3),
            initialDate: now,
            onChanged: (v) => setState(() => f.startsOn = v),
          ),
          formGap,
          DateField(
            label: 'Until (optional)',
            value: f.endsOn,
            icon: Icons.event_busy_outlined,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 3),
            initialDate: now,
            onChanged: (v) => setState(() => f.endsOn = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show this banner'),
            value: f.isActive,
            onChanged: (v) => setState(() => f.isActive = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
