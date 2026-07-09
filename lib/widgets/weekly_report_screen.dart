import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/evening_verdict.dart';
import 'package:productivitwo_v1/widgets/plan_day_screen.dart';

/// Rapport hebdo (maquettes 16b « rapport » + 16c « ce qui change ») : la
/// semaine jugée sur les FAITS — vital par domaine, motif chiffré avec ses
/// heures, LA question de fond (une seule). « Oui — on réorganise » applique
/// la décision aux modalités du domaine (trace history + renegotiatedAt),
/// lue par la proposition dès lundi. Jamais de culpabilité rétroactive.
class WeeklyReportScreen extends StatefulWidget {
  final AppLogic logic;
  final WeeklyReport report;

  const WeeklyReportScreen(
      {super.key, required this.logic, required this.report});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  final _sync = FirestoreSync();
  late String _decisionStatus;

  WeeklyReport get r => widget.report;

  @override
  void initState() {
    super.initState();
    _decisionStatus = r.decisionStatus;
  }

  /// « Oui — on réorganise » : la décision devient un fait — la modalité du
  /// domaine change (from → to), la trace est écrite (history +
  /// renegotiatedAt). L'intention, elle, ne bouge jamais ici.
  Future<void> _applyDecision() async {
    final d = r.proposedDecision;
    if (d?.domainId == null) return;
    final domain = widget.logic.state.domains
        .where((x) => x.id == d!.domainId)
        .firstOrNull;
    if (domain == null) return;
    final idx = domain.modalities.indexWhere((m) =>
        m.trim().toLowerCase() == d!.from.trim().toLowerCase());
    if (idx >= 0) {
      domain.modalities[idx] = d!.to;
    } else {
      domain.modalities.add(d!.to);
    }
    domain.history.add({
      'date': DateTime.now().toIso8601String(),
      'field': 'modalities',
      'from': d.from,
      'to': d.to,
      'reason': d.reason,
    });
    domain.renegotiatedAt = DateTime.now();
    await _sync.saveDomain(domain);
    await _sync.setWeeklyReportDecision(r.weekStart, 'applied');
    if (mounted) {
      setState(() => _decisionStatus = 'applied');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Décidé — « ${d.to} » dès lundi.'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _declineDecision() async {
    await _sync.setWeeklyReportDecision(r.weekStart, 'declined');
    if (mounted) setState(() => _decisionStatus = 'declined');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Semaine ${r.isoWeek}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text('RAPPORT · ${_rangeLabel()}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.primary)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // ── Narratif (rédigé depuis les faits, jamais inventé) ──────────────
          if (r.narrative.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(r.narrative,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: cs.onSurface.withOpacity(.85))),
            ),
          // ── Engagements ─────────────────────────────────────────────────────
          Row(
            children: [
              Text('${r.held}/${r.total}',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: cs.primary)),
              const SizedBox(width: 8),
              Text('ENGAGEMENTS TENUS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: cs.onSurface.withOpacity(.5))),
            ],
          ),
          const SizedBox(height: 14),
          // ── Domaines : le vital, en faits ────────────────────────────────────
          for (final d in r.domains) _domainCard(cs, d),
          // ── Motifs : ce n'est plus de la malchance ──────────────────────────
          for (final m in r.motifs) _motifCard(cs, m),
          // ── LA question de fond (une seule) + décision ──────────────────────
          if (r.question?.isNotEmpty == true) _questionCard(cs),
          // ── Ce qui change (16c) ─────────────────────────────────────────────
          if (_decisionStatus == 'applied' && r.proposedDecision != null)
            _changeRow(
                cs,
                Icons.arrow_forward_rounded,
                cs.primary,
                r.proposedDecision!.to,
                'décidé au rapport · ${r.proposedDecision!.reason}'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                'Rien d\'autre ne bouge — une décision par semaine suffit.',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurface.withOpacity(.45)),
              ),
            ),
          ),
          // ── Poser la semaine ────────────────────────────────────────────────
          FilledButton(
            onPressed: () {
              final tomorrow = DateTime.now().add(const Duration(days: 1));
              final ymd =
                  '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlanDayScreen(
                    logic: widget.logic, targetDate: ymd, rattrapage: false),
              ));
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('Poser la semaine — courses & batch d\'abord'),
          ),
        ],
      ),
    );
  }

  Widget _domainCard(ColorScheme cs, ReportDomainFact d) {
    final held = d.vitalHeld;
    final color = held ? cs.primary : cs.tertiary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.35)),
        color: color.withOpacity(.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '${d.name} — ${held ? 'vital tenu' : 'vital sous tension'}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              if (held) Icon(Icons.check_rounded, size: 16, color: cs.primary),
            ],
          ),
          if (d.vitals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              children: [
                for (final v in d.vitals)
                  Text.rich(TextSpan(children: [
                    TextSpan(
                      text: '${v.done}/${v.target} ',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: v.done >= v.target ? cs.primary : cs.tertiary),
                    ),
                    TextSpan(
                      text: v.label,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(.6)),
                    ),
                  ])),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Pas de métrique mesurable cette semaine.',
                  style: TextStyle(
                      fontSize: 11.5, color: cs.onSurface.withOpacity(.45))),
            ),
        ],
      ),
    );
  }

  Widget _motifCard(ColorScheme cs, ReportMotif m) {
    final amber = cs.tertiary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withOpacity(.5)),
        color: amber.withOpacity(.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UN MOTIF — PLUS UNE EXCEPTION',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: amber)),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '« ${skipReasonLabel(m.cause)} » a mangé ',
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: cs.onSurface.withOpacity(.9))),
            TextSpan(
                text: '${m.count} blocs sur ${m.brokenTotal}',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: amber)),
            TextSpan(
                text:
                    ' cette semaine — ${m.hoursLabel}. Ce n\'est plus de la malchance, c\'est un créneau exposé.',
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: cs.onSurface.withOpacity(.9))),
          ])),
          if (m.samples.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in m.samples)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: cs.onSurface.withOpacity(.15)),
                    ),
                    child: Text(
                      '${s['weekday']} ${(s['time'] ?? '').toString().split(':').first} h  ✗',
                      style: TextStyle(
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: cs.onSurface.withOpacity(.6)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _questionCard(ColorScheme cs) {
    final pending = _decisionStatus == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(.35)),
        color: cs.primary.withOpacity(.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LA QUESTION DE FOND — UNE SEULE',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.primary)),
          const SizedBox(height: 8),
          Text(r.question!,
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          if (r.proposedDecision != null) ...[
            const SizedBox(height: 12),
            if (pending)
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _applyDecision,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('Oui — on réorganise'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _declineDecision,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('Pas cette semaine'),
                    ),
                  ),
                ],
              )
            else
              Text(
                _decisionStatus == 'applied'
                    ? '✓ Décidé — appliqué aux modalités du domaine, la proposition le lit dès lundi.'
                    : 'Noté — on n\'y touche pas cette semaine.',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.6)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _changeRow(
      ColorScheme cs, IconData icon, Color color, String title, String sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: cs.onSurface.withOpacity(.55))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _rangeLabel() {
    String dayMonth(String ymd) {
      final d = DateTime.tryParse(ymd);
      if (d == null) return ymd;
      const months = [
        '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
        'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
      ];
      return '${d.day} ${months[d.month]}';
    }

    return '${dayMonth(r.weekStart)} – ${dayMonth(r.weekEnd)}'.toUpperCase();
  }
}
