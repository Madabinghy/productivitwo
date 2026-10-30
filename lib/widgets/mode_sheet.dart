import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show BadgeState;
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/elan_view.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show kRechargeValue;
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;
import 'package:productivitwo_v1/widgets/badge_painter.dart' show BadgeView;
import 'package:productivitwo_v1/widgets/elan_rows.dart' show elanColor;
import 'package:productivitwo_v1/run_session_store.dart';
import 'package:productivitwo_v1/utils/guerilla.dart' show kGuerillaKind;
import 'package:productivitwo_v1/utils/offensive.dart' show kOffensiveKind;
import 'package:productivitwo_v1/utils/run_session.dart' show PendingRun;
import 'package:productivitwo_v1/widgets/guerilla_screen.dart' show kGuerillaAccent, showGuerillaScreen;
import 'package:productivitwo_v1/widgets/offensive_screen.dart' show kOffensiveAccent, showOffensiveScreen;
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;

/// Feuille « Mode du jour » (lot 1 Modes et coups ; vue d'élan 2026-10,
/// maquette « Élan visible ») : trois postures en tête, puis AUJOURD'HUI par
/// créneau (ce qui a été fait après chaque pointage), CETTE SEMAINE (un point
/// par pointage à sa hauteur, moyenne, fenêtres de flemme gagnées), les 30
/// DERNIERS JOURS (cases, trois chiffres, tendance) et ce que ça vaut pour les
/// badges d'élan. Poser un mode ÉCRIT un pointage d'élan (zéro double saisie) ;
/// il expire à la bascule de journée vécue. [badges] (facultatif) évite de
/// relire les programmes et nourrit la section badges.
Future<void> showModeSheet(BuildContext context, AppLogic logic, {BadgeCenter? badges}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      minChildSize: .4,
      builder: (c, scroll) => _ModeSheetBody(logic: logic, badges: badges, scroll: scroll),
    ),
  );
}

class _ModeSheetBody extends StatefulWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  final ScrollController scroll;
  const _ModeSheetBody({required this.logic, required this.badges, required this.scroll});

  @override
  State<_ModeSheetBody> createState() => _ModeSheetBodyState();
}

class _ModeSheetBodyState extends State<_ModeSheetBody> {
  List<DailySchedule>? _schedules;

  @override
  void initState() {
    super.initState();
    widget.logic.addListener(_onLogic);
    _loadSchedules();
    RunSessionStore.live(widget.logic).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSchedules() async {
    final bc = widget.badges;
    if (bc != null) {
      try {
        await bc.load();
      } catch (_) {}
      if (mounted) setState(() => _schedules = bc.schedules);
      return;
    }
    final sync = widget.logic.sync;
    if (sync == null) {
      setState(() => _schedules = const []);
      return;
    }
    try {
      final now = DateTime.now();
      final s = await sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 61))), ymdOf(now));
      if (mounted) setState(() => _schedules = s);
    } catch (_) {
      if (mounted) setState(() => _schedules = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final logic = widget.logic;
    final cur = logic.mode;
    final st = logic.state;
    final now = DateTime.now();
    final schedules = _schedules ?? const <DailySchedule>[];
    final byYmd = {for (final s in schedules) s.date: s};
    // La nuit (recharge) ferme le dernier pointage du jour : elle ne pèse pas.
    final marks = logic.elanMarksWithRecharge(byYmd);
    final rechargeSince = logic.rechargeSinceNow;
    final doneActions = doneActionsOf(logic.currentProjects, st.activities);
    final days60 = buildElanDays(
        marks: marks, schedulesByYmd: byYmd, hits: st.habitHits, activities: st.activities, now: now, days: 60, dayStartMin: logic.dayStartMin,
        sessions: st.sessions, doneActions: doneActions);
    final week = days60.sublist(days60.length - 7);
    final wm = elanMetrics(week);
    final month = elanMonth(days60);
    final slots = todayElanSlots(
        marks: marks, schedule: byYmd[logic.livedTodayYmd], hits: st.habitHits, activities: st.activities, now: now, dayStartMin: logic.dayStartMin,
        sessions: st.sessions, doneActions: doneActions);
    final pointedToday = slots.where((s) => s.pointed).length;
    final text3 = cs.onSurface.withValues(alpha: .55);
    final hardest = hardestBucket(week);

    Widget title(String t, {String? right, Color? rightColor}) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: text3))),
            if (right != null) Text(right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: rightColor ?? text3)),
          ]),
        );

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        const Row(children: [
          Text('Mode du jour', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          InfoDot(kRuleModes),
        ]),
        const SizedBox(height: 2),
        Text('Une posture, changeable à tout moment. Elle pointe ton élan et repart en Normal demain.', style: TextStyle(fontSize: 12.5, color: text3)),
        if (rechargeSince != null) ...[
          const SizedBox(height: 12),
          RechargeBanner(since: rechargeSince, now: now),
        ],
        const SizedBox(height: 12),
        Row(children: [
          for (final m in DayMode.values) ...[
            if (m != DayMode.low) const SizedBox(width: 8),
            Expanded(child: _modeTile(cs, dark, m, selected: rechargeSince == null && m == cur, onTap: () {
              if (m != cur || rechargeSince != null) logic.setMode(m);
            })),
          ],
        ]),
        const SizedBox(height: 10),
        if (cur == DayMode.high) ...[_offensiveCard(cs), const SizedBox(height: 8), _guerillaCard(cs)] else ...[_guerillaCard(cs), const SizedBox(height: 8), _offensiveCard(cs)],
        title('AUJOURD’HUI', right: '${_dayLabel(now)} · ${pointedToday == 0 ? 'rien de pointé' : '$pointedToday créneau${pointedToday > 1 ? 'x' : ''} pointé${pointedToday > 1 ? 's' : ''}'}'),
        Row(children: [
          for (final s in slots) ...[
            if (s.bucket != 'matin') const SizedBox(width: 8),
            Expanded(child: _slotTile(cs, dark, s)),
          ],
        ]),
        const SizedBox(height: 10),
        ElanDayStrip(cells: elanTimeline(marks, now, logic.dayStartMin), dayStartMin: logic.dayStartMin),
        title('CETTE SEMAINE',
            right: wm.count == 0
                ? 'aucun pointage'
                : 'moyenne ${fmtElan(wm.mean)} · ${wm.slots} créneau${wm.slots > 1 ? 'x' : ''}${wm.count > wm.slots ? ' · ${wm.count} changements' : ''}',
            rightColor: wm.count == 0 ? null : kElanAccent),
        if (wm.count == 0)
          _note(cs, 'Pointe ton élan (le mode du jour suffit) : la semaine se dessinera ici, un point par pointage.')
        else ...[
          ElanWeekGraph(days: week, mean: wm.mean),
          const SizedBox(height: 8),
          _legend(cs),
        ],
        if (wm.lowCount > 0) ...[
          title('FACE À LA FLEMME', right: '${wm.lowWon} / ${wm.lowCount} · ${(wm.discipline! * 100).round()} %', rightColor: kPalierGreen),
          _note(cs,
              '${wm.lowCount} fenêtre${wm.lowCount > 1 ? 's' : ''} pointée${wm.lowCount > 1 ? 's' : ''} Flemme cette semaine, ${wm.lowWon} où tu as quand même fait quelque chose.'
              '${hardest == null ? '' : ' ${_bucketSentence(hardest)} est ton créneau difficile.'}'),
        ],
        title('30 DERNIERS JOURS', right: _schedules == null ? 'chargement…' : '${month.pointedDays} jour${month.pointedDays > 1 ? 's' : ''} pointé${month.pointedDays > 1 ? 's' : ''}'),
        ElanMonthGrid(month: month),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _stat(cs, month.mean == null ? '—' : fmtElan(month.mean!), 'élan moyen sur le mois')),
          const SizedBox(width: 8),
          Expanded(child: _stat(cs, '${month.lowDays} j', 'de flemme · ${month.lowDaysWon} gagné${month.lowDaysWon > 1 ? 's' : ''}')),
          const SizedBox(width: 8),
          Expanded(child: _stat(cs, '${month.highDays} j', 'en forme')),
        ]),
        if (trendLabel(month) case final tl?) ...[
          title('TENDANCE', right: tl, rightColor: month.delta! > 0.15 ? kPalierGreen : (month.delta! < -0.15 ? kPalierCoral : null)),
          _note(cs, _trendSentence(month)),
        ],
        if (widget.badges?.deck case final deck?) ...[
          title('CE QUE ÇA VAUT', right: 'badges d’élan'),
          for (final id in const ['maree-haute', 'vent-contraire', 'malgre-tout', 'barometre'])
            if (deck.byId(id) case final b?) _badgeRow(cs, b),
        ],
        const SizedBox(height: 10),
        Text('Des faits, un créneau, une suite. Rien ici ne juge la journée.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: text3)),
      ],
    );
  }

  Widget _modeTile(ColorScheme cs, bool dark, DayMode m, {required bool selected, required VoidCallback onTap}) {
    final c = modeChipColor(m, dark: dark);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: .14) : cs.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c.withValues(alpha: .6) : Colors.transparent),
        ),
        child: Column(children: [
          Icon(modeIcon(m), size: 20, color: selected ? c : cs.onSurface.withValues(alpha: .6)),
          const SizedBox(height: 4),
          Text(kModeLabels[m]!, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: selected ? c : cs.onSurface)),
          Text(_modeShort(m), textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: cs.onSurface.withValues(alpha: .55))),
        ]),
      ),
    );
  }

  /// Offensive : en forme, à fond — des coups de 10 / 15 min sur un front.
  Widget _offensiveCard(ColorScheme cs) {
    final p = _pending(kOffensiveKind);
    return _launchCard(
      cs,
      accent: kOffensiveAccent,
      lightAccent: const Color(0xFFB4532A),
      icon: Icons.north_east,
      title: p != null ? 'Reprendre l’offensive · ${p.done} coup${p.done > 1 ? 's' : ''}' : 'Offensive · en forme, à fond',
      sub: p != null ? 'Quittée en route : elle reprend au coup suivant.' : 'Des coups de 10 ou 15 min sur un projet, l’un après l’autre.',
      onTap: () => showOffensiveScreen(context, widget.logic, resume: p).then((_) => mounted ? setState(() {}) : null),
    );
  }

  /// La session en attente de ce mode, si elle est reprenable.
  PendingRun? _pending(String kind) {
    final p = RunSessionStore.current;
    return p != null && p.kind == kind && p.isLive(DateTime.now(), widget.logic.livedTodayYmd) ? p : null;
  }

  Widget _launchCard(ColorScheme cs,
      {required Color accent, required Color lightAccent, required IconData icon, required String title, required String sub, required VoidCallback onTap}) {
    return Material(
      color: accent.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: accent.withValues(alpha: .5))),
          child: Row(children: [
            Icon(icon, color: cs.brightness == Brightness.dark ? accent : lightAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
              ]),
            ),
            Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .5)),
          ]),
        ),
      ),
    );
  }

  /// Guérilla : pas bien, mais debout — des coups de 5 min, l'app choisit.
  Widget _guerillaCard(ColorScheme cs) {
    final p = _pending(kGuerillaKind);
    return _launchCard(
      cs,
      accent: kGuerillaAccent,
      lightAccent: const Color(0xFF5E6B2A),
      icon: Icons.bolt,
      title: p != null ? 'Reprendre la guérilla · ${p.done} coup${p.done > 1 ? 's' : ''}' : 'Guérilla · la flemme ou moi',
      sub: p != null ? 'Quittée en route : elle reprend au coup suivant.' : 'Pas bien, mais debout : des coups de 5 min, sans réfléchir.',
      onTap: () => showGuerillaScreen(context, widget.logic, resume: p).then((_) => mounted ? setState(() {}) : null),
    );
  }

  String _modeShort(DayMode m) => switch (m) { DayMode.low => 'petites choses', DayMode.normal => 'le programme', DayMode.high => 'deep work' };

  Widget _slotTile(ColorScheme cs, bool dark, ElanSlot s) {
    final c = s.value == null ? cs.onSurface.withValues(alpha: .15) : elanColor(s.value!);
    final text3 = cs.onSurface.withValues(alpha: .55);
    final String big;
    final String detail;
    if (s.value != null) {
      big = '${s.value} · ${kElanLabels[s.value!]}';
      detail = [
        'pointé ${_hm(s.at!)}',
        if (s.changes > 1) '${s.changes} changements',
        if (s.wins > 0) '${s.wins} chose${s.wins > 1 ? 's' : ''} faite${s.wins > 1 ? 's' : ''} ensuite' else if (s.value! <= 2) 'rien de fait ensuite',
      ].join(' · ');
    } else if (s.started) {
      big = 'pas pointé';
      detail = s.current ? 'c’est maintenant' : 'créneau passé';
    } else {
      big = 'pas encore';
      detail = 'à partir de ${s.startHour} h';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
        border: Border(top: BorderSide(color: c, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.label.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: .6, fontWeight: FontWeight.w700, color: s.current ? cs.primary : text3)),
        const SizedBox(height: 2),
        Text(big, style: TextStyle(fontSize: s.value != null ? 15 : 13, fontWeight: FontWeight.w800, color: s.value != null ? cs.onSurface : text3)),
        Text(detail, style: TextStyle(fontSize: 10.5, height: 1.25, color: text3)),
      ]),
    );
  }

  Widget _legend(ColorScheme cs) {
    final muted = cs.onSurface.withValues(alpha: .55);
    return Wrap(spacing: 12, runSpacing: 4, children: [
      for (var i = 1; i <= 5; i++)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: elanColor(i))),
          const SizedBox(width: 4),
          Text(kElanLabels[i], style: TextStyle(fontSize: 11, color: muted)),
        ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kPalierGreen, width: 2))),
        const SizedBox(width: 4),
        Text('gagnée', style: TextStyle(fontSize: 11, color: muted)),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 2, color: kElanAccent),
        const SizedBox(width: 4),
        Text('moyenne', style: TextStyle(fontSize: 11, color: muted)),
      ]),
    ]);
  }

  Widget _note(ColorScheme cs, String t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: TextStyle(fontSize: 12.5, height: 1.4, color: cs.onSurface.withValues(alpha: .8))),
      );

  Widget _stat(ColorScheme cs, String v, String l) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(l, style: TextStyle(fontSize: 10.5, height: 1.25, color: cs.onSurface.withValues(alpha: .55))),
        ]),
      );

  Widget _badgeRow(ColorScheme cs, BadgeState b) {
    final text3 = cs.onSurface.withValues(alpha: .55);
    final String sub;
    final String chip;
    switch (b.def.id) {
      case 'maree-haute':
        sub = '${b.value} jour${b.value == 1 ? '' : 's'} à élan ≥ 4 d’affilée · il en faut 7';
        chip = b.acquired ? 'obtenu' : '${b.value} / 7';
      case 'vent-contraire':
        sub = 'semaine solide à élan ≤ 2,5';
        chip = b.acquired ? 'obtenu' : (b.facts.where((f) => f.$1.startsWith('Jours solides à élan bas')).map((f) => f.$2).firstOrNull ?? 'pas encore');
      case 'malgre-tout':
        sub = 'victoires sur la flemme${b.nextTarget == null ? '' : ' · palier ${b.nextTarget}'}';
        chip = '${b.value}';
      default:
        sub = 'pointages d’élan${b.nextTarget == null ? '' : ' · palier ${b.nextTarget}'}';
        chip = b.nextTarget == null ? '${b.value}' : '${b.value} / ${b.nextTarget}';
    }
    return InkWell(
      onTap: () => showBadgeSheet(context, b, logic: widget.logic, facts: widget.badges?.todayFacts()),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          BadgeView(state: b, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.def.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(sub, style: TextStyle(fontSize: 11.5, color: text3)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(999)),
            child: Text(chip, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: b.acquired ? kPalierGreen : cs.onSurface.withValues(alpha: .75))),
          ),
        ]),
      ),
    );
  }

  String _trendSentence(ElanMonth m) {
    final weeks = weeklyMeans(m.days).where((w) => w.mean != null).toList();
    final parts = <String>[];
    if (weeks.length >= 2) {
      final lowest = weeks.reduce((a, b) => a.mean! <= b.mean! ? a : b);
      final last = weeks.last;
      parts.add('La semaine la plus basse était à ${fmtElan(lowest.mean!)}, la dernière est à ${fmtElan(last.mean!)}.');
    }
    final streak = m.pointedStreak;
    if (streak >= 3) parts.add('Aucun jour sans pointage depuis $streak jours : Baromètre avance.');
    return parts.isEmpty ? 'Les semaines se lisent en lignes dans la grille.' : parts.join(' ');
  }

  static String _hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  static String _dayLabel(DateTime d) {
    const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  static String _bucketSentence(String b) => switch (b) { 'matin' => 'Le matin', 'aprem' => 'L’après-midi', _ => 'Le soir' };
}

/// Accent des moyennes d'élan (ambre, comme le « pour l'instant » des badges).
const kElanAccent = Color(0xFFE0A23A);

/// Bande horaire du jour vécu (2026-10) : une case par quart d'heure, colorée
/// par l'élan en vigueur, vide avant le premier pointage et après maintenant ;
/// repères 8 h · 12 h · 18 h · 22 h. Calculée depuis l'historique des
/// changements, rien n'est échantillonné.
class ElanDayStrip extends StatelessWidget {
  final List<int?> cells;
  final int dayStartMin;
  const ElanDayStrip({super.key, required this.cells, required this.dayStartMin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: .45);
    final n = cells.length;
    final stepMin = n == 0 ? 15 : (24 * 60 / n).round();
    const marks = <int>[8 * 60, 12 * 60, 18 * 60, 22 * 60];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 14,
        child: Row(children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: .5),
                decoration: BoxDecoration(
                  color: cells[i] == null ? cs.onSurface.withValues(alpha: .07) : (cells[i] == kRechargeValue ? kRechargeColor : elanColor(cells[i]!)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 3),
      LayoutBuilder(builder: (_, c) {
        return SizedBox(
          height: 12,
          child: Stack(children: [
            for (final m in marks)
              Positioned(
                left: ((m - dayStartMin + 24 * 60) % (24 * 60)) / (24 * 60) * c.maxWidth - 8,
                child: Text('${m ~/ 60} h', style: TextStyle(fontSize: 9.5, color: muted)),
              ),
          ]),
        );
      }),
      const SizedBox(height: 2),
      Text('L\u2019élan en vigueur, $stepMin min par case : il suit le dernier pointage jusqu\u2019au suivant.', style: TextStyle(fontSize: 11, color: muted)),
    ]);
  }
}

/// La semaine en sept colonnes : un point par pointage à sa hauteur (1 → 5),
/// anneau vert = fenêtre de flemme gagnée, trait de moyenne.
class ElanWeekGraph extends StatelessWidget {
  final List<ElanDay> days;
  final double mean;
  const ElanWeekGraph({super.key, required this.days, required this.mean});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: .5);
    const h = 110.0;
    const dot = 9.0;
    final todayYmd = days.isEmpty ? '' : days.last.ymd;
    double yOf(num v) => h - (v - 1) / 4 * h;
    return SizedBox(
      height: h + 22,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 16,
          height: h,
          child: Stack(children: [
            for (var v = 1; v <= 5; v++)
              Positioned(top: yOf(v) - 6, left: 0, child: Text('$v', style: TextStyle(fontSize: 9.5, color: muted))),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, c) {
            final colW = c.maxWidth / days.length;
            return Stack(clipBehavior: Clip.none, children: [
              for (var v = 1; v <= 5; v++)
                Positioned(top: yOf(v), left: 0, right: 0, child: Container(height: 1, color: cs.onSurface.withValues(alpha: .06))),
              Positioned(top: yOf(mean), left: 0, right: 0, child: Container(height: 2, color: kElanAccent.withValues(alpha: .7))),
              Positioned(top: yOf(mean) - 14, right: 2, child: Text(fmtElan(mean), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: kElanAccent))),
              for (var i = 0; i < days.length; i++) ...[
                Positioned(
                  top: h + 6,
                  left: i * colW,
                  width: colW,
                  child: Text(_dayLetter(days[i].ymd), textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: days[i].ymd == todayYmd ? FontWeight.w800 : FontWeight.w500, color: days[i].ymd == todayYmd ? cs.onSurface : muted)),
                ),
                for (var k = 0; k < days[i].marks.length; k++)
                  Positioned(
                    top: yOf(days[i].marks[k].value) - dot / 2,
                    left: i * colW + colW / 2 - dot / 2 + (k - (days[i].marks.length - 1) / 2) * 6,
                    child: Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: elanColor(days[i].marks[k].value),
                        border: days[i].marks[k].value <= 2 && days[i].marks[k].won ? Border.all(color: kPalierGreen, width: 2) : null,
                      ),
                    ),
                  ),
              ],
            ]);
          }),
        ),
      ]),
    );
  }

  static String _dayLetter(String ymd) {
    const l = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    return l[DateTime.parse(ymd).weekday - 1];
  }
}

/// Les 30 derniers jours en cases (10 par ligne), colorées par l'élan moyen du
/// jour ; aujourd'hui encadré, jours sans pointage en pointillé. Tap = le jour.
class ElanMonthGrid extends StatelessWidget {
  final ElanMonth month;
  const ElanMonthGrid({super.key, required this.month});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = month.days;
    return LayoutBuilder(builder: (_, c) {
      const cols = 10;
      const gap = 4.0;
      final size = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < days.length; i++)
            Tooltip(
              message: _tip(days[i]),
              triggerMode: TooltipTriggerMode.tap,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: days[i].mean == null ? null : elanColor(days[i].mean!.round()),
                  border: i == days.length - 1
                      ? Border.all(color: cs.onSurface, width: 1.5)
                      : (days[i].mean == null ? Border.all(color: cs.onSurface.withValues(alpha: .15)) : null),
                ),
              ),
            ),
        ],
      );
    });
  }

  static String _tip(ElanDay d) {
    final date = DateTime.parse(d.ymd);
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    final head = '${date.day} ${months[date.month - 1]}';
    if (d.marks.isEmpty) return '$head · pas de pointage';
    final parts = d.marks.map((m) => '${kElanBucketLabels[m.bucket] ?? m.bucket} ${m.value}${m.value <= 2 ? (m.won ? ' ✓' : ' ·') : ''}').join(' · ');
    return '$head · moyenne ${fmtElan(d.mean!)} · $parts';
  }
}

/// Traînée du jour (2026-10) : trois points matin · aprem · soir, colorés à
/// la hauteur de l'élan pointé, vides sinon ; le créneau courant est cerclé.
class ElanTrail extends StatelessWidget {
  final List<int?> values;
  final int current;
  final Color empty;
  final Color ring;
  final double size;
  const ElanTrail({super.key, required this.values, required this.current, required this.empty, required this.ring, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < values.length; i++)
        Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: values[i] == null ? empty : elanColor(values[i]!),
              border: i == current ? Border.all(color: ring, width: 1) : null,
            ),
          ),
        ),
    ]);
  }
}

/// Pilule « Mode · Flemme ▾ » de la carte MAINTENANT et de la barre du haut :
/// le mode, puis la traînée des trois créneaux du jour. Tap = la feuille.
class ModePill extends StatelessWidget {
  final AppLogic logic;
  final BadgeCenter? badges;
  const ModePill({super.key, required this.logic, this.badges});

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    final m = logic.mode;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (logic.inRecharge) {
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showModeSheet(context, logic, badges: badges),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 3, 9, 3),
          decoration: BoxDecoration(
            color: kRechargeColor.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: kRechargeInk.withValues(alpha: .35)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bedtime_outlined, size: 12, color: kRechargeInk),
            SizedBox(width: 4),
            Text('Recharge', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4, color: kRechargeInk)),
          ]),
        ),
      );
    }
    final accent = modeAccentOverride(m, dark: dark);
    final fg = accent ?? pal.text3;
    final trail = todayElanValues(logic.state.moodMarks, DateTime.now(), logic.dayStartMin);
    final wins = m == DayMode.low ? _flemmeWinsToday(badges) : 0;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => showModeSheet(context, logic, badges: badges),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 3, 7, 3),
        decoration: BoxDecoration(
          color: accent == null ? pal.chip : accent.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(modeIcon(m), size: 12, color: fg),
          const SizedBox(width: 4),
          Text(kModeLabels[m]!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4, color: fg)),
          Container(width: 1, height: 10, margin: const EdgeInsets.symmetric(horizontal: 6), color: fg.withValues(alpha: .35)),
          if (wins > 0)
            Text('$wins victoire${wins > 1 ? 's' : ''}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg, fontFeatures: const [FontFeature.tabularFigures()]))
          else
            ElanTrail(values: trail.values, current: trail.current, empty: fg.withValues(alpha: .22), ring: fg),
        ]),
      ),
    );
  }
}

/// Victoires sur la flemme du jour (pilule du mode), recalculées au plus une
/// fois par minute : la pilule se redessine souvent.
int _flemmeWinsToday(BadgeCenter? badges) {
  if (badges == null) return 0;
  final now = DateTime.now();
  final key = now.millisecondsSinceEpoch ~/ 60000;
  if (key != _winsCacheKey) {
    _winsCacheKey = key;
    try {
      _winsCache = badges.todayFacts().disciplineWinsToday;
    } catch (_) {
      _winsCache = 0;
    }
  }
  return _winsCache;
}

int _winsCacheKey = -1;
int _winsCache = 0;

/// Chip « malgré tout » (fait en mode Flemme) ou « à fond » (En forme) pour une
/// chose validée à [doneAt]. Dérivé, jamais stocké. Null en Normal.
Widget? modeChipFor(BuildContext context, AppLogic logic, DateTime? doneAt) {
  if (doneAt == null) return null;
  final m = modeAt(logic.state.moodMarks, doneAt, logic.dayStartMin);
  if (m == DayMode.normal) return null;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final c = modeChipColor(m, dark: dark);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
    child: Text(m == DayMode.low ? 'malgré tout' : 'à fond',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
  );
}

/// Recharge : bleu nuit, hors de la rampe d'élan (qui se lit à la clarté).
const kRechargeColor = Color(0xFF2A3C58);
const kRechargeInk = Color(0xFFC9D8EE);

/// « En recharge depuis 22:40 » (feuille du mode).
class RechargeBanner extends StatelessWidget {
  final DateTime since;
  final DateTime now;
  const RechargeBanner({super.key, required this.since, required this.now});

  @override
  Widget build(BuildContext context) {
    final hm = '${since.hour.toString().padLeft(2, '0')}:${since.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kRechargeColor.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRechargeInk.withValues(alpha: .25)),
      ),
      child: Row(children: [
        const Icon(Icons.bedtime_outlined, size: 20, color: kRechargeInk),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('En recharge depuis $hm', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kRechargeInk)),
            Text('La nuit ne compte ni dans ton élan, ni dans la flemme. Choisis un mode pour démarrer.',
                style: TextStyle(fontSize: 12, height: 1.3, color: kRechargeInk.withValues(alpha: .8))),
          ]),
        ),
      ]),
    );
  }
}
