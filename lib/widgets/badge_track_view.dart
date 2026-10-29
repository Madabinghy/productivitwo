import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart';

/// Le graphique d'avancement d'un badge (2026-10) : une bande de cases, une
/// par unité (jour, semaine, relevé, session), de la plus ancienne à la plus
/// récente. Atteint = laiton, manqué = case sombre, neutre = contour, en
/// cours = contour vert d'accent. Légende courte sous la bande.
class BadgeTrackView extends StatelessWidget {
  final BadgeTrack track;
  final double cell;
  final Color text3;
  final bool showLegend;
  const BadgeTrackView({super.key, required this.track, this.cell = 12, required this.text3, this.showLegend = true});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [for (final c in track.cells) _cell(c)],
      ),
      const SizedBox(height: 6),
      Text(track.caption, style: TextStyle(fontSize: 12, color: text3)),
      if (showLegend) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 10, children: [
          for (final (state, label) in [
            (TrackCell.hit, track.hitLabel),
            (TrackCell.miss, track.missLabel),
            if (track.cells.contains(TrackCell.neutral)) (TrackCell.neutral, 'rien à tenir'),
            if (track.cells.contains(TrackCell.current)) (TrackCell.current, 'en cours'),
            if (track.cells.contains(TrackCell.bridged)) (TrackCell.bridged, 'rallumé (braise)'),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              _cell(state, size: 9),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: text3)),
            ]),
        ]),
      ],
    ]);
  }

  Widget _cell(TrackCell c, {double? size}) {
    final s = size ?? cell;
    final (Color? fill, Color border) = switch (c) {
      TrackCell.hit => (kBadgeBrass, kBadgeBrassDark),
      TrackCell.miss => (kBadgeLockedBand, kBadgeLockedRim),
      TrackCell.neutral => (null, kBadgeLockedRim),
      TrackCell.current => (null, kBadgeGaugeFill),
      TrackCell.future => (null, kBadgeLockedBand),
      TrackCell.bridged => (kEmberColor.withValues(alpha: .35), kEmberColor),
    };
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(s * .25),
        border: Border.all(color: border, width: c == TrackCell.current ? 1.5 : 1),
      ),
    );
  }
}
