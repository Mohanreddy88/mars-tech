import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/school_extras.dart';
import 'school_widgets.dart';

/// Round profile photo of a child ('students') or parent ('parents'), loaded with the login
/// token; the initials while there is no photo.
class SchoolAvatar extends ConsumerWidget {
  const SchoolAvatar({super.key, required this.kind, required this.id, required this.version, required this.name, this.radius = 20});

  final String kind;
  final int id;
  final String? version;
  final String name;
  final double radius;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = ref.watch(profilePhotoProvider((kind: kind, id: id, version: version))).valueOrNull;
    return CircleAvatar(
      radius: radius,
      backgroundColor: kind == 'parents' ? const Color(0xFFFCE7F3) : scheme.primary,
      foregroundImage: bytes == null ? null : MemoryImage(bytes),
      child: Text(_initials,
          style: TextStyle(
              fontSize: radius * 0.75,
              fontWeight: FontWeight.w700,
              color: kind == 'parents' ? const Color(0xFFBE185D) : scheme.onPrimary)),
    );
  }
}

/// Avatar with a small camera badge: tap to take / choose a new photo or remove it.
/// [onChanged] gets the new version (null when removed).
class EditableAvatar extends ConsumerStatefulWidget {
  const EditableAvatar({super.key, required this.kind, required this.id, required this.version, required this.name,
      this.radius = 30, this.onChanged});

  final String kind;
  final int id;
  final String? version;
  final String name;
  final double radius;
  final ValueChanged<String?>? onChanged;

  @override
  ConsumerState<EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends ConsumerState<EditableAvatar> {
  late String? _version = widget.version;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant EditableAvatar old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) _version = widget.version;
  }

  Future<void> _change() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add_a_photo_outlined),
            title: Text(_version == null ? 'Add photo' : 'Change photo'),
            onTap: () => Navigator.pop(ctx, 'change'),
          ),
          if (_version != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove photo'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final repo = ref.read(schoolExtrasProvider);
    if (action == 'remove') {
      setState(() => _busy = true);
      final ok = await attempt(context, () => repo.deletePhoto(widget.kind, widget.id), done: 'Photo removed.');
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (ok) _version = null;
      });
      if (ok) widget.onChanged?.call(null);
      return;
    }
    final picked = await pickPhoto(context);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    String? v;
    final ok = await attempt(context, () async => v = await repo.setPhoto(widget.kind, widget.id, picked.bytes, picked.name),
        done: 'Photo saved.');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _version = v;
    });
    if (ok) widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _busy ? null : _change,
      child: Stack(clipBehavior: Clip.none, children: [
        SchoolAvatar(kind: widget.kind, id: widget.id, version: _version, name: widget.name, radius: widget.radius),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle, boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)]),
            child: _busy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.photo_camera, size: 14, color: scheme.primary),
          ),
        ),
      ]),
    );
  }
}
