import 'package:flutter/material.dart';

// Shared look for the home screens (parent, teacher/employee, admin): a row of counters and a
// grid of big tiles with an icon in a soft coloured circle.

/// Tile colours, so the same kind of tile has the same colour on every home screen.
class TileColors {
  TileColors._();
  static const today = Color(0xFFF59E0B);
  static const report = Color(0xFFEC4899);
  static const attendance = Color(0xFF10B981);
  static const note = Color(0xFFEF4444);
  static const messages = Color(0xFF6366F1);
  static const teacher = Color(0xFF3B82F6);
  static const office = Color(0xFF8B5CF6);
  static const news = Color(0xFFF97316);
  static const fees = Color(0xFF14B8A6);
  static const help = Color(0xFF0EA5E9);
  static const school = Color(0xFFA855F7);
  static const account = Color(0xFF64748B);
  static const people = Color(0xFF0D9488);
  static const payroll = Color(0xFF16A34A);
  static const reports = Color(0xFF7C3AED);
  static const settings = Color(0xFF475569);
  static const leave = Color(0xFF0891B2);
}

/// One big tile: icon in a soft coloured circle, label under it, optional badge.
class HomeTile {
  const HomeTile(this.label, this.icon, this.color, this.onTap, {this.badge = 0});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int badge;
}

/// A grid of [HomeTile]s that fits the screen width (4 across on most phones).
class HomeTileGrid extends StatelessWidget {
  const HomeTileGrid({super.key, required this.tiles});
  final List<HomeTile> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisExtent: 112,
        crossAxisSpacing: 4,
        mainAxisSpacing: 8,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => _TileView(tile: tiles[i]),
    );
  }
}

class _TileView extends StatelessWidget {
  const _TileView({required this.tile});
  final HomeTile tile;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: tile.onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Badge(
          isLabelVisible: tile.badge > 0,
          label: Text(tile.badge > 99 ? '99+' : '${tile.badge}'),
          offset: const Offset(-4, 4),
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tile.color.withValues(alpha: 0.14)),
            child: Icon(tile.icon, size: 30, color: tile.color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tile.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ]),
    );
  }
}

/// One number in the counters row ("3 · Leave to approve").
class HomeCounter {
  const HomeCounter(this.label, this.value, {this.highlight = false, this.onTap});
  final String label;
  final String value;
  final bool highlight;
  final VoidCallback? onTap;
}

/// A row of [HomeCounter]s separated by thin lines; highlighted values use the primary colour.
class HomeCounters extends StatelessWidget {
  const HomeCounters({super.key, required this.counters});
  final List<HomeCounter> counters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cells = <Widget>[];
    for (var i = 0; i < counters.length; i++) {
      final c = counters[i];
      if (i > 0) cells.add(SizedBox(height: 32, child: VerticalDivider(width: 1, color: scheme.outlineVariant)));
      cells.add(Expanded(
        child: InkWell(
          onTap: c.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text(c.value,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: c.highlight ? scheme.primary : scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(c.label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center, maxLines: 2),
            ]),
          ),
        ),
      ));
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: cells));
  }
}

/// Small heading above a tile group ("School", "My work").
class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
