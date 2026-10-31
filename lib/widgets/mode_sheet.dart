import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show BadgeState;
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/elan_bands.dart';
import 'package:productivitwo_v1/utils/elan_view.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
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
    final text3 = cs.onSurface.withValues(alpha: .55);

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
          Text('Là, tu es comment ?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          InfoDot(kRuleModes),
        ]),
        const SizedBox(height: 2),
        Text('Un tap. L’app adapte ce qu’elle te propose, et ta semaine se dessine plus bas.', style: TextStyle(fontSize: 12.5, color: text3)),
        if (rechargeSince != null) ...[
          const SizedBox(height: 12),
          RechargeBanner(since: rechargeSince, now: now),
        ],
        const SizedBox(height: 12),
        // Les trois modes côte à côte (retour user : « trois choses qui vont ensemble »),
        // puis ce que l'app propose dans le mode choisi.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in DayMode.values) ...[
            if (m != DayMode.low) const SizedBox(width: 8),
            Expanded(
              child: _modeCard(cs, dark, m, selected: rechargeSince == null && m == cur, since: m == cur ? _sinceLabel(marks, now) : null, onTap: () {
                if (m != cur || rechargeSince != null) logic.setMode(m);
              }),
            ),
          ],
        ]),
        if (rechargeSince == null) ...[
          const SizedBox(height: 8),
          Text(_modePromise[cur]!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: text3)),
        ],
        const SizedBox(height: 10),
        if (cur == DayMode.high) ...[_offensiveCard(cs), const SizedBox(height: 8), _guerillaCard(cs)] else ...[_guerillaCard(cs), const SizedBox(height: 8), _offensiveCard(cs)],
        ..._winsSection(cs),
        title('CETTE SEMAINE', right: wm.count == 0 ? 'rien de dit' : 'dit ${saidDays(week)} j sur 7${_rollingLabel(days60)}'),
        ..._weekBands(cs, dark, marks, week, now),
        title('CE QUE ÇA T’APPREND', right: '30 jours'),
        ..._learnSection(cs, dark, marks, days60, now),
        title('30 DERNIERS JOURS', right: _schedules == null ? 'chargement…' : 'touche un jour'),
        ElanMonthGrid(month: month, onDay: (d) => showElanDaySheet(context, logic, marks: marks, day: d, badges: widget.badges)),
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

  /// « · élan 7 j 2,9 ↗ » : moyenne glissante sur 7 jours, comparée à hier.
  String _rollingLabel(List<ElanDay> days60) {
    final r = rollingElanMeans(days60, 2);
    final today = r.last;
    if (today == null) return '';
    final prev = r.first;
    final arrow = prev == null ? '' : (today - prev > 0.05 ? ' ↗' : (today - prev < -0.05 ? ' ↘' : ' →'));
    return ' · élan 7 j ${fmtElan(today)}$arrow';
  }

  /// « Ce que ça t'apprend » (maquette « Ton élan, autrement », PR 2) : ton
  /// creux, la flemme gagnée, la remontée après une guérilla, la tendance.
  List<Widget> _learnSection(ColorScheme cs, bool dark, List<MoodMark> marks, List<ElanDay> days60, DateTime now) {
    final logic = widget.logic;
    final last30 = days60.sublist(days60.length - 30);
    final cells30 = [for (final d in last30) elanCellsOfDay(marks, d.ymd, now, logic.dayStartMin)];
    final byMoment = lowByMoment(cells30, logic.dayStartMin);
    final hard = hardestMoment(byMoment);
    final windows = lowWindowsOf(last30);
    final rebound = guerillaRebound(logic.state.chainRuns, now.subtract(const Duration(days: 30)));
    final weekly = weeklyLowPct(cells30.sublist(cells30.length - 28));
    final low = modeChipColor(DayMode.low, dark: dark);
    final text2 = cs.onSurface.withValues(alpha: .7);
    final text3 = cs.onSurface.withValues(alpha: .55);
    Widget card(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
    Widget fact(String big, Color c, String title, String sub) => card([
          Row(children: [
            SizedBox(width: 78, child: Text(big, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(sub, style: TextStyle(fontSize: 12.5, color: text3)),
              ]),
            ),
          ]),
        ]);
    const momentLabel = {'matin': 'matin', 'aprem': 'après-midi', 'soir': 'soir'};
    final maxM = byMoment.values.fold<int>(0, (a, b) => a > b ? a : b);
    final out = <Widget>[];
    if (hard != null) {
      out.add(card([
        Text('Ton creux : ${hard == 'matin' ? 'le matin' : (hard == 'aprem' ? 'l’après-midi' : 'le soir')}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final k in const ['matin', 'aprem', 'soir'])
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    width: 38,
                    height: maxM == 0 ? 2 : 2 + 52 * byMoment[k]! / maxM,
                    decoration: BoxDecoration(color: low.withValues(alpha: k == hard ? 1 : .55), borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
                  ),
                  const SizedBox(height: 4),
                  Text(momentLabel[k]!, style: TextStyle(fontSize: 12, fontWeight: k == hard ? FontWeight.w800 : FontWeight.w500, color: k == hard ? cs.onSurface : text3)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Text('temps passé en Flemme, par moment de la journée', style: TextStyle(fontSize: 12, color: text3)),
      ]));
    }
    if (windows.total > 0) {
      out.add(fact('${windows.won}/${windows.total}', low, 'En Flemme, tu démarres quand même',
          'fenêtres de flemme où tu as fait quelque chose · ${(windows.won * 100 / windows.total).round()} %'));
    }
    if (rebound.total > 0) {
      out.add(fact('${rebound.up}/${rebound.total}', modeChipColor(DayMode.high, dark: dark), 'Après une guérilla, tu remontes',
          'ton corps va mieux à la fin de ${rebound.up} guérilla${rebound.up > 1 ? 's' : ''} sur ${rebound.total}'));
    }
    final known = weekly.whereType<int>().toList();
    if (known.length >= 2) {
      final first = weekly.firstWhere((v) => v != null)!;
      final lastV = weekly.lastWhere((v) => v != null)!;
      final maxW = known.fold<int>(1, (a, b) => a > b ? a : b);
      out.add(card([
        const Text('Ta tendance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < weekly.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (weekly[i] != null) Text('${weekly[i]} %', style: TextStyle(fontSize: 10.5, color: text3)),
                  Container(
                    height: weekly[i] == null ? 2 : 2 + 36 * weekly[i]! / maxW,
                    decoration: BoxDecoration(color: low.withValues(alpha: i == weekly.length - 1 ? 1 : .5), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  ),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 6),
        Text(
          lastV < first - 3
              ? 'Moins de temps en Flemme qu’il y a un mois · part de flemme, semaine par semaine'
              : (lastV > first + 3 ? 'Plus de temps en Flemme qu’il y a un mois · part de flemme, semaine par semaine' : 'Stable depuis un mois · part de flemme, semaine par semaine'),
          style: TextStyle(fontSize: 12.5, color: text2),
        ),
      ]));
    }
    if (out.isEmpty) {
      out.add(_note(cs, 'Dis ton mode quelques jours : ce que ça t’apprend (ton creux, ta façon de repartir) apparaîtra ici.'));
    }
    return out;
  }

  static const _modeShort = {DayMode.low: 'petits démarrages', DayMode.normal: 'le programme', DayMode.high: 'le gros'};

  static const _modePromise = {
    DayMode.low: 'Je te propose des petits démarrages : 10 min, malgré tout · Guérilla',
    DayMode.normal: 'Le programme tel qu’il est, une chose après l’autre',
    DayMode.high: 'Je te pousse vers le gros : Offensive · Deep work 90 min',
  };

  /// « depuis 14:20 » : l'heure du dernier pointage réel du jour vécu.
  String? _sinceLabel(List<MoodMark> marks, DateTime now) {
    final ymd = widget.logic.livedTodayYmd;
    final w = elanWindows(marks, ymd, dayStartMin: widget.logic.dayStartMin).where((w) => w.mark.value >= 1).toList();
    if (w.isEmpty) return null;
    final t = w.last.mark.at;
    return 'depuis ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// « Là, tu es comment ? » (maquette « Ton élan, autrement ») : une grande
  /// carte par mode, avec ce que l'app va proposer.
  Widget _modeCard(ColorScheme cs, bool dark, DayMode m, {required bool selected, String? since, required VoidCallback onTap}) {
    final c = modeChipColor(m, dark: dark);
    return Material(
      color: selected ? c.withValues(alpha: .14) : c.withValues(alpha: .05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? c : c.withValues(alpha: .35), width: selected ? 2 : 1.2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: selected ? c : c.withValues(alpha: .22), shape: BoxShape.circle),
              child: Icon(modeIcon(m), color: selected ? (dark ? Colors.black : Colors.white) : c, size: 20),
            ),
            const SizedBox(height: 6),
            Text(kModeLabels[m]!, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: selected ? c : cs.onSurface)),
            Text(selected ? (since ?? 'maintenant') : _modeShort[m]!,
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? c : cs.onSurface.withValues(alpha: .55))),
          ]),
        ),
      ),
    );
  }


  Color _bandColor(ColorScheme cs, bool dark, int? v) => switch (bandModeOf(v)) {
        BandMode.low => modeChipColor(DayMode.low, dark: dark),
        BandMode.normal => modeChipColor(DayMode.normal, dark: dark),
        BandMode.high => modeChipColor(DayMode.high, dark: dark),
        BandMode.recharge => kRechargeBand,
        null => cs.onSurface.withValues(alpha: .07),
      };

  /// La semaine en bandes : une phrase, une bande par jour (6 h → nuit),
  /// « ⚡ n » = fenêtres de flemme où tu as quand même fait quelque chose ;
  /// tap = le jour en détail. Puis la répartition du temps dit.
  List<Widget> _weekBands(ColorScheme cs, bool dark, List<MoodMark> marks, List<ElanDay> week, DateTime now) {
    final logic = widget.logic;
    final rows = [for (final d in week) (d.ymd, elanCellsOfDay(marks, d.ymd, now, logic.dayStartMin))];
    final wins = week.fold<int>(0, (s, d) => s + lowWinsOf(d));
    final share = modeShareOf(rows.map((r) => r.$2));
    final text3 = cs.onSurface.withValues(alpha: .55);
    const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    Widget band(List<int?> cells, {double h = 22, bool today = false}) => Container(
          height: h,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: today ? Border.all(color: cs.onSurface.withValues(alpha: .8), width: 1.5) : null),
          clipBehavior: Clip.antiAlias,
          // stretch : sans hauteur imposée, une case colorée vide fait 0 px de haut.
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final v in cells) Expanded(child: ColoredBox(color: _bandColor(cs, dark, v))),
          ]),
        );
    return [
      Text(weekBandSentence(rows, wins), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.3)),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.only(left: 40, right: 40),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final t in elanHourTicks(logic.dayStartMin)) Text(t, style: TextStyle(fontSize: 10, color: text3)),
        ]),
      ),
      const SizedBox(height: 4),
      for (var i = 0; i < week.length; i++)
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showElanDaySheet(context, logic, marks: marks, day: week[i], badges: widget.badges),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 36,
                child: Text(days[DateTime.parse(week[i].ymd).weekday - 1],
                    style: TextStyle(fontSize: 12.5, fontWeight: i == week.length - 1 ? FontWeight.w800 : FontWeight.w600, color: i == week.length - 1 ? cs.onSurface : text3)),
              ),
              Expanded(child: band(rows[i].$2, today: i == week.length - 1)),
              SizedBox(
                width: 40,
                child: Text(lowWinsOf(week[i]) == 0 ? '' : '⚡ ${lowWinsOf(week[i])}',
                    textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: modeChipColor(DayMode.low, dark: dark))),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 4, children: [
        for (final m in BandMode.values) _swatch(cs, _bandColor(cs, dark, switch (m) { BandMode.low => 1, BandMode.normal => 3, BandMode.high => 5, BandMode.recharge => kRechargeValue }), kBandModeLabels[m]!),
        _swatch(cs, _bandColor(cs, dark, null), 'pas dit'),
        Text('⚡ démarré malgré la flemme', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: modeChipColor(DayMode.low, dark: dark))),
      ]),
      if (share.said > 0) ...[
        const SizedBox(height: 14),
        Text('TON TEMPS DIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: text3)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            height: 12,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final m in const [BandMode.normal, BandMode.low, BandMode.high])
                if (share.pct(m) > 0) Expanded(flex: share.pct(m), child: ColoredBox(color: _bandColor(cs, dark, switch (m) { BandMode.low => 1, BandMode.high => 5, _ => 3 }))),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final m in const [BandMode.normal, BandMode.low, BandMode.high])
            Text('${kBandModeLabels[m]} ${share.pct(m)} %', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .7))),
        ]),
      ],
      const SizedBox(height: 4),
      Text('Touche un jour pour le voir en détail.', style: TextStyle(fontSize: 11.5, color: text3)),
    ];
  }


  Widget _swatch(ColorScheme cs, Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .7))),
      ]);

  /// VICTOIRES SUR LA FLEMME · n (retour user 2026-10-30 : « Flemme | 8 victoires », mais lesquelles ?) :
  /// une ligne par victoire du jour, heure · quoi · comment. Rien sans victoire.
  List<Widget> _winsSection(ColorScheme cs) {
    final wins = widget.badges?.todayFacts().flemmeWins ?? const [];
    if (wins.isEmpty) return const [];
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final sorted = [...wins]..sort((a, b) => a.at.compareTo(b.at));
    final text3 = cs.onSurface.withValues(alpha: .55);
    final accent = modeChipColor(DayMode.low, dark: cs.brightness == Brightness.dark);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Row(children: [
          Expanded(
            child: Text('VICTOIRES SUR LA FLEMME · ${wins.length}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: text3)),
          ),
        ]),
      ),
      for (final w in sorted)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.what, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(w.how, style: TextStyle(fontSize: 12, color: text3)),
              ]),
            ),
            Text(hm(w.at), style: TextStyle(fontSize: 12.5, color: text3, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
    ];
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


  Widget _note(ColorScheme cs, String t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: TextStyle(fontSize: 12.5, height: 1.4, color: cs.onSurface.withValues(alpha: .8))),
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
  /// Moyenne glissante sur 7 jours, une valeur par jour (`rollingElanMeans`) :
  /// tracée en courbe à la place du trait plat de la semaine.
  final List<double?>? rolling;
  const ElanWeekGraph({super.key, required this.days, required this.mean, this.rolling});

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
              if (rolling == null || rolling!.length != days.length) ...[
                Positioned(top: yOf(mean), left: 0, right: 0, child: Container(height: 2, color: kElanAccent.withValues(alpha: .7))),
                Positioned(top: yOf(mean) - 14, right: 2, child: Text(fmtElan(mean), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: kElanAccent))),
              ] else ...[
                Positioned.fill(
                  child: CustomPaint(painter: _RollingPainter([for (final v in rolling!) v == null ? null : yOf(v)], colW, kElanAccent)),
                ),
                if (rolling!.last != null)
                  Positioned(top: yOf(rolling!.last!) - 15, right: 2, child: Text(fmtElan(rolling!.last!), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: kElanAccent))),
              ],
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

/// Courbe de la moyenne glissante : un point par jour (centre de colonne),
/// reliés ; un jour sans valeur coupe la courbe.
class _RollingPainter extends CustomPainter {
  final List<double?> ys;
  final double colW;
  final Color color;
  _RollingPainter(this.ys, this.colW, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: .8)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = color;
    Path? path;
    for (var i = 0; i < ys.length; i++) {
      final y = ys[i];
      if (y == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      final x = i * colW + colW / 2;
      if (path == null) {
        path = Path()..moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.6, dot);
    }
    if (path != null) canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_RollingPainter old) => old.ys.toString() != ys.toString() || old.colW != colW;
}

/// Les 30 derniers jours en cases (10 par ligne), colorées par l'élan moyen du
/// jour ; aujourd'hui encadré, jours sans pointage en pointillé. Tap = le jour.
class ElanMonthGrid extends StatelessWidget {
  final ElanMonth month;
  final void Function(ElanDay day)? onDay;
  const ElanMonthGrid({super.key, required this.month, this.onDay});

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
              triggerMode: onDay == null ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
              child: GestureDetector(
                onTap: onDay == null ? null : () => onDay!(days[i]),
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

/// Couleur de la recharge dans les bandes (plus claire que `kRechargeColor`
/// pour se lire sur le fond sombre).
const kRechargeBand = Color(0xFF3B5585);

/// Un jour en détail (maquette « Ton élan, autrement ») : sa bande, trois
/// chiffres, le fil des pointages (heure · mode · durée), et pour aujourd'hui
/// les victoires sur la flemme.
Future<void> showElanDaySheet(BuildContext context, AppLogic logic, {required List<MoodMark> marks, required ElanDay day, BadgeCenter? badges}) {
  return showFiche<void>(context, builder: (ctx, scroll) {
    final cs = Theme.of(ctx).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final now = DateTime.now();
    final cells = elanCellsOfDay(marks, day.ymd, now, logic.dayStartMin);
    final windows = elanWindows(marks, day.ymd, dayStartMin: logic.dayStartMin);
    final isToday = day.ymd == logic.livedTodayYmd;
    final wins = isToday ? (badges?.todayFacts().flemmeWins ?? const []) : const [];
    final share = modeShareOf([cells]);
    final text3 = cs.onSurface.withValues(alpha: .55);
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    String dur(int min) => min >= 60 ? '${min ~/ 60} h${min % 60 == 0 ? '' : (min % 60).toString().padLeft(2, '0')}' : '$min min';
    Color colorOf(int? v) => switch (bandModeOf(v)) {
          BandMode.low => modeChipColor(DayMode.low, dark: dark),
          BandMode.normal => modeChipColor(DayMode.normal, dark: dark),
          BandMode.high => modeChipColor(DayMode.high, dark: dark),
          BandMode.recharge => kRechargeBand,
          null => cs.onSurface.withValues(alpha: .07),
        };
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    const wd = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    final date = DateTime.parse(day.ymd);
    final events = <(DateTime, Widget)>[];
    for (final w in windows) {
      final v = w.mark.value;
      final end = w.end.isAfter(now) ? now : w.end;
      final min = end.difference(w.mark.at).inMinutes;
      final mode = bandModeOf(v);
      if (mode == null) continue;
      events.add((
        w.mark.at,
        _eventRow(cs, hm(w.mark.at), colorOf(v), kBandModeLabels[mode]!,
            [if (min > 0) dur(min), if (w.low && day.marks.any((m) => m.value <= 2 && m.value >= 1 && m.won)) 'tu as quand même fait quelque chose'].join(' · '))
      ));
    }
    for (final w in wins) {
      events.add((w.at, _eventRow(cs, hm(w.at), null, w.what, w.how)));
    }
    events.sort((a, b) => a.$1.compareTo(b.$1));
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      Text('${wd[date.weekday - 1]} ${date.day} ${months[date.month - 1]}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(share.dominant == null ? 'rien de dit ce jour-là' : 'surtout ${kBandModeLabels[share.dominant]}', style: TextStyle(fontSize: 13, color: text3)),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(height: 32, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final v in cells) Expanded(child: ColoredBox(color: colorOf(v)))])),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final t in elanHourTicks(logic.dayStartMin)) Text(t, style: TextStyle(fontSize: 10, color: text3)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        for (final (big, label, c) in [
          ('⚡ ${isToday ? wins.length : lowWinsOf(day)}', isToday ? 'victoires sur la flemme' : 'flemmes gagnées', modeChipColor(DayMode.low, dark: dark)),
          ('${share.pct(BandMode.normal)} %', 'en Normal', modeChipColor(DayMode.normal, dark: dark)),
          ('${share.pct(BandMode.high)} %', 'en forme', modeChipColor(DayMode.high, dark: dark)),
        ]) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text(big, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c)),
                Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: text3)),
              ]),
            ),
          ),
          if (label != 'en forme') const SizedBox(width: 6),
        ],
      ]),
      const SizedBox(height: 16),
      Text('LE FIL DE LA JOURNÉE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: text3)),
      const SizedBox(height: 8),
      if (events.isEmpty) Text('Aucun pointage ce jour-là.', style: TextStyle(fontSize: 13, color: text3, fontStyle: FontStyle.italic)),
      for (final e in events) e.$2,
    ]);
  });
}

Widget _eventRow(ColorScheme cs, String time, Color? dot, String title, String detail) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 46, child: Text(time, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .55), fontFeatures: const [FontFeature.tabularFigures()]))),
        SizedBox(
          width: 22,
          child: dot == null
              ? const Text('⚡', style: TextStyle(fontSize: 13, color: Color(0xFFF2A93B)))
              : Padding(padding: const EdgeInsets.only(top: 3), child: Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle))),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            if (detail.isNotEmpty) Text(detail, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
          ]),
        ),
      ]),
    );
