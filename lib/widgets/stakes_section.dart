import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/evening_ledger.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/moment_item.dart';

/// « Aujourd'hui en enjeux » (lot 2, maquette validée 2026-10-30) : le tableau
/// du jour (gagnés · en jeu · perdus, la journée qui avance) et la liste EN
/// JEU. Une ligne = un GESTE avec tout ce qu'il rapporte ; tap = ouvert sur
/// place (« CE QUE ÇA RAPPORTE », une jauge par gain), bouton = le faire.
const kStakeLose = kBAlert;
const kStakeTier = Color(0xFFE9C46A);
const kStakeHunt = kBAttention;
const kStakeObjective = Color(0xFF9B8AFB);
const kStakeSession = Color(0xFF5DADE2);

Color stakeGainColor(StakeGain g) {
  if (g.losesTonight) return kStakeLose;
  return switch (g.kind) {
    StakeGainKind.tierTonight => kStakeTier,
    StakeGainKind.series => kStakeTier,
    StakeGainKind.seriesTonight => kStakeLose,
    StakeGainKind.hunt => kStakeHunt,
    StakeGainKind.objective => kStakeObjective,
    StakeGainKind.session => kStakeSession,
    StakeGainKind.focus => kBPrimary,
    StakeGainKind.routine => kBText3,
  };
}

IconData stakeIcon(StakeGestureKind k) => switch (k) {
      StakeGestureKind.routine => Icons.loop_rounded,
      StakeGestureKind.activity => Icons.timer_outlined,
      StakeGestureKind.block => Icons.view_agenda_outlined,
      StakeGestureKind.action => Icons.check_circle_outline,
    };

/// Libellé du bouton d'un geste.
String stakeButtonLabel(StakeGesture g) => switch (g.kind) {
      StakeGestureKind.routine => '+1',
      StakeGestureKind.activity => 'Chrono',
      StakeGestureKind.block => 'Lancer',
      StakeGestureKind.action => 'Focus',
    };

/// Part de la journée active passée (8 h → 22 h par défaut), 0..1.
double dayElapsed(int livedNowMin, {int startMin = 8 * 60, int endMin = 22 * 60}) {
  if (endMin <= startMin) return 0;
  return ((livedNowMin - startMin) / (endMin - startMin)).clamp(0.0, 1.0);
}

/// Le tableau du jour : trois compteurs et la barre de la journée.
class StakeScoreboard extends StatelessWidget {
  final StakeBoard board;
  final double elapsed;
  /// Tap = la feuille des enjeux (Aujourd'hui mobile, 2026-10-30).
  final VoidCallback? onTap;
  const StakeScoreboard({super.key, required this.board, required this.elapsed, this.onTap});

  @override
  Widget build(BuildContext context) {
    final won = board.won.length, play = board.inPlay, lost = board.lost.length;
    final total = won + play + lost;
    Widget counter(int n, String label, Color c) => Expanded(
          child: Column(children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(label, style: const TextStyle(fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w700, color: kBText3)),
          ]),
        );
    return _tappable(onTap, Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('Ta journée', style: TextStyle(fontSize: 13, color: kBText3, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$total enjeu${total > 1 ? 'x' : ''}', style: const TextStyle(fontSize: 13, color: kBText, fontWeight: FontWeight.w700)),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20, color: kBText3),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          counter(won, 'GAGNÉS', kBPrimary),
          counter(play, 'EN JEU', kStakeHunt),
          counter(lost, lost > 1 ? 'PERDUS' : 'PERDU', kStakeLose),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: elapsed, minHeight: 6, backgroundColor: kBRaised, valueColor: const AlwaysStoppedAnimation(kBText3)),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('${(elapsed * 100).round()} % de la journée passée', style: const TextStyle(fontSize: 11.5, color: kBText3)),
          const Spacer(),
          if (total > 0) Text('tenu $won sur $total', style: const TextStyle(fontSize: 11.5, color: kBText3)),
        ]),
      ]),
    ));
  }
}

Widget _tappable(VoidCallback? onTap, Widget child) => onTap == null
    ? child
    : Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: child),
      );

/// La liste EN JEU, le reste replié par famille, puis gagné / perdu.
class StakesList extends StatefulWidget {
  final StakeBoard board;
  /// Faire le geste (+1, chrono, bloc, page focus).
  final void Function(Stake s) onRun;
  /// Ouvre la galerie des badges (lien d'un geste qui sert un badge).
  final VoidCallback? onOpenBadges;
  /// Le soir (lot 4) : le bilan porte gagné / perdu ; la liste ne garde que
  /// ce qui reste possible.
  final bool evening;
  const StakesList({super.key, required this.board, required this.onRun, this.onOpenBadges, this.evening = false});

  @override
  State<StakesList> createState() => _StakesListState();
}

class _StakesListState extends State<StakesList> {
  final _open = OpenItem();
  bool _restOpen = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.board;
    if (b.isEmpty || (widget.evening && b.inPlay == 0)) return const SizedBox.shrink();
    final ev = widget.evening;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (b.top.isNotEmpty) ...[
        _sec(ev ? 'ENCORE POSSIBLE CE SOIR' : 'EN JEU D’ICI CE SOIR', b.rest.isEmpty ? '${b.top.length}' : '${b.top.length} sur ${b.inPlay}'),
        for (final s in b.top) _item(s),
      ],
      if (b.rest.isNotEmpty) _restToggle(b.rest),
      if (_restOpen) ..._restList(b.rest),
      if (!ev && b.won.isNotEmpty) ...[
        _sec('GAGNÉ AUJOURD’HUI', '${b.won.length}'),
        _summary(Icons.check_rounded, kBPrimary, b.won.join(' · ')),
      ],
      if (!ev && b.lost.isNotEmpty) ...[
        _sec(b.lost.length > 1 ? 'PERDUS' : 'PERDU', '${b.lost.length}'),
        _summary(Icons.close_rounded, kStakeLose, b.lost.join(' · ')),
      ],
    ]);
  }

  Widget _sec(String t, String n) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Row(children: [
          Text(t, style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
          const SizedBox(width: 8),
          Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kBText4)),
        ]),
      );

  Widget _summary(IconData icon, Color c, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: kBSurface.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: kBText2, height: 1.35))),
        ]),
      );

  Widget _item(Stake s) {
    final id = s.gesture.key;
    final open = _open.isOpen(id, null);
    return KeyedSubtree(
      key: _open.keyFor(id),
      child: MomentItem(
        open: open,
        onToggle: () => _open.settle(id, () => setState(() => _open.toggle(id, null))),
        collapsed: _row(s),
        expanded: _card(s),
      ),
    );
  }

  Widget _button(Stake s, {bool big = false}) {
    final label = stakeButtonLabel(s.gesture);
    final c = s.losesTonight ? kStakeLose : kBPrimary;
    if (big) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c, foregroundColor: kBBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => widget.onRun(s),
          child: Text(s.gesture.kind == StakeGestureKind.routine ? '+1 · c’est fait' : label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      );
    }
    return SizedBox(
      height: 36,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          backgroundColor: c.withValues(alpha: .16),
          foregroundColor: c,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => widget.onRun(s),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }

  String _head(StakeGesture g) => g.progress == null || g.progress!.isEmpty ? g.title : '${g.title} · ${g.progress}';

  Widget _chip(StakeGain g) {
    final c = stakeGainColor(g);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
      child: Text(g.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _row(Stake s) {
    final edge = s.losesTonight ? kStakeLose.withValues(alpha: .35) : kBLine;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: edge)),
      child: Row(children: [
        Icon(stakeIcon(s.gesture.kind), size: 22, color: s.losesTonight ? kStakeLose : kBText2),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_head(s.gesture), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kBText)),
            const SizedBox(height: 5),
            Wrap(spacing: 5, runSpacing: 4, children: [for (final g in s.gains) _chip(g)]),
          ]),
        ),
        const SizedBox(width: 8),
        _button(s),
      ]),
    );
  }

  Widget _card(Stake s) {
    final g = s.gesture;
    final c = s.losesTonight ? kStakeLose : kBPrimary;
    final meta = [
      if (g.progress != null && g.progress!.isNotEmpty) g.progress!,
      '≈ ${fmtMin(g.costMin)}',
      if (g.project != null) g.project!.title,
    ].join(' · ');
    final servesBadge = s.gains.any((x) => x.kind == StakeGainKind.seriesTonight || x.kind == StakeGainKind.tierTonight || x.kind == StakeGainKind.series || x.kind == StakeGainKind.hunt);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(s.losesTonight ? 'EN JEU · SE PERD CE SOIR' : 'EN JEU',
                style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: s.losesTonight ? kStakeLose : kBText3)),
          ),
          _chip(s.gains.first),
        ]),
        const SizedBox(height: 8),
        Text(g.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kBText, height: 1.2)),
        const SizedBox(height: 4),
        Text(meta, style: const TextStyle(fontSize: 13, color: kBText3)),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text('CE QUE ÇA RAPPORTE  ${s.gains.length}', style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
        ),
        for (final gain in s.gains) _yield(gain),
        const SizedBox(height: 10),
        _button(s, big: true),
        if (servesBadge && widget.onOpenBadges != null)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: widget.onOpenBadges,
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text('Tous les badges'),
              style: TextButton.styleFrom(foregroundColor: kBText2),
            ),
          ),
      ]),
    );
  }

  Widget _yield(StakeGain g) {
    final c = stakeGainColor(g);
    final gauge = g.gauge;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: kBRaised.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(g.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c))),
          if (gauge != null)
            Text('${gauge.done} → ${gauge.after} / ${gauge.total}',
                style: const TextStyle(fontSize: 12, color: kBText2, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        if (gauge != null && gauge.total > 0) ...[
          const SizedBox(height: 6),
          StakeGauge(done: gauge.done, after: gauge.after, total: gauge.total, color: c),
        ],
        if (g.detail != null && g.detail!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(g.detail!, style: const TextStyle(fontSize: 12, color: kBText3, height: 1.3)),
        ],
      ]),
    );
  }

  Widget _restToggle(List<Stake> rest) {
    final counts = <String, int>{};
    for (final s in rest) {
      counts[s.family] = (counts[s.family] ?? 0) + 1;
    }
    final parts = [
      for (final (f, label) in kStakeRestFamilies)
        if ((counts[f] ?? 0) > 0) '${counts[f]} ${label.toLowerCase()}',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _restOpen = !_restOpen),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kBText4.withValues(alpha: .5))),
          child: Row(children: [
            Text(_restOpen ? '−' : '+', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kBText2)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${rest.length} autre${rest.length > 1 ? 's' : ''} en jeu', style: const TextStyle(fontWeight: FontWeight.w700, color: kBText)),
                  if (!_restOpen && parts.isNotEmpty) TextSpan(text: ' · $parts', style: const TextStyle(color: kBText3)),
                ]),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Icon(_restOpen ? Icons.expand_less : Icons.expand_more, color: kBText3),
          ]),
        ),
      ),
    );
  }

  List<Widget> _restList(List<Stake> rest) {
    final out = <Widget>[];
    for (final (f, label) in kStakeRestFamilies) {
      final group = rest.where((s) => s.family == f).toList();
      if (group.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
        child: Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText4)),
      ));
      for (final s in group) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_head(s.gesture), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kBText)),
                Text(s.gains.map((g) => g.label).join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: s.losesTonight ? kStakeLose : kBText3)),
              ]),
            ),
            const SizedBox(width: 8),
            _button(s),
          ]),
        ));
      }
    }
    return out;
  }
}

/// Jauge d'un gain : cases (≤ 14) ou barre ; la part « après ce geste » en
/// clair (ce soir).
class StakeGauge extends StatelessWidget {
  final int done;
  final int after;
  final int total;
  final Color color;
  const StakeGauge({super.key, required this.done, required this.after, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final d = done.clamp(0, total), a = after.clamp(0, total);
    if (total <= 14) {
      return Row(children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 8,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: i < d ? color : (i < a ? color.withValues(alpha: .35) : kBRaised),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ]);
    }
    return SizedBox(
      height: 8,
      child: LayoutBuilder(builder: (ctx, c) {
        final w = c.maxWidth;
        return Stack(children: [
          Container(decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(4))),
          Container(width: w * a / total, decoration: BoxDecoration(color: color.withValues(alpha: .35), borderRadius: BorderRadius.circular(4))),
          Container(width: w * d / total, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        ]);
      }),
    );
  }
}

/// Le bilan du soir (lot 4) : le tableau du jour retourné — gagnés, encore,
/// perdus ; AVANCÉ AUJOURD'HUI ; LAISSÉ FILER ; demain en jeu.
class EveningLedgerCard extends StatelessWidget {
  final EveningLedger ledger;
  /// Sur la page : seulement les compteurs, le détail est dans la feuille.
  final bool compact;
  final VoidCallback? onTap;
  const EveningLedgerCard({super.key, required this.ledger, this.compact = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = ledger;
    Widget counter(int n, String label, Color c) => Expanded(
          child: Column(children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(label, style: const TextStyle(fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w700, color: kBText3)),
          ]),
        );
    Widget sec(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
          child: Text(t, style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
        );
    Widget line(LedgerLine x, Color c) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              constraints: const BoxConstraints(minWidth: 52),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
              child: Text(x.figure, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText)),
                Text(x.sub, style: const TextStyle(fontSize: 12, color: kBText3, height: 1.3)),
              ]),
            ),
          ]),
        );
    return _tappable(onTap, Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('Ce soir · ta journée', style: TextStyle(fontSize: 13, color: kBText3, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (l.total > 0) Text('tenu ${l.won} sur ${l.total}', style: const TextStyle(fontSize: 13, color: kBText, fontWeight: FontWeight.w700)),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20, color: kBText3),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          counter(l.won, 'GAGNÉS', kBPrimary),
          counter(l.stillPossible.length, 'ENCORE', kStakeHunt),
          counter(l.lost, l.lost > 1 ? 'PERDUS' : 'PERDU', kStakeLose),
        ]),
        if (!compact && l.advanced.isNotEmpty) ...[sec('AVANCÉ AUJOURD’HUI'), for (final x in l.advanced) line(x, kBPrimary)],
        if (!compact && l.slipped.isNotEmpty) ...[sec('LAISSÉ FILER'), for (final x in l.slipped) line(x, kStakeLose)],
        if (!compact && (l.tomorrow.isNotEmpty || l.stillPossible.isNotEmpty)) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kBRaised.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
            child: Text.rich(
              TextSpan(children: [
                if (l.tomorrow.isNotEmpty) ...[
                  const TextSpan(text: 'Demain en jeu : ', style: TextStyle(fontWeight: FontWeight.w800, color: kBText)),
                  TextSpan(text: '${l.tomorrow.join(' · ')}. '),
                ],
                if (l.stillPossible.isNotEmpty) ...[
                  const TextSpan(text: 'Encore possible ce soir : ', style: TextStyle(fontWeight: FontWeight.w800, color: kBText)),
                  TextSpan(text: '${l.stillPossible.take(3).join(', ')}${l.stillPossible.length > 3 ? '…' : ''}.'),
                ],
              ]),
              style: const TextStyle(fontSize: 12.5, color: kBText2, height: 1.4),
            ),
          ),
        ],
      ]),
    ));
  }
}
