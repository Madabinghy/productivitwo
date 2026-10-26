import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;
import 'package:productivitwo_v1/widgets/badge_painter.dart';

/// Badges sur le web (2026-10) : module « BADGES » de la colonne de droite
/// d'Aujourd'hui (compteur hors séries, séries en cours, bande de six badges,
/// « Voir le deck ») et le deck complet en dialog. Le deck se calcule ici
/// depuis les flux du web (hits, sessions, pointages, sessions d'Enchaîner) et
/// les programmes des 400 derniers jours, relus toutes les cinq minutes.
class WebBadgesCard extends StatefulWidget {
  final FirestoreSync sync;
  final List<Activity> activities;
  final List<Project> projects;
  final List<StrategicObjective> objectives;
  final List<HabitHit> hits;
  final List<Session> sessions;
  final List<MoodMark> moodMarks;
  final List<ChainRun> chainRuns;
  final int dayStartMin;
  final bool folded;
  final VoidCallback onToggleFold;
  const WebBadgesCard({
    super.key,
    required this.sync,
    required this.activities,
    required this.projects,
    required this.objectives,
    required this.hits,
    required this.sessions,
    required this.moodMarks,
    required this.chainRuns,
    required this.dayStartMin,
    required this.folded,
    required this.onToggleFold,
  });

  @override
  State<WebBadgesCard> createState() => _WebBadgesCardState();
}

class _WebBadgesCardState extends State<WebBadgesCard> {
  List<DailySchedule> _schedules = const [];
  DateTime? _fetchedAt;
  BadgeDeck? _deck;
  String _deckKey = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final now = DateTime.now();
    if (_fetchedAt != null && now.difference(_fetchedAt!) < const Duration(minutes: 5)) return;
    _fetchedAt = now;
    try {
      final s = await widget.sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 400))), ymdOf(now));
      if (!mounted) return;
      setState(() {
        _schedules = s;
        _deckKey = '';
      });
    } catch (_) {}
  }

  BadgeDeck _deckOf() {
    final key = '${widget.hits.length}|${widget.sessions.length}|${widget.moodMarks.length}|${widget.chainRuns.length}|${widget.projects.length}|${widget.objectives.length}|${_schedules.length}|${ymdOf(DateTime.now())}';
    if (_deck != null && key == _deckKey) return _deck!;
    _deckKey = key;
    return _deck = computeBadges(
      activities: widget.activities,
      habitHits: widget.hits,
      schedules: _schedules,
      projects: widget.projects,
      objectives: widget.objectives,
      sessions: widget.sessions,
      moodMarks: widget.moodMarks,
      chainRuns: widget.chainRuns,
      now: DateTime.now(),
      dayStartMin: widget.dayStartMin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = _deckOf();
    final all = deck.badges;
    final acquired = all.where((b) => b.acquired).toList()..sort((a, b) => (b.obtained ?? DateTime(2000)).compareTo(a.obtained ?? DateTime(2000)));
    final locked = all.where((b) => !b.acquired && b.showGauge && b.def.measured).toList();
    final strip = [...acquired, ...locked].take(6).toList();
    return Container(
      padding: widget.folded ? const EdgeInsets.fromLTRB(20, 14, 20, 14) : const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onToggleFold,
          child: Row(children: [
            const Icon(Icons.military_tech_outlined, size: 15, color: kBadgeBrass),
            const SizedBox(width: 6),
            const Text('BADGES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
            const SizedBox(width: 8),
            Text('${deck.acquired} / ${deck.total}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kBadgeBrass)),
            if (deck.seriesRunning > 0) ...[
              const SizedBox(width: 8),
              Expanded(child: Text('· ${deck.seriesRunning} série${deck.seriesRunning > 1 ? 's' : ''} en cours', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kBText3))),
            ] else
              const Spacer(),
            Icon(widget.folded ? Icons.expand_more : Icons.expand_less, size: 18, color: kBText4),
          ]),
        ),
        if (!widget.folded) ...[
          const SizedBox(height: 12),
          Row(children: [
            for (final b in strip)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Tooltip(
                  message: b.def.name,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => showBadgeSheet(context, b),
                    child: Opacity(opacity: b.acquired ? 1 : .55, child: BadgeView(state: b, size: 40)),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: kBPrimary, padding: EdgeInsets.zero),
              onPressed: () => showWebBadgeDeck(context, deck),
              icon: const Icon(Icons.grid_view_rounded, size: 16),
              label: const Text('Voir le deck', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Le deck complet en dialog (familles, badges à 72 px, fiche au clic).
Future<void> showWebBadgeDeck(BuildContext context, BadgeDeck deck) {
  final last = deck.lastObtained;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: kBBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 640,
        height: 720,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(children: [
              const Text('Badges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kBText)),
              const SizedBox(width: 12),
              Text.rich(TextSpan(children: [
                TextSpan(text: '${deck.acquired}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBadgeBrass)),
                TextSpan(text: ' sur ${deck.total}', style: const TextStyle(fontSize: 14, color: kBText3)),
              ])),
              const Spacer(),
              if (last != null)
                Row(children: [
                  BadgeView(state: last, size: 32),
                  const SizedBox(width: 8),
                  Text('Dernier obtenu · ${last.def.name}', style: const TextStyle(fontSize: 12.5, color: kBText2)),
                  const SizedBox(width: 12),
                ]),
              IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close, color: kBText3)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                for (final f in BadgeFamily.values)
                  if (deck.ofFamily(f).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Row(children: [
                        Text(badgeFamilyLabel(f).toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: kBText3)),
                        const Spacer(),
                        Text(
                          f == BadgeFamily.routines
                              ? '${deck.seriesRunning} en cours'
                              : '${deck.ofFamily(f).fold(0, (s, b) => s + b.paliersDone)} / ${deck.ofFamily(f).fold(0, (s, b) => s + b.paliersTotal)}',
                          style: const TextStyle(fontSize: 12, color: kBText4),
                        ),
                      ]),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 14,
                      children: [
                        for (final b in deck.ofFamily(f))
                          SizedBox(
                            width: 104,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => showBadgeSheet(ctx, b),
                              child: Column(children: [
                                Opacity(opacity: b.acquired ? 1 : .55, child: BadgeView(state: b, size: 72)),
                                const SizedBox(height: 4),
                                Text(b.def.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, height: 1.25, fontWeight: b.acquired ? FontWeight.w600 : FontWeight.w400, color: b.acquired ? kBText : kBText3)),
                                Text(_sub(b), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: kBText3)),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ],
              ],
            ),
          ),
        ]),
      ),
    ),
  );
}

String _sub(BadgeState b) {
  if (!b.def.measured) return 'bientôt';
  if (b.complete) return '${fmtInt(b.def.tiers.last)} ${b.def.unit} · complet';
  if (b.showGauge) return '${b.value == b.value.roundToDouble() ? fmtInt(b.value) : b.value.toStringAsFixed(1).replaceAll('.', ',')} / ${fmtInt(b.nextTarget!)} ${b.def.unit}';
  if (b.acquired && b.obtained != null) return 'le ${b.obtained!.day} ${const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'][b.obtained!.month - 1]}';
  return 'pas encore';
}
