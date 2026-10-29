import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/dashboard_tiles.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show FicheHeader;
import 'package:productivitwo_v1/widgets/embers_view.dart' show EmberLedgerPanel;
import 'package:productivitwo_v1/utils/embers.dart' show EmberLedger;
import 'package:productivitwo_v1/widgets/stakes_section.dart' show kStakeLose, kStakeTier, kStakeHunt, StakeGauge;

/// « TON TABLEAU DE BORD » (lot 3) : une tuile par vue, son état en une ligne,
/// tap = la vue complète.
class DashboardTiles extends StatelessWidget {
  final ProgramTile? program;
  final DashTile? routines;
  final DashTile? objectives;
  final DashTile? badges;
  final DashTile? actions;
  final DashTile? projects;
  final VoidCallback? onProgram;
  final VoidCallback? onRoutines;
  final VoidCallback? onObjectives;
  final VoidCallback? onBadges;
  final VoidCallback? onActions;
  final VoidCallback? onProjects;
  /// Web large : toutes les tuiles sur une rangée (Programme et Projets
  /// deux fois plus larges), sans titre de section.
  final bool row;
  const DashboardTiles({
    super.key,
    this.row = false,
    this.program,
    this.routines,
    this.objectives,
    this.badges,
    this.actions,
    this.projects,
    this.onProgram,
    this.onRoutines,
    this.onObjectives,
    this.onBadges,
    this.onActions,
    this.onProjects,
  });

  @override
  Widget build(BuildContext context) {
    final small = <(DashTile, VoidCallback?)>[
      if (routines != null) (routines!, onRoutines),
      if (objectives != null) (objectives!, onObjectives),
      if (badges != null) (badges!, onBadges),
      if (actions != null) (actions!, onActions),
    ];
    if (row) {
      final all = <(DashTile, VoidCallback?, int)>[
        if (program != null) (program!, onProgram, 2),
        for (final t in small) (t.$1, t.$2, 1),
        if (projects != null) (projects!, onProjects, 2),
      ];
      if (all.isEmpty) return const SizedBox.shrink();
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, t) in all.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(flex: t.$3, child: _Tile(tile: t.$1, onTap: t.$2)),
          ],
        ]),
      );
    }
    final rows = <Widget>[
      if (program != null) _Tile(tile: program!, onTap: onProgram),
      for (var i = 0; i < small.length; i += 2)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Tile(tile: small[i].$1, onTap: small[i].$2)),
            const SizedBox(width: 8),
            Expanded(child: i + 1 < small.length ? _Tile(tile: small[i + 1].$1, onTap: small[i + 1].$2) : const SizedBox()),
          ]),
        ),
      if (projects != null) _Tile(tile: projects!, onTap: onProjects),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Text('TON TABLEAU DE BORD', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
      ),
      for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: r),
    ]);
  }
}

Color _markColor(TileMark m) => switch (m) {
      TileMark.on => kBPrimary,
      TileMark.warn => kStakeHunt,
      TileMark.current => kStakeTier,
      TileMark.off => kBRaised,
    };

class _Tile extends StatelessWidget {
  final DashTile tile;
  final VoidCallback? onTap;
  const _Tile({required this.tile, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = tile;
    return Material(
      color: kBSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: kBLine)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(t.label, style: const TextStyle(fontSize: 10.5, letterSpacing: .9, fontWeight: FontWeight.w800, color: kBText3)),
              const Spacer(),
              if (t.badge != null)
                Flexible(child: Text(t.badge!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kBText4, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 6),
            if (t is! ProgramTile)
              Text(t.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kBText, height: 1.15)),
            if (t is ProgramTile) ...[
              Text(t.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText)),
              const SizedBox(height: 6),
              Row(children: [
                for (final (i, p) in t.strip.indexed)
                  Expanded(
                    flex: p.durationMin.clamp(5, 600),
                    child: Container(
                      height: 10,
                      margin: EdgeInsets.only(right: i == t.strip.length - 1 ? 0 : 2),
                      decoration: BoxDecoration(
                        color: p.mark == TileMark.current ? kStakeTier.withValues(alpha: .25) : _markColor(p.mark),
                        borderRadius: BorderRadius.circular(3),
                        border: p.mark == TileMark.current ? Border.all(color: kStakeTier, width: 1.5) : null,
                      ),
                    ),
                  ),
              ]),
            ] else if (t.mini.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                for (final (i, m) in t.mini.indexed)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: i == t.mini.length - 1 ? 0 : 3),
                      decoration: BoxDecoration(color: _markColor(m), borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 6),
            Text(t.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kBText3, height: 1.3)),
          ]),
        ),
      ),
    );
  }
}

/// Écran « Badges en jeu » : tout ce qui bouge aujourd'hui, trié comme la
/// liste EN JEU (se perd ce soir, palier ce soir, chasses), puis les plus
/// proches. Bouton = le geste ; « Tous les badges » = la galerie.
class BadgesInPlayScreen extends StatelessWidget {
  final BadgesInPlay data;
  final void Function(Stake s)? onRun;
  final VoidCallback? onAll;
  /// Feuille (`showFiche`, Aujourd'hui mobile) : liste sans Scaffold, sur le
  /// défilement de la feuille, avec l'en-tête des fiches.
  final ScrollController? sheetScroll;
  /// Braises : réserve et historique en tête (null = pas de bloc).
  final EmberLedger? embers;
  final Map<String, String> names;
  const BadgesInPlayScreen({super.key, required this.data, this.onRun, this.onAll, this.sheetScroll, this.embers, this.names = const {}});

  @override
  Widget build(BuildContext context) {
    Widget fam(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
          child: Text(t, style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
        );
    Widget stakeRow((Stake, StakeGain) e, Color c, String pill) {
      final (s, g) = e;
      return _BadgeLine(
        color: c,
        title: s.gesture.title,
        sub: [g.label, if (s.gesture.progress != null) s.gesture.progress!].join(' · '),
        pill: pill,
        gauge: g.gauge,
        action: onRun == null
            ? null
            : () {
                onRun!(s);
                Navigator.of(context).maybePop();
              },
        actionLabel: switch (s.gesture.kind) {
          StakeGestureKind.routine => '+1',
          StakeGestureKind.activity => 'Chrono',
          StakeGestureKind.block => 'Lancer',
          StakeGestureKind.action => 'Focus',
        },
      );
    }

    final sheet = sheetScroll != null;
    final list = ListView(
        controller: sheetScroll,
        padding: sheet ? const EdgeInsets.fromLTRB(20, 14, 20, 32) : const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (sheet) FicheHeader(title: 'Badges en jeu', chip: '${data.today} aujourd’hui', chipColor: kStakeHunt),
          if (embers case final e?) EmberLedgerPanel(ledger: e, names: names),
          if (data.today == 0)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('Rien ne se joue ce soir côté badges.', style: TextStyle(color: kBText3, fontSize: 14)),
            ),
          if (data.losing.isNotEmpty) ...[fam('SE PERD CE SOIR'), for (final e in data.losing) stakeRow(e, kStakeLose, 'ce soir')],
          if (data.tiers.isNotEmpty) ...[fam('PALIER CE SOIR'), for (final e in data.tiers) stakeRow(e, kStakeTier, '+1 palier')],
          if (data.hunts.isNotEmpty) ...[fam('CHASSES'), for (final e in data.hunts) stakeRow(e, kStakeHunt, 'chasse')],
          if (data.near.isNotEmpty) ...[
            fam('PROCHES'),
            for (final b in data.near)
              _BadgeLine(
                color: kBText3,
                title: b.def.name,
                sub: '${b.value.toInt()} / ${b.nextTarget} ${b.def.unit}'.trim(),
                pill: '${(b.value / b.nextTarget! * 100).round()} %',
                gauge: (done: b.value.toInt(), after: b.value.toInt(), total: b.nextTarget!),
              ),
          ],
          if (onAll != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAll,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Tous les badges'),
              style: OutlinedButton.styleFrom(foregroundColor: kBText2, minimumSize: const Size.fromHeight(44)),
            ),
          ],
        ],
      );
    if (sheet) return list;
    return Scaffold(
      backgroundColor: kBBg,
      appBar: AppBar(
        backgroundColor: kBBg,
        foregroundColor: kBText,
        title: Text('Badges en jeu · ${data.today}'),
      ),
      body: list,
    );
  }
}

class _BadgeLine extends StatelessWidget {
  final Color color;
  final String title;
  final String sub;
  final String pill;
  final ({int done, int after, int total})? gauge;
  final VoidCallback? action;
  final String? actionLabel;
  const _BadgeLine({required this.color, required this.title, required this.sub, required this.pill, this.gauge, this.action, this.actionLabel});

  @override
  Widget build(BuildContext context) {
    final g = gauge;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBLine)),
      child: Row(children: [
        Container(width: 6, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
                child: Text(pill, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kBText3)),
            if (g != null && g.total > 0) ...[
              const SizedBox(height: 6),
              StakeGauge(done: g.done, after: g.after, total: g.total, color: color),
            ],
          ]),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(backgroundColor: color.withValues(alpha: .16), foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: action,
            child: Text(actionLabel ?? 'Faire', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
    );
  }
}
