import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/app_router.dart';

/// A highlight card from GET dashboard/highlights (same cards as the website's admin home).
class HighlightCard {
  const HighlightCard({required this.key, required this.group, required this.icon, required this.tone,
      required this.title, required this.text, this.page, this.action});
  final String key;
  /// 'hr' or 'school'.
  final String group;
  final String icon;
  /// 'bad' (broken), 'warn' (to do), 'good', 'info'.
  final String tone;
  final String title;
  final String text;
  final String? page;
  final String? action;

  factory HighlightCard.fromJson(Map<String, dynamic> j) => HighlightCard(
        key: j['key'] as String? ?? '',
        group: j['group'] as String? ?? 'hr',
        icon: j['icon'] as String? ?? '',
        tone: j['tone'] as String? ?? 'info',
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        page: j['page'] as String?,
        action: j['action'] as String?,
      );
}

final highlightsProvider = FutureProvider.autoDispose<List<HighlightCard>>((ref) async {
  final r = await ref.watch(dioProvider).get<List<dynamic>>('dashboard/highlights');
  return (r.data ?? const []).map((e) => HighlightCard.fromJson(e as Map<String, dynamic>)).toList();
});

/// A card's page key → this app's screen.
String? highlightRoute(String? page) => switch (page) {
      'approvals' => Routes.adminApprovals,
      'approvals-attendance' => '${Routes.adminApprovals}?tab=attendance',
      'payroll' => Routes.adminPayroll,
      'pickup-people' => Routes.schoolPickupPeople,
      'school-fees' => Routes.schoolFees,
      'school-messages' => Routes.schoolMessages,
      'school-attendance' => Routes.schoolAttendance,
      'chatbot' => Routes.chatbotAdmin,
      'holidays' => Routes.holidaysMaster,
      'employees' => Routes.adminEmployees,
      _ => null,
    };

const _icons = <String, IconData>{
  'leave': Icons.event_busy_outlined,
  'attendance': Icons.history_toggle_off,
  'payroll': Icons.payments_outlined,
  'pickup': Icons.how_to_reg_outlined,
  'fees': Icons.receipt_long_outlined,
  'messages': Icons.forum_outlined,
  'ai': Icons.smart_toy_outlined,
  'children': Icons.child_care_outlined,
  'holiday': Icons.celebration_outlined,
  'birthday': Icons.cake_outlined,
  'done': Icons.task_alt,
};

const _tones = <String, List<Color>>{
  'warn': [Color(0xFFF59E0B), Color(0xFFEA580C)],
  'bad': [Color(0xFFEF4444), Color(0xFFB91C1C)],
  'good': [Color(0xFF22C55E), Color(0xFF15803D)],
  'info': [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
};

/// Sliding highlights at the top of the admin home: one card at a time, moving on every few
/// seconds (paused while touched), swipeable, with dots. Tapping a card opens its screen.
class HighlightsCarousel extends ConsumerStatefulWidget {
  const HighlightsCarousel({super.key});

  @override
  ConsumerState<HighlightsCarousel> createState() => _HighlightsCarouselState();
}

class _HighlightsCarouselState extends ConsumerState<HighlightsCarousel> {
  static const _every = Duration(seconds: 5);
  final _page = PageController(viewportFraction: 0.94);
  Timer? _timer;
  int _index = 0;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_every, (_) => _next());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _next() {
    final n = ref.read(highlightsProvider).valueOrNull?.length ?? 0;
    if (_touching || n < 2 || !_page.hasClients) return;
    final next = (_index + 1) % n;
    if (next == 0) {
      _page.jumpToPage(0);
    } else {
      _page.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(highlightsProvider).valueOrNull ?? const <HighlightCard>[];
    if (cards.isEmpty) return const SizedBox.shrink();
    if (_index >= cards.length) _index = 0;

    return Column(children: [
      SizedBox(
        height: 132,
        child: Listener(
          onPointerDown: (_) => _touching = true,
          onPointerUp: (_) => _touching = false,
          onPointerCancel: (_) => _touching = false,
          child: PageView.builder(
            controller: _page,
            itemCount: cards.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _Card(card: cards[i]),
          ),
        ),
      ),
      if (cards.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < cards.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _index ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
        ),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card});
  final HighlightCard card;

  @override
  Widget build(BuildContext context) {
    final route = highlightRoute(card.page);
    final colors = _tones[card.tone] ?? _tones['info']!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: InkWell(
            onTap: route == null ? null : () => Routes.open(GoRouter.of(context), route),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(14)),
                  child: Icon(_icons[card.icon] ?? Icons.info_outline, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(card.group == 'school' ? 'SCHOOL' : 'HR',
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8)),
                    const SizedBox(height: 2),
                    Text(card.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(card.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
                if (route != null) const Icon(Icons.chevron_right, color: Colors.white),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
