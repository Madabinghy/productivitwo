import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart';
import 'package:productivitwo_v1/widgets/badge_track_view.dart';
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show showModeSheet;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus;
import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';

/// Aperçu des badges (lot 1) : le gabarit aux trois tailles, puis le deck
/// calculé sur les VRAIES données de la personne (routines, programmes des
/// 400 derniers jours, projets, objectifs, sessions). Ouvert depuis
/// Paramètres ; pas d'onglet, pas de signal : le deck de l'onglet Objectifs
/// viendra au lot 3.
class BadgeGalleryScreen extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  /// Deck partagé (lot 3) : évite de relire 400 programmes à chaque ouverture.
  final BadgeCenter? center;
  /// Aperçu du gabarit et des niveaux en tête (Paramètres) ; faux = le deck seul.
  final bool showSamples;
  const BadgeGalleryScreen({super.key, required this.logic, required this.sync, this.center, this.showSamples = true});

  @override
  State<BadgeGalleryScreen> createState() => _BadgeGalleryScreenState();
}

class _BadgeGalleryScreenState extends State<BadgeGalleryScreen> {
  BadgeDeck? _deck;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.center;
    if (c != null) {
      try {
        final d = await c.load();
        if (mounted) setState(() => _deck = d);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
      return;
    }
    try {
      final now = DateTime.now();
      final from = ymdOf(now.subtract(const Duration(days: 400)));
      final results = await Future.wait([
        widget.sync.fetchDailySchedulesRange(from, ymdOf(now)),
        widget.sync.fetchProjects(),
        widget.sync.fetchStrategicObjectives(),
      ]);
      final st = widget.logic.state;
      final deck = computeBadges(
        activities: st.activities,
        habitHits: st.habitHits,
        schedules: results[0] as List<DailySchedule>,
        projects: results[1] as List<Project>,
        objectives: results[2] as List<StrategicObjective>,
        sessions: st.sessions,
        moodMarks: st.moodMarks,
        chainRuns: st.chainRuns,
        now: now,
        dayStartMin: widget.logic.dayStartMin,
      );
      if (mounted) setState(() => _deck = deck);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  TodayFacts? _facts;

  @override
  Widget build(BuildContext context) {
    final deck = _deck;
    _facts = widget.center?.todayFacts();
    return Scaffold(
      backgroundColor: kBBg,
      appBar: AppBar(
        backgroundColor: kBBar,
        foregroundColor: kBText,
        title: Text(widget.showSamples ? 'Badges · aperçu' : 'Badges'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          if (widget.showSamples) ...[
            _kicker('LE GABARIT · 150 / 72 / 40 PX'),
            _sampleRow(),
            const SizedBox(height: 20),
            _kicker('LES NIVEAUX'),
            _levelsRow(),
            const SizedBox(height: 28),
          ],
          if (_error != null)
            Text('Impossible de lire les données : $_error', style: const TextStyle(color: kBAlert))
          else if (deck == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: kBPrimary)),
            )
          else ...[
            _deckHeader(deck),
            if (_facts case final f?) _todaySection(deck, f),
            _huntsSection(deck),
            for (final f in BadgeFamily.values) _family(deck, f),
            const SizedBox(height: 16),
            const Text('Un badge est un fait : il reste acquis. Ton coach les voit en lecture seule.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kBText4)),
          ],
        ],
      ),
    );
  }

  Widget _kicker(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: kBText3)),
      );

  BadgeState _sample(String id, String name, String symbol, List<int> tiers, int level, num value, {String? label}) =>
      BadgeState(def: BadgeDef(id: id, family: BadgeFamily.routines, name: name, symbol: symbol, tiers: tiers, label: label), level: level, value: value);

  Widget _sampleRow() {
    final samples = [
      _sample('a', 'Méditation', 'flame', kRoutineTiers, 3, 34),
      _sample('b', 'Première cible', 'target', const [1], 1, 1, label: '1re'),
      _sample('c', 'Journée parfaite', 'sun', const [1], 1, 1, label: 'Parfaite'),
      _sample('d', 'Enchaîneur', 'chain', const [10], 0, 7, label: '×10'),
      _sample('e', 'Actions', 'check', kActionTiers, 3, 142),
      _sample('f', 'Temps investi', 'hourglass', kTimeTiersHours, 0, 62),
    ];
    return Column(
      children: [
        for (final size in const [150.0, 72.0, 40.0])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [for (final s in samples) Padding(padding: const EdgeInsets.only(right: 12), child: BadgeView(state: s, size: size))],
              ),
            ),
          ),
      ],
    );
  }

  Widget _levelsRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var lv = 0; lv <= 5; lv++)
            BadgeView(
                state: BadgeState(
                    def: const BadgeDef(id: 'lv', family: BadgeFamily.routines, name: 'Série', symbol: 'flame', tiers: kRoutineTiers),
                    level: lv,
                    value: lv == 0 ? 0 : kRoutineTiers[lv - 1]),
                size: 52),
        ],
      );

  Widget _deckHeader(BadgeDeck deck) {
    final last = deck.lastObtained;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${deck.acquired}', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: kBadgeBrass, height: 1)),
                TextSpan(text: ' sur ${deck.total}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBText3)),
              ])),
              if (deck.series.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_seriesLine(deck), maxLines: 2, style: const TextStyle(fontSize: 12, height: 1.3, color: kBText3)),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          if (last != null)
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBadgeBrassDark.withValues(alpha: .6))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                BadgeView(state: last, size: 40),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('DERNIER OBTENU', style: TextStyle(fontSize: 10, letterSpacing: .6, color: kBText3)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text('${last.def.name} · ${_shortDate(last.obtained!)}', maxLines: 2, style: const TextStyle(fontSize: 13, color: kBText2)),
                  ),
                ]),
              ]),
            ),
        ],
      ),
    );
  }

  String _seriesLine(BadgeDeck deck) {
    final n = deck.series.length;
    return '$n série${n > 1 ? 's' : ''} de routine, ${deck.seriesRunning} en cours\nhors compteur';
  }

  /// « EN JEU AUJOURD'HUI » (2026-10) : les suites en cours qui se perdent si
  /// la journée n'est pas tenue, puis « À PORTÉE » : ce qui peut tomber
  /// aujourd'hui. Pastille = ce qu'il manque ; tap = la fiche et ses gestes.
  Widget _todaySection(BadgeDeck deck, TodayFacts facts) {
    final inPlay = badgesInPlay(deck, facts);
    final reachable = <(BadgeState, BadgeToday)>[];
    for (final b in deck.badges) {
      if (b.def.family == BadgeFamily.routines || b.complete) continue;
      final t = badgeToday(b, facts);
      if (t.stake == TodayStake.reachable && t.items.isNotEmpty) reachable.add((b, t));
    }
    if (inPlay.isEmpty && reachable.isEmpty) return const SizedBox.shrink();
    final missing = inPlay.fold(0, (s, e) => s + e.$2.missing);
    Widget header(String title, String right, Color color, IconData icon) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBLine))),
          child: Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1, color: color)),
            const Spacer(),
            Text(right, style: const TextStyle(fontSize: 12.5, color: kBText4)),
          ]),
        );
    Widget row(BadgeState b, BadgeToday t) {
      final color = todayStakeColor(t.stake);
      return InkWell(
        onTap: () => _showFacts(b),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            BadgeView(state: b, size: 40, todayGain: t.gain, todaySecured: t.gainSecured, todayRatio: t.dayRatio),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.def.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kBText)),
                Text(_todaySub(b, t), style: const TextStyle(fontSize: 12, color: kBText3)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
                    child: Text(_pill(t), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                  ),
                ),
                if (t.dayRatio case final r?) ...[
                  const SizedBox(height: 5),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(value: r, minHeight: 4, backgroundColor: kBadgeGaugeTrack, valueColor: AlwaysStoppedAnimation<Color>(r >= 1 ? kBPrimary : kBadgeGaugeToday)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_dayLabel(t), style: const TextStyle(fontSize: 10.5, color: kBText4, fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, color: kBText4),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (inPlay.isNotEmpty) ...[
          header('EN JEU AUJOURD\u2019HUI · ${inPlay.length}', missing > 0 ? 'il manque ${missing == 1 ? '1 chose' : '$missing choses'}' : '', kBAttention, Icons.local_fire_department_rounded),
          for (final (b, t) in inPlay) row(b, t),
        ],
        if (reachable.isNotEmpty) ...[
          if (inPlay.isNotEmpty) const SizedBox(height: 8),
          header('À PORTÉE · ${reachable.length}', '', kBPrimary, Icons.flag_outlined),
          for (final (b, t) in reachable.take(5)) row(b, t),
        ],
      ]),
    );
  }

  /// Sous-titre d'une ligne du jour : la mesure en cours, sans répéter le nom,
  /// et ce que la journée ajoutera (« +1 ce soir ») quand le compteur ne voit
  /// que les jours clos.
  String _todaySub(BadgeState b, BadgeToday t) {
    if (b.def.family == BadgeFamily.routines) return 'série ${_num(b.value)} j${b.nextTarget == null ? '' : ' · palier ${fmtInt(b.nextTarget!)} j'}';
    if (b.showGauge) return '${_num(b.value)} / ${fmtInt(b.nextTarget!)} ${b.def.unit}${todayGainLabel(t)}';
    return b.acquired ? 'déjà obtenu' : 'jamais obtenu';
  }

  /// « 3 / 5 du faisable » ou « 25 / 60 min ».
  String _dayLabel(BadgeToday t) {
    final unit = t.items.any((i) => i.kind == GapKind.time) || t.gauges.any((g) => g.label == 'Rythme du jour') ? ' min' : '';
    return '${t.dayDone} / ${t.dayTotal}$unit';
  }

  /// Pastille courte : le premier geste quand il y en a un, sinon le chip.
  String _pill(BadgeToday t) {
    if (t.items.isEmpty) return t.chip;
    final kinds = t.items.map((i) => i.kind).toSet();
    final routines = t.items.where((i) => i.kind == GapKind.routine).length;
    final blocks = t.items.where((i) => i.kind == GapKind.block).length;
    if (kinds.length == 1 && t.items.length == 1) {
      final i = t.items.single;
      return switch (i.kind) {
        GapKind.routine => 'coche ${i.title}',
        GapKind.block => 'bloc ${i.block?.startTime ?? ''}'.trim(),
        GapKind.elan => 'pointe ton élan',
        GapKind.time => i.title.toLowerCase(),
        GapKind.chain => 'enchaîner',
        GapKind.reading => 'relevé à noter',
        _ => t.chip,
      };
    }
    final parts = <String>[
      if (routines > 0) '$routines routine${routines > 1 ? 's' : ''}',
      if (blocks > 0) '$blocks bloc${blocks > 1 ? 's' : ''}',
    ];
    return parts.isEmpty ? t.chip : parts.join(', ');
  }

  /// « EN CHASSE · n » : les badges visés, leur palier et le rythme.
  Widget _huntsSection(BadgeDeck deck) {
    final views = huntViews(widget.logic.badgeHunts, deck).where((v) => !v.caught).toList();
    if (views.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBLine))),
          child: Row(children: [
            const Icon(Icons.gps_fixed, size: 14, color: kBadgeBrass),
            const SizedBox(width: 6),
            const Text('EN CHASSE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1, color: kBadgeBrass)),
            const Spacer(),
            Text('${views.length} / $kMaxBadgeHunts', style: const TextStyle(fontSize: 13, color: kBText4)),
          ]),
        ),
        for (final v in views)
          InkWell(
            onTap: () => _showFacts(v.badge),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                BadgeView(state: v.badge, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${v.badge.def.name} · palier ${fmtInt(v.tierValue)}${v.badge.def.unit.isEmpty ? '' : ' ${v.badge.def.unit}'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kBText)),
                    Text(v.paceLabel(now), softWrap: true, style: const TextStyle(fontSize: 12.5, color: kBText3)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: v.progress, minHeight: 6, backgroundColor: kBadgeGaugeTrack, valueColor: const AlwaysStoppedAnimation<Color>(kBadgeGaugeFill)),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: kBText4),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _family(BadgeDeck deck, BadgeFamily f) {
    final badges = deck.ofFamily(f);
    if (badges.isEmpty) return const SizedBox.shrink();
    final got = badges.fold(0, (s, b) => s + b.paliersDone);
    final all = badges.fold(0, (s, b) => s + b.paliersTotal);
    final count = f == BadgeFamily.routines ? '${deck.seriesRunning} en cours' : '$got / $all';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBLine))),
          child: Row(children: [
            Text(badgeFamilyLabel(f).toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1, color: kBText3)),
            const Spacer(),
            Text(count, style: const TextStyle(fontSize: 13, color: kBText4)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [for (final b in badges) _card(b)],
        ),
      ]),
    );
  }

  Widget _card(BadgeState b) {
    final width = (MediaQuery.sizeOf(context).width - 32 - 3 * 8) / 4;
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => _showFacts(b),
        child: Column(children: [
          Opacity(
            opacity: b.acquired ? 1 : .55,
            child: _facts == null
                ? BadgeView(state: b, size: 72)
                : Builder(builder: (_) {
                    final t = badgeToday(b, _facts!);
                    return BadgeView(state: b, size: 72, todayGain: t.gain, todaySecured: t.gainSecured, todayRatio: t.dayRatio);
                  }),
          ),
          const SizedBox(height: 4),
          Text(b.def.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.25, fontWeight: b.acquired ? FontWeight.w600 : FontWeight.w400, color: b.acquired ? kBText : kBText3)),
          Text(_sub(b), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: kBText3)),
        ]),
      ),
    );
  }

  String _sub(BadgeState b) {
    if (!b.def.measured) return 'bientôt';
    if (b.complete) return '${fmtInt(b.def.tiers.last)} ${b.def.unit} · complet';
    if (b.showGauge) return '${_num(b.value)} / ${fmtInt(b.nextTarget!)} ${b.def.unit}';
    if (b.acquired && b.obtained != null) return 'le ${_shortDate(b.obtained!)}';
    return 'pas encore';
  }

  String _num(num v) => _numOf(v);

  String _shortDate(DateTime d) => _shortDateOf(d);

  void _showFacts(BadgeState b) => showBadgeSheet(
        context,
        b,
        logic: widget.logic,
        facts: widget.center?.todayFacts(),
        actions: BadgeTodayActions(
          routinePlus: (id) {
            final a = widget.logic.state.activities.where((x) => x.id == id).firstOrNull;
            if (a != null) routinePlus(widget.logic, a);
          },
          pointElan: () => showModeSheet(context, widget.logic),
        ),
      );
}

String _numOf(num v) => v is int || v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1).replaceAll('.', ',');

String _shortDateOf(DateTime d) {
  const m = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day == 1 ? '1er' : d.day} ${m[d.month - 1]}';
}

/// La fiche d'un badge : badge, mesure, « à quoi ça correspond », paliers,
/// « Où j'en suis », « Comment l'obtenir », faits. Ouverte depuis le deck, la
/// rangée d'Objectifs et les routines d'Aujourd'hui.
/// Gestes de la section AUJOURD'HUI (facultatifs : sans eux, les lignes se lisent).
class BadgeTodayActions {
  final void Function(String activityId)? routinePlus;
  final VoidCallback? pointElan;
  final void Function(ScheduleBlock block)? openBlock;
  final void Function(String activityId, int minutes)? startChrono;
  final VoidCallback? openChain;
  const BadgeTodayActions({this.routinePlus, this.pointElan, this.openBlock, this.startChrono, this.openChain});
}

Future<void> showBadgeSheet(BuildContext context, BadgeState b, {HuntStore? logic, TodayFacts? facts, BadgeTodayActions? actions}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kBSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      maxChildSize: .95,
      builder: (ctx, scroll) => StatefulBuilder(builder: (ctx, setSheet) {
        final today = facts == null ? null : badgeToday(b, facts);
        return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Center(child: BadgeView(state: b, size: 150, todayGain: today?.gain ?? 0, todaySecured: today?.gainSecured ?? false, todayRatio: today?.dayRatio)),
        const SizedBox(height: 12),
        Text(badgeFamilyLabel(b.def.family).toUpperCase(),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, letterSpacing: 1, color: kBText3)),
        Text(b.def.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kBText)),
        const SizedBox(height: 6),
        Text(
          b.showGauge
              ? '${_numOf(b.value)} / ${fmtInt(b.nextTarget!)} ${b.def.unitLong}'
              : (b.acquired && b.obtained != null ? 'Obtenu le ${_shortDateOf(b.obtained!)} ${b.obtained!.year}' : 'Pas encore obtenu'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: kBText),
        ),
        if (today != null && !b.showGauge && !b.complete && today.dayRatio != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              today.dayRatio! >= 1 ? 'Faisable du jour fait · ${today.dayDone} / ${today.dayTotal}' : 'Faisable du jour · ${today.dayDone} / ${today.dayTotal}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: today.dayRatio! >= 1 ? kBPrimary : kBadgeGaugeToday),
            ),
          ),
        if (today != null && today.gain > 0 && b.showGauge)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              today.gainSecured
                  ? '+${_numOf(today.gain)} ce soir · la journée tient pour l\u2019instant'
                  : '+${_numOf(today.gain)} ce soir si la journée tient',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: today.gainSecured ? kBadgeGaugeToday : kBText3),
            ),
          ),
        if (b.def.what.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(b.def.what, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, height: 1.35, color: kBText2)),
        ],
        if (today != null) _todayBlock(ctx, b, today, actions, () => setSheet(() {})),
        if (logic != null && !b.complete && b.def.measured) _huntBlock(ctx, logic, b, () => setSheet(() {})),
        if (b.def.tiers.length > 1) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (var i = 0; i < b.def.tiers.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: i < b.level ? kBRaised : null,
                  border: Border.all(color: i < b.level ? kBadgeBrassDark : (i == b.level ? kBPrimary : kBadgeLockedRim)),
                ),
                child: Text('${fmtInt(b.def.tiers[i])}${i < b.level ? ' ✓' : ''}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: i < b.level ? kBadgeBrass : (i == b.level ? kBPrimary : kBText4))),
              ),
          ]),
        ],
        if (b.track case final t?) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: kBBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBLine)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OÙ J\u2019EN SUIS', style: TextStyle(fontSize: 11, letterSpacing: .8, color: kBText4)),
              const SizedBox(height: 8),
              BadgeTrackView(track: t, text3: kBText3),
            ]),
          ),
        ],
        if (b.def.how.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: kBBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBLine)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('COMMENT L\u2019OBTENIR', style: TextStyle(fontSize: 11, letterSpacing: .8, color: kBText4)),
              const SizedBox(height: 6),
              Text(b.def.how, style: const TextStyle(fontSize: 13.5, height: 1.4, color: kBText2)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(color: kBBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBLine)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SUR TES DONNÉES', style: TextStyle(fontSize: 11, letterSpacing: .8, color: kBText4)),
            for (final (k, v) in b.facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: kBText3))),
                  Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kBText)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        const Text('Visible par ton coach · lecture seule', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kBText4)),
      ],
      );
      }),
    ),
  );
}

/// « · +1 ce soir » / « · +1 ce soir ✓ » après la mesure, quand la journée
/// ajoute à un compteur qui ne voit que les jours clos.
String todayGainLabel(BadgeToday t) {
  if (t.gain <= 0) return '';
  final g = t.gain == t.gain.roundToDouble() ? '${t.gain.round()}' : t.gain.toStringAsFixed(1).replaceAll('.', ',');
  return t.gainSecured ? ' · +$g ce soir ✓' : ' · +$g ce soir ?';
}

Color todayStakeColor(TodayStake s) => switch (s) {
      TodayStake.atRisk => kBAttention,
      TodayStake.reachable => kBPrimary,
      TodayStake.saved => kBPrimaryDark,
      TodayStake.lostToday => kBAlert,
      TodayStake.none => kBText4,
    };

IconData _gapIcon(GapKind k) => switch (k) {
      GapKind.routine => Icons.loop_rounded,
      GapKind.block => Icons.play_arrow_rounded,
      GapKind.elan => Icons.bolt_rounded,
      GapKind.time => Icons.timer_outlined,
      GapKind.chain => Icons.link_rounded,
      GapKind.reading => Icons.edit_note_rounded,
      GapKind.deepwork => Icons.center_focus_strong_rounded,
      GapKind.action => Icons.check_rounded,
    };

/// AUJOURD'HUI : l'enjeu du jour (chip), les jauges fait / suffisant, puis
/// chaque chose qui manque avec son geste. Rien n'y juge la journée : elle
/// est comptée demain, une fois close.
Widget _todayBlock(BuildContext ctx, BadgeState b, BadgeToday t, BadgeTodayActions? actions, VoidCallback refresh) {
  if (t.stake == TodayStake.none && t.items.isEmpty && t.notes.isEmpty) return const SizedBox.shrink();
  final color = todayStakeColor(t.stake);
  Widget? gesture(GapItem i) {
    final a = actions;
    if (a == null) return null;
    (String, VoidCallback)? g;
    switch (i.kind) {
      case GapKind.routine:
        if (a.routinePlus != null && i.activityId != null) g = ('+1', () => a.routinePlus!(i.activityId!));
      case GapKind.elan:
        if (a.pointElan != null) g = ('Pointer', a.pointElan!);
      case GapKind.block:
        if (a.openBlock != null && i.block != null) g = ('Ouvrir', () => a.openBlock!(i.block!));
      case GapKind.time:
        if (a.startChrono != null && i.activityId != null) g = ('Chrono', () => a.startChrono!(i.activityId!, i.minutes ?? 25));
      case GapKind.chain:
        if (a.openChain != null) g = ('Enchaîner', a.openChain!);
      default:
        g = null;
    }
    if (g == null) return null;
    final (label, onTap) = g;
    final primary = i.kind == GapKind.routine || i.kind == GapKind.elan;
    return SizedBox(
      height: 30,
      child: FilledButton(
        onPressed: () {
          onTap();
          refresh();
        },
        style: FilledButton.styleFrom(
          backgroundColor: primary ? kBPrimary : kBRaised,
          foregroundColor: primary ? kBBg : kBText,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(color: kBBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: .45))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('AUJOURD\u2019HUI', style: TextStyle(fontSize: 11, letterSpacing: .8, color: kBText4)),
      if (t.chip.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
            child: Text(t.chip, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
        ),
      for (final g in t.gauges) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(g.label, style: const TextStyle(fontSize: 12.5, color: kBText2))),
          Text(
            g.need == g.total ? '${g.done} / ${g.total}' : '${g.done} / ${g.total} · ${g.need} suffisent',
            style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ]),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          final total = g.total <= 0 ? 1 : g.total;
          final ok = g.done >= g.need;
          return SizedBox(
            height: 10,
            child: Stack(children: [
              Container(decoration: BoxDecoration(color: kBadgeGaugeTrack, borderRadius: BorderRadius.circular(5))),
              Container(
                width: w * (g.done / total).clamp(0.0, 1.0),
                decoration: BoxDecoration(color: ok ? kBPrimary : kBAttention, borderRadius: BorderRadius.circular(5)),
              ),
              if (g.need < g.total && g.need > 0)
                Positioned(left: (w * g.need / total).clamp(0.0, w - 2), top: -1, bottom: -1, child: Container(width: 2, color: kBText)),
            ]),
          );
        }),
      ],
      if (t.items.isNotEmpty) const SizedBox(height: 6),
      for (final i in t.items)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: kBRaised, shape: BoxShape.circle),
              child: Icon(_gapIcon(i.kind), size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kBText)),
                if (i.detail.isNotEmpty) Text(i.detail, style: const TextStyle(fontSize: 11.5, color: kBText3)),
              ]),
            ),
            if (gesture(i) case final w?) ...[const SizedBox(width: 8), w],
          ]),
        ),
      for (final n in t.notes)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(n, style: const TextStyle(fontSize: 12.5, height: 1.35, color: kBText2)),
        ),
    ]),
  );
}

/// La chasse : « Viser ce palier » (palier et date facultative), ou l'état de
/// la chasse en cours avec « Ne plus viser ». Trois chasses au plus.
Widget _huntBlock(BuildContext ctx, HuntStore logic, BadgeState b, VoidCallback refresh) {
  final hunt = logic.hunts.where((h) => h.badgeId == b.def.id).firstOrNull;
  final now = DateTime.now();
  if (hunt != null) {
    final v = HuntView(hunt: hunt, badge: b, tierValue: b.def.tiers[(hunt.tier - 1).clamp(0, b.def.tiers.length - 1)]);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBadgeBrassDark.withValues(alpha: .6))),
        child: Row(children: [
          const Icon(Icons.gps_fixed, size: 18, color: kBadgeBrass),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Visé · palier ${fmtInt(v.tierValue)}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBText)),
              Text(v.paceLabel(now), style: const TextStyle(fontSize: 12.5, color: kBText3)),
            ]),
          ),
          TextButton(
            onPressed: () async {
              await logic.stop([b.def.id]);
              refresh();
            },
            child: const Text('Ne plus viser', style: TextStyle(color: kBText3)),
          ),
        ]),
      ),
    );
  }
  final full = logic.hunts.length >= kMaxBadgeHunts;
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(children: [
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: kBadgeBrass, side: const BorderSide(color: kBadgeBrassDark), minimumSize: const Size.fromHeight(44)),
        onPressed: full ? null : () async {
          final picked = await _pickHunt(ctx, b);
          if (picked == null) return;
          await logic.hunt(newHunt(b, picked.tier, now, targetDate: picked.date));
          refresh();
        },
        icon: const Icon(Icons.gps_fixed, size: 18),
        label: Text(b.def.tiers.length > 1 ? 'Viser le palier ${fmtInt(b.nextTarget ?? b.def.tiers.last)}' : 'Viser ce badge'),
      ),
      if (full) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Trois chasses au plus : termine ou retire-en une.', style: TextStyle(fontSize: 12, color: kBText4))),
    ]),
  );
}

Future<({int tier, DateTime? date})?> _pickHunt(BuildContext ctx, BadgeState b) {
  var tier = b.level + 1;
  DateTime? date;
  return showModalBottomSheet<({int tier, DateTime? date})>(
    context: ctx,
    backgroundColor: kBSurface,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      final choices = [for (var i = b.level; i < b.def.tiers.length; i++) i + 1];
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Viser « ${b.def.name} »', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kBText)),
          const SizedBox(height: 4),
          const Text('Une intention, pas une obligation : rien ne se perd si la date passe.', style: TextStyle(fontSize: 12.5, color: kBText3)),
          if (choices.length > 1) ...[
            const SizedBox(height: 14),
            const Text('PALIER', style: TextStyle(fontSize: 11, letterSpacing: .8, color: kBText4)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final t in choices)
                ChoiceChip(
                  label: Text('${fmtInt(b.def.tiers[t - 1])}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}'),
                  selected: tier == t,
                  onSelected: (_) => setS(() => tier = t),
                ),
            ]),
          ],
          const SizedBox(height: 14),
          const Text('D\u2019ICI', style: TextStyle(fontSize: 11, letterSpacing: .8, color: kBText4)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            ChoiceChip(label: const Text('Sans date'), selected: date == null, onSelected: (_) => setS(() => date = null)),
            for (final (l, d) in [('2 semaines', 14), ('1 mois', 30), ('3 mois', 90)])
              ChoiceChip(
                label: Text(l),
                selected: date != null && date!.difference(DateTime.now()).inDays == d - 1 || (date != null && date!.difference(DateTime.now()).inDays == d),
                onSelected: (_) => setS(() => date = DateTime.now().add(Duration(days: d))),
              ),
            ActionChip(
              label: Text(date == null ? 'Choisir…' : ymdOf(date!)),
              onPressed: () async {
                final p = await showDatePicker(context: c, initialDate: date ?? DateTime.now().add(const Duration(days: 14)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (p != null) setS(() => date = p);
              },
            ),
          ]),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBadgeBrass, foregroundColor: kBadgeRibbonInk, minimumSize: const Size.fromHeight(46)),
            onPressed: () => Navigator.of(c).pop((tier: tier, date: date)),
            child: const Text('Viser', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
    }),
  );
}
