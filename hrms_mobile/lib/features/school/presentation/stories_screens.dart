import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_extras.dart';
import '../data/school_repository.dart' show schoolMeProvider;
import 'school_widgets.dart';

const _maxPhoto = 10 * 1024 * 1024;
const _maxVideo = 100 * 1024 * 1024;

/// Class stories: parents view and download the photos and videos of their child's class;
/// class teachers and the office post new ones (button at the bottom).
class StoriesScreen extends ConsumerWidget {
  const StoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stories = ref.watch(storiesProvider);
    final me = ref.watch(schoolMeProvider).valueOrNull;
    final canPost = me != null && me.isStaff;
    return Scaffold(
      appBar: AppBar(title: const Text('Stories')),
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              onPressed: () async {
                final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewStoryScreen()));
                if (done == true) ref.invalidate(storiesProvider);
              },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('New story'),
            )
          : null,
      body: stories.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(storiesProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(storiesProvider.future),
          child: list.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      canPost
                          ? 'No stories yet. Tap "New story" to share photos and videos with the parents of your class.'
                          : 'No stories yet. When the teacher shares photos or videos of the class, they appear here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _StoryCard(story: list[i]),
                ),
        ),
      ),
    );
  }
}

class _StoryCard extends ConsumerWidget {
  const _StoryCard({required this.story});
  final Story story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(schoolExtrasProvider);
    final text = Theme.of(context).textTheme;
    final s = story;
    final shown = s.media.take(6).toList();
    final photos = s.media.where((m) => !m.isVideo).length;
    final videos = s.media.length - photos;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(s.className ?? 'Whole school', tone: PillTone.info),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.createdByName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(DateFormat('d MMM yyyy, h:mm a').format(s.publishedAt ?? s.createdAt), style: text.bodySmall),
              ]),
            ),
            if (s.canEdit)
              PopupMenuButton<String>(
                onSelected: (_) async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete story'),
                      content: const Text('Delete this story and all its photos and videos? Parents will no longer see them.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  if (await attempt(context, () => repo.deleteStory(s.id), done: 'Story deleted.')) {
                    ref.invalidate(storiesProvider);
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete story'))],
              ),
          ]),
          if (s.publishedAt == null)
            const Padding(padding: EdgeInsets.only(top: 6), child: Pill('Draft — parents can\'t see it', tone: PillTone.warn)),
          if (s.caption != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.caption!)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: shown.length == 1 ? 1 : shown.length == 2 ? 2 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: shown.length == 1 ? 16 / 10 : 1,
            children: [
              for (var i = 0; i < shown.length; i++)
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => StoryViewerScreen(story: s, initialIndex: i),
                  )),
                  child: Stack(fit: StackFit.expand, children: [
                    _Thumb(media: shown[i], url: repo.mediaUrl(shown[i].url)),
                    if (i == 5 && s.media.length > 6)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: Text('+${s.media.length - 6}',
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text([if (photos > 0) '$photos photo${photos == 1 ? '' : 's'}', if (videos > 0) '$videos video${videos == 1 ? '' : 's'}'].join(' · '),
              style: text.bodySmall),
        ]),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.media, required this.url});
  final StoryMedia media;
  final String url;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return Container(
        color: const Color(0xFF111827),
        alignment: Alignment.center,
        child: const CircleAvatar(
          radius: 22,
          backgroundColor: Colors.black54,
          child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : Container(color: Colors.black12, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (_, __, ___) => Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined)),
    );
  }
}

/// Full screen: swipe through the story's photos and videos; download / share each file.
/// Videos play in the phone's own video player (streamed with the signed link).
class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({super.key, required this.story, this.initialIndex = 0});
  final Story story;
  final int initialIndex;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  double? _progress;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _download(StoryMedia m) async {
    setState(() => _progress = 0);
    try {
      final bytes = await ref.read(schoolExtrasProvider).download(m, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      final file = await FileOpener.save(bytes, m.fileName);
      await FileOpener.share(file, mimeType: m.contentType, subject: m.fileName);
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _play(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, 'Could not open the video.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(schoolExtrasProvider);
    final media = widget.story.media;
    final current = media[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${media.length}'),
        actions: [
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(value: _progress == 0 ? null : _progress, strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              tooltip: 'Download / share',
              icon: const Icon(Icons.download),
              onPressed: () => _download(current),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: media.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final m = media[i];
              final url = repo.mediaUrl(m.url);
              if (m.isVideo) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    IconButton.filled(
                      iconSize: 56,
                      onPressed: () => _play(url),
                      icon: const Icon(Icons.play_arrow),
                    ),
                    const SizedBox(height: 12),
                    const Text('Tap to play the video', style: TextStyle(color: Colors.white70)),
                  ]),
                );
              }
              return InteractiveViewer(
                child: Center(
                  child: Image.network(url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, p) => p == null ? child : const CircularProgressIndicator(color: Colors.white),
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
                ),
              );
            },
          ),
        ),
        if (widget.story.caption != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(widget.story.caption!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            ),
          ),
      ]),
    );
  }
}

class _Pending {
  _Pending(this.file, this.isVideo, this.size);
  final XFile file;
  final bool isVideo;
  final int size;
  double progress = 0;
  bool done = false;
  String? error;
}

/// Staff: a new story for one of their classes (the office: any class or the whole school).
class NewStoryScreen extends ConsumerStatefulWidget {
  const NewStoryScreen({super.key});

  @override
  ConsumerState<NewStoryScreen> createState() => _NewStoryScreenState();
}

class _NewStoryScreenState extends ConsumerState<NewStoryScreen> {
  final _caption = TextEditingController();
  StoryAudience? _audience;
  int? _classId;
  bool _wholeSchool = false;
  final List<_Pending> _files = [];
  bool _working = false;
  int? _storyId;

  @override
  void initState() {
    super.initState();
    ref.read(schoolExtrasProvider).audience().then((a) {
      if (!mounted) return;
      setState(() {
        _audience = a;
        _classId = a.classes.isNotEmpty ? a.classes.first.id : null;
        _wholeSchool = a.classes.isEmpty && a.wholeSchool;
      });
    }).catchError((Object e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    });
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  bool _looksVideo(XFile f) {
    final n = f.name.toLowerCase();
    return (f.mimeType?.startsWith('video/') ?? false) || n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.webm') || n.endsWith('.3gp');
  }

  Future<void> _add(Future<List<XFile>> Function() pick) async {
    List<XFile> picked;
    try {
      picked = await pick();
    } catch (_) {
      if (mounted) toast(context, 'Could not open the camera or gallery.', error: true);
      return;
    }
    for (final f in picked) {
      final video = _looksVideo(f);
      final size = await File(f.path).length();
      final p = _Pending(f, video, size);
      if (video && size > _maxVideo) p.error = 'Video over 100 MB';
      if (!video && size > _maxPhoto) p.error = 'Photo over 10 MB';
      _files.add(p);
    }
    if (mounted) setState(() {});
  }

  Future<void> _publish() async {
    final todo = _files.where((f) => !f.done && f.error == null).toList();
    if (_storyId == null && todo.isEmpty) {
      toast(context, 'Add at least one photo or video.', error: true);
      return;
    }
    setState(() => _working = true);
    final repo = ref.read(schoolExtrasProvider);
    try {
      final caption = _caption.text.trim().isEmpty ? null : _caption.text.trim();
      _storyId ??= await repo.createStory(_wholeSchool ? null : _classId, caption);
      for (final f in todo) {
        try {
          await repo.addMedia(_storyId!, f.file.path, f.file.name, (p) {
            if (mounted) setState(() => f.progress = p);
          });
          f.done = true;
        } catch (e) {
          f.error = ApiException.from(e).message;
        }
        if (mounted) setState(() {});
      }
      if (!_files.any((f) => f.done)) {
        if (mounted) toast(context, 'None of the files could be uploaded.', error: true);
        return;
      }
      final sent = await repo.publish(_storyId!);
      if (!mounted) return;
      final failed = _files.where((f) => f.error != null).length;
      toast(context, 'Story shared${sent > 0 ? ' with $sent parent${sent == 1 ? '' : 's'}' : ''}.'
          '${failed > 0 ? ' $failed file${failed == 1 ? '' : 's'} could not be added.' : ''}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _size(int b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final a = _audience;
    final picker = ImagePicker();
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(title: const Text('New story')),
        body: a == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                DropdownButtonFormField<int?>(
                  value: _wholeSchool ? -1 : _classId,
                  decoration: const InputDecoration(labelText: 'Share with'),
                  items: [
                    if (a.wholeSchool) const DropdownMenuItem<int?>(value: -1, child: Text('Whole school (every parent)')),
                    for (final c in a.classes) DropdownMenuItem<int?>(value: c.id, child: Text('Parents of ${c.name}')),
                  ],
                  onChanged: _working || _storyId != null
                      ? null
                      : (v) => setState(() {
                            _wholeSchool = v == -1;
                            _classId = v == -1 ? null : v;
                          }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _caption,
                  enabled: !_working,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'Caption (optional)', hintText: 'e.g. Sports day practice!'),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _working ? null : () => _add(() => picker.pickMultipleMedia(maxWidth: 2400, maxHeight: 2400, imageQuality: 85)),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _add(() async {
                              final f = await picker.pickImage(source: ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 85);
                              return f == null ? <XFile>[] : [f];
                            }),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _add(() async {
                              final f = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 3));
                              return f == null ? <XFile>[] : [f];
                            }),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Record video'),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('Photos up to 10 MB, videos up to 100 MB, up to 20 per story.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (var i = 0; i < _files.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _files[i].isVideo
                        ? const CircleAvatar(child: Icon(Icons.videocam))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(File(_files[i].file.path), width: 48, height: 48, fit: BoxFit.cover),
                          ),
                    title: Text(_files[i].file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: _files[i].error != null
                        ? Text(_files[i].error!, style: const TextStyle(color: Colors.red))
                        : _working && !_files[i].done
                            ? LinearProgressIndicator(value: _files[i].progress)
                            : Text(_files[i].done ? 'Uploaded' : _size(_files[i].size)),
                    trailing: _working || _files[i].done
                        ? (_files[i].done ? const Icon(Icons.check_circle, color: Color(0xFF16A34A)) : null)
                        : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _files.removeAt(i))),
                  ),
              ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _working || a == null ? null : _publish,
              icon: _working
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_working ? 'Uploading…' : 'Publish to parents'),
            ),
          ),
        ),
      ),
    );
  }
}
