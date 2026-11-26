import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/storage/company_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/home_tiles.dart';
import '../../assistant/presentation/assistant_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../data/banners.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'banner_carousel.dart';
import 'messages_screens.dart';
import 'school_avatar.dart';
import 'school_widgets.dart';

/// The child shown on the parent home (parents with several children switch between them).
/// Kept for the whole session, so coming back to Home shows the same child.
final selectedChildProvider = StateProvider<int?>((ref) => null);

final _todayProvider = FutureProvider.autoDispose.family<ChildDay, int>(
    (ref, id) => ref.watch(schoolRepositoryProvider).day(id, schoolToday()));

/// Outstanding fees for the counters row (0 when it can't be loaded).
final _feesDueProvider = FutureProvider.autoDispose<double>((ref) async {
  try {
    return (await ref.watch(schoolRepositoryProvider).myFees()).outstanding;
  } catch (_) {
    return 0;
  }
});

/// Absolute address of a server path such as "/api/company-settings/logo?v=1".
String? _serverUrl(WidgetRef ref, String? path) {
  if (path == null) return null;
  return Uri.parse(ref.read(apiBaseUrlProvider)).resolve(path).toString();
}

/// Parent home: the child (switch between siblings), today's status, counters for unread
/// messages / news and fees due, and a grid of big tiles for everything a parent does.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(schoolMeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(meAsync.valueOrNull?.school.name.isNotEmpty == true ? meAsync.value!.school.name : 'Home',
            overflow: TextOverflow.ellipsis),
        actions: const [AssistantButton(), NotificationBell()],
      ),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(schoolMeProvider)),
        data: (me) {
          if (!me.enabled) {
            return const _Message('The parent portal isn\'t available. Please contact the school office.');
          }
          if (me.children.isEmpty) {
            return const _Message('No child is linked to your account yet. Please ask the school office to link your child.');
          }
          final selectedId = ref.watch(selectedChildProvider);
          final child = me.children.firstWhere((c) => c.id == selectedId, orElse: () => me.children.first);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(schoolUnreadProvider);
              ref.invalidate(_todayProvider(child.id));
              ref.invalidate(_feesDueProvider);
              ref.invalidate(currentBannersProvider);
              ref.invalidate(schoolMeProvider);
              await ref.read(schoolMeProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _ChildHeader(child: child, all: me.children, school: me.school),
                const BannerCarousel(),
                const _Counters(),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                  child: _Tiles(child: child),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));
}

/// Child's avatar, name, class and teacher, today's status, and the "Children" switcher.
class _ChildHeader extends ConsumerWidget {
  const _ChildHeader({required this.child, required this.all, required this.school});
  final ChildSummary child;
  final List<ChildSummary> all;
  final SchoolInfo school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final a = ref.watch(_todayProvider(child.id)).valueOrNull;
    final att = a?.attendance;
    final (String status, PillTone tone) = att == null
        ? ('Not checked in yet', PillTone.neutral)
        : att.absent
            ? ('Absent today', PillTone.bad)
            : att.checkOut != null
                ? ('Went home ${att.checkOut}', PillTone.info)
                : ('At school since ${att.checkIn}', PillTone.good);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Tap to add / change the child's photo (refreshes "me" so every screen shows it)
        EditableAvatar(
          kind: 'students',
          id: child.id,
          version: child.photoUpdatedAt,
          name: child.fullName,
          radius: 30,
          onChanged: (_) => ref.invalidate(schoolMeProvider),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(child.fullName, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              [
                child.className == null ? 'No class yet' : 'Class ${child.className}',
                if (child.classTeacherName != null) child.classTeacherName!,
              ].join(' · '),
              style: text.bodyMedium,
            ),
            if (school.name.isNotEmpty) Text(school.name, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Pill(status, tone: tone),
              if (a?.report != null) const Pill('Daily report ready', tone: PillTone.good),
            ]),
          ]),
        ),
        if (all.length > 1)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () async {
              final id = await showModalBottomSheet<int>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                    for (final c in all)
                      ListTile(
                        leading: SchoolAvatar(kind: 'students', id: c.id, version: c.photoUpdatedAt, name: c.fullName),
                        title: Text(c.fullName),
                        subtitle: Text(c.className == null ? 'No class yet' : 'Class ${c.className}'),
                        trailing: c.id == child.id ? Icon(Icons.check, color: scheme.primary) : null,
                        onTap: () => Navigator.pop(ctx, c.id),
                      ),
                  ]),
                ),
              );
              if (id != null) ref.read(selectedChildProvider.notifier).state = id;
            },
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Children'),
          ),
      ]),
    );
  }
}

/// Unread messages · Unread news · Fees due. Each opens its tab.
class _Counters extends ConsumerWidget {
  const _Counters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(schoolUnreadProvider).valueOrNull;
    final due = ref.watch(_feesDueProvider).valueOrNull ?? 0;
    final m = unread?.messages ?? 0, a = unread?.announcements ?? 0;
    return HomeCounters(counters: [
      HomeCounter('Unread messages', '$m', highlight: m > 0, onTap: () => context.go(Routes.parentMessages)),
      HomeCounter('Unread news', '$a', highlight: a > 0, onTap: () => context.go(Routes.parentAnnouncements)),
      HomeCounter('Fees due', due > 0 ? Fmt.money(due) : 'RM 0', highlight: due > 0, onTap: () => context.go(Routes.parentFees)),
    ]);
  }
}

class _Tiles extends ConsumerWidget {
  const _Tiles({required this.child});
  final ChildSummary child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(schoolUnreadProvider).valueOrNull;
    final dayRoute = '${Routes.schoolChild}/${child.id}';

    return HomeTileGrid(tiles: [
      HomeTile('Today', Icons.wb_sunny_outlined, TileColors.today, () => context.push(dayRoute)),
      HomeTile('Daily report', Icons.photo_library_outlined, TileColors.report, () => context.push('$dayRoute?view=report')),
      HomeTile('Attendance', Icons.event_available_outlined, TileColors.attendance, () => context.push('$dayRoute?view=attendance')),
      HomeTile('Absence / pickup', Icons.edit_note_outlined, TileColors.note, () => context.push('$dayRoute?view=notes')),
      HomeTile('Timetable', Icons.schedule_outlined, TileColors.teacher, () => context.push('${Routes.schoolTimetable}?student=${child.id}')),
      HomeTile('Stories', Icons.collections_outlined, TileColors.report, () => context.push(Routes.schoolStories)),
      HomeTile('Messages', Icons.forum_outlined, TileColors.messages, () => context.go(Routes.parentMessages),
          badge: unread?.messages ?? 0),
      HomeTile('Message teacher', Icons.person_outline, TileColors.teacher,
          () => startNewConversation(context, ref, studentId: child.id, kind: 'Teacher')),
      HomeTile('Message office', Icons.business_outlined, TileColors.office,
          () => startNewConversation(context, ref, studentId: child.id, kind: 'Office')),
      HomeTile('News', Icons.campaign_outlined, TileColors.news, () => context.go(Routes.parentAnnouncements),
          badge: unread?.announcements ?? 0),
      HomeTile('Fees', Icons.receipt_long_outlined, TileColors.fees, () => context.go(Routes.parentFees)),
      HomeTile('Help', Icons.support_agent_outlined, TileColors.help, () => context.push(Routes.assistant)),
      HomeTile('School', Icons.school_outlined, TileColors.school, () => openSchoolInfo(context)),
      HomeTile('Account', Icons.account_circle_outlined, TileColors.account, () => context.go(Routes.parentAccount)),
    ]);
  }
}

/// Opens the school's details page (logo, address, phone, website).
void openSchoolInfo(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchoolInfoScreen()));

/// The school's details from Company Settings: logo, name, address, phone, website.
class SchoolInfoScreen extends ConsumerWidget {
  const SchoolInfoScreen({super.key});

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, 'Could not open $uri', error: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(schoolMeProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('School')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(schoolMeProvider)),
        data: (me) {
          final s = me.school;
          final logo = _serverUrl(ref, s.logoUrl);
          final website = s.website == null
              ? null
              : Uri.parse(s.website!.startsWith('http') ? s.website! : 'https://${s.website}');
          final phone = s.phone?.replaceAll(RegExp(r'[^0-9+]'), '');
          return ListView(padding: const EdgeInsets.all(16), children: [
            Center(
              child: logo != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(logo, height: 110, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(Icons.school, size: 80, color: scheme.primary)),
                    )
                  : CircleAvatar(
                      radius: 44,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(Icons.school, size: 48, color: scheme.primary)),
            ),
            const SizedBox(height: 12),
            Text(s.name.isEmpty ? 'Our school' : s.name,
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              child: Column(children: [
                if (s.address != null)
                  ListTile(leading: Icon(Icons.place_outlined, color: scheme.primary), title: Text(s.address!)),
                if (phone != null && phone.isNotEmpty) ...[
                  if (s.address != null) const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.call_outlined, color: scheme.primary),
                    title: Text(s.phone!),
                    subtitle: const Text('Tap to call'),
                    onTap: () => _launch(context, Uri(scheme: 'tel', path: phone)),
                  ),
                ],
                if (website != null) ...[
                  if (s.address != null || phone != null) const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.language, color: scheme.primary),
                    title: Text(s.website!),
                    subtitle: const Text('Open the school website'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _launch(context, website),
                  ),
                ],
                if (s.address == null && phone == null && website == null)
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('The school hasn\'t added its contact details yet.'),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(Icons.business_outlined, color: scheme.primary),
                  title: const Text('Message the school office'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => startNewConversation(context, ref, kind: 'Office'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.support_agent_outlined, color: scheme.primary),
                  title: const Text('Help assistant'),
                  subtitle: const Text('Fees, absence, pickup and more'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.assistant),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
