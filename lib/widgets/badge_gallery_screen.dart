import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart';

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
        now: now,
        dayStartMin: widget.logic.dayStartMin,
      );
      if (mounted) setState(() => _deck = deck);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final deck = _deck;
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
                    child: Text('${last.def.name} · ${_shortDate(last.obtained!)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kBText2)),
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
          Opacity(opacity: b.acquired ? 1 : .55, child: BadgeView(state: b, size: 72)),
          const SizedBox(height: 4),
          Text(b.def.name,
              maxLines: 2,
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

  String _num(num v) => v is int || v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1).replaceAll('.', ',');

  String _shortDate(DateTime d) {
    const m = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${d.day == 1 ? '1er' : d.day} ${m[d.month - 1]}';
  }

  void _showFacts(BadgeState b) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kBSurface,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          BadgeView(state: b, size: 150),
          const SizedBox(height: 12),
          Text(badgeFamilyLabel(b.def.family).toUpperCase(),
              style: const TextStyle(fontSize: 12, letterSpacing: 1, color: kBText3)),
          Text(b.def.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kBText)),
          const SizedBox(height: 6),
          Text(
            b.showGauge
                ? '${_num(b.value)} / ${fmtInt(b.nextTarget!)} ${b.def.unitLong}'
                : (b.acquired && b.obtained != null ? 'Obtenu le ${_shortDate(b.obtained!)} ${b.obtained!.year}' : 'Pas encore obtenu'),
            style: const TextStyle(fontSize: 15, color: kBText),
          ),
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
          const Text('Visible par ton coach · lecture seule', style: TextStyle(fontSize: 12, color: kBText4)),
        ]),
      ),
    );
  }
}
