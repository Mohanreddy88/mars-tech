import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../data/banners.dart';
import 'messages_screens.dart';
import 'school_widgets.dart';

/// Gradient colours of each banner theme (same as the website).
const bannerColors = <String, List<Color>>{
  'purple': [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  'blue': [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
  'green': [Color(0xFF22C55E), Color(0xFF15803D)],
  'orange': [Color(0xFFF59E0B), Color(0xFFEA580C)],
  'pink': [Color(0xFFEC4899), Color(0xFFBE185D)],
  'teal': [Color(0xFF14B8A6), Color(0xFF0F766E)],
};

/// A banner page key → this app's parent screen.
String? bannerRoute(String? link) => switch (link) {
      'fees' => Routes.parentFees,
      'messages' => Routes.parentMessages,
      'announcements' => Routes.parentAnnouncements,
      'account' => Routes.parentAccount,
      _ => null,
    };

/// The icon of a card without a picture: from its link, else its colour (same as the website).
IconData bannerIcon(SchoolBanner b) => switch (b.link) {
      'fees' => Icons.receipt_long_outlined,
      'messages' || 'new-message' => Icons.forum_outlined,
      'announcements' => Icons.campaign_outlined,
      'account' => Icons.badge_outlined,
      _ => switch (b.theme) {
          'orange' => Icons.palette_outlined,
          'pink' => Icons.celebration_outlined,
          'blue' => Icons.restaurant_outlined,
          'green' => Icons.sentiment_satisfied_alt_outlined,
          'teal' => Icons.payments_outlined,
          _ => Icons.auto_awesome_outlined,
        },
    };

/// Opens what a banner's button points to.
Future<void> openBanner(BuildContext context, WidgetRef ref, SchoolBanner b) async {
  final link = b.link;
  if (link == null) return;
  if (b.external) {
    final ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, 'Could not open the link.', error: true);
  } else if (link == 'new-message') {
    await startNewConversation(context, ref);
  } else {
    final route = bannerRoute(link);
    if (route != null) Routes.open(GoRouter.of(context), route);
  }
}

/// Advert-style banners at the top of the parent home (School → Banners): one at a time, sliding
/// on every few seconds (paused while touched), swipeable, with dots. Same as the website.
class BannerCarousel extends ConsumerStatefulWidget {
  const BannerCarousel({super.key});

  @override
  ConsumerState<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<BannerCarousel> {
  static const _every = Duration(seconds: 6);
  final _page = PageController(viewportFraction: 0.86);
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
    final n = ref.read(currentBannersProvider).valueOrNull?.length ?? 0;
    if (_touching || n < 2 || !_page.hasClients) return;
    final next = (_index + 1) % n;
    if (next == 0) {
      _page.jumpToPage(0);
    } else {
      _page.animateToPage(next, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(currentBannersProvider).valueOrNull ?? const <SchoolBanner>[];
    if (banners.isEmpty) return const SizedBox.shrink();
    if (_index >= banners.length) _index = 0;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(children: [
        SizedBox(
          height: 190,
          child: Listener(
            onPointerDown: (_) => _touching = true,
            onPointerUp: (_) => _touching = false,
            onPointerCancel: (_) => _touching = false,
            child: PageView.builder(
              controller: _page,
              padEnds: false,
              itemCount: banners.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: BannerSlide(banner: banners[i], onOpen: () => openBanner(context, ref, banners[i])),
              ),
            ),
          ),
        ),
        if (banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < banners.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _index ? scheme.primary : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// One banner: the theme's gradient, the picture on the right fading into it (or decorative
/// circles), headline, text and a white pill button. [localImage] replaces the saved picture
/// (the admin form's preview); [onOpen] null = the button does nothing.
class BannerSlide extends ConsumerWidget {
  const BannerSlide({super.key, required this.banner, this.onOpen, this.localImage, this.useSavedImage = true});

  final SchoolBanner banner;
  final VoidCallback? onOpen;
  final Uint8List? localImage;
  final bool useSavedImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = bannerColors[banner.theme] ?? bannerColors['purple']!;
    final dark = colors[1];
    final v = banner.imageVersion;
    final Uint8List? image = localImage ??
        (useSavedImage && v != null ? ref.watch(bannerImageProvider((banner.id, v))).valueOrNull : null);
    final hasButton = banner.link != null && (banner.buttonText?.isNotEmpty ?? false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Stack(fit: StackFit.expand, children: [
          if (image != null) ...[
            Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [dark, dark.withValues(alpha: .75), dark.withValues(alpha: .15)],
                  stops: const [0, .5, 1],
                ),
              ),
            ),
          ] else ...[
            Positioned(right: -50, top: -80, child: _circle(220, .14)),
            Positioned(right: 110, bottom: -70, child: _circle(130, .10)),
            Positioned(right: 16, top: 14, child: Icon(bannerIcon(banner), color: Colors.white, size: 38)),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Padding(
                padding: const EdgeInsets.only(right: 44),
                child: Text(banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.15)),
              ),
              if (banner.text?.isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Text(banner.text!,
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
              if (hasButton) ...[
                const SizedBox(height: 12),
                Material(
                  color: Colors.white,
                  shape: const StadiumBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(banner.buttonText!, style: TextStyle(color: dark, fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(width: 6),
                        Icon(banner.external ? Icons.open_in_new : Icons.arrow_forward, color: dark, size: 16),
                      ]),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  static Widget _circle(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
      );
}
