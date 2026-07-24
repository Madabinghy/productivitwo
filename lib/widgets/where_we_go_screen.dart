import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';
import 'package:productivitwo_v1/utils/where_we_go.dart';

/// Vue « Où on va » (maquette 24d) — la ligne d'horizon, accessible depuis le
/// header de Maintenant. 3 cartes, 100 % assemblage de faits : le cap
/// (intention n° 1, mots du user, éditable et tracé), la stratégie (décision
/// du rapport + vital compté, réordonnable ⇅ — l'ordre survit au rapport
/// suivant), la tactique (programme du jour + artefacts de J+1). Seul le
/// narratif tactique passe par le modèle (1 appel/jour max, caché serveur) ;
/// en son absence, les lignes déterministes font foi.
class WhereWeGoScreen extends StatefulWidget {
  final AppLogic logic;
  const WhereWeGoScreen({super.key, required this.logic});

  @override
  State<WhereWeGoScreen> createState() => _WhereWeGoScreenState();
}

class _WhereWeGoScreenState extends State<WhereWeGoScreen> {
  final _sync = FirestoreSync();
  static const String _kNarrativeUrl =
      'https://wherewego-dzos75b65q-uc.a.run.app';

  DailySchedule? _today;
  DailySchedule? _tomorrow;
  List<Artifact> _artifacts = const [];
  WeeklyReport? _report;
  List<StrategyItem> _strategy = const [];
  String? _narrToday;
  String? _narrTomorrow;
  bool _loaded = false;

  AppState get st => widget.logic.state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    try {
      final results = await Future.wait([
        _sync.fetchDailySchedule(_ymd(now)),
        _sync.fetchDailySchedule(_ymd(now.add(const Duration(days: 1)))),
        _sync.streamArtifacts().first,
        // Dernier rapport généré : celui de la semaine courante (dès le
        // dimanche soir), sinon celui de la semaine précédente.
        _sync.fetchWeeklyReport(_ymd(monday)),
        _sync.fetchWeeklyReport(
            _ymd(monday.subtract(const Duration(days: 7)))),
      ]);
      if (!mounted) return;
      _today = results[0] as DailySchedule?;
      _tomorrow = results[1] as DailySchedule?;
      _artifacts = results[2] as List<Artifact>? ?? const [];
      final current = results[3] as WeeklyReport?;
      final previous = results[4] as WeeklyReport?;
      // Dernier rapport RÉELLEMENT généré (narratif présent) — un doc partiel
      // (juste strategyOrder) ne masque pas le vrai rapport précédent.
      _report = (current != null && current.narrative.isNotEmpty)
          ? current
          : (previous != null && previous.narrative.isNotEmpty)
              ? previous
              : (current ?? previous);
      _rebuildStrategy(now);
      setState(() => _loaded = true);
      _fetchNarrative(now);
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _rebuildStrategy(DateTime now) {
    final items = buildStrategyItems(
      now: now,
      st: st,
      report: _report,
      gantt: ganttMicroAction(widget.logic.currentProjects,
          blocks: _today?.blocks ?? const []),
    );
    _strategy = applyStrategyOrder(items, _report?.strategyOrder ?? const []);
  }

  /// Narratif tactique : 1 appel/jour max, caché côté serveur (hash de faits).
  /// Échec réseau ou réponse vide → les lignes déterministes restent.
  Future<void> _fetchNarrative(DateTime now) async {
    try {
      final token = await _sync.ensureWidgetToken();
      final raw = token.rawToken;
      final uid = _sync.uid;
      if (raw == null || raw.isEmpty || uid == null) return;
      final cap = capDomain(st);
      final facts = {
        if (cap != null) 'cap': cap.domain.intention,
        'strategy': [for (final s in _strategy) s.title],
        'today': tactiqueTodayLine(now, _today?.blocks ?? const []),
        'tomorrow': tactiqueTomorrowLine(
              now: now,
              tomorrowBlocks: _tomorrow?.blocks ?? const [],
              artifacts: _artifacts,
              todayBlocks: _today?.blocks ?? const [],
            ) ??
            '',
      };
      final resp = await http
          .post(Uri.parse(_kNarrativeUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $raw',
              },
              body: jsonEncode({'uid': uid, 'facts': facts}))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 || !mounted) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final narr = body['narrative'];
      if (narr is Map) {
        setState(() {
          _narrToday = (narr['today'] as String?)?.trim().isEmpty == true
              ? null
              : narr['today'] as String?;
          _narrTomorrow =
              (narr['tomorrow'] as String?)?.trim().isEmpty == true
                  ? null
                  : narr['tomorrow'] as String?;
        });
      }
    } catch (_) {
      // Silencieux : la vue reste 100 % faits.
    }
  }

  // ── Édition du cap : la modification est un fait tracé (history) ───────────

  Future<void> _editCap(Domain d) async {
    final ctrl = TextEditingController(text: d.intention ?? '');
    final cs = Theme.of(context).colorScheme;
    final result = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Changer le cap'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'C\'est ta phrase — je la citerai telle quelle, partout. La modification est tracée sur le domaine.',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withOpacity(.6))),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
              child: const Text('Garder cette formulation')),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == d.intention) return;
    final old = d.intention;
    d.intention = result;
    d.history.add({
      'date': DateTime.now().toIso8601String(),
      'field': 'intention',
      'from': old,
      'to': result,
      'reason': 'édition depuis « Où on va »',
    });
    await _sync.saveDomain(d);
    widget.logic.onChange();
    if (mounted) setState(() {});
  }

  // ── Réordonner (⇅) : l'ordre du user survit au rapport suivant ─────────────

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final items = _strategy.toList();
      final item = items.removeAt(oldIndex);
      items.insert(newIndex, item);
      _strategy = items;
    });
    final report = _report;
    if (report != null) {
      report.strategyOrder = [for (final i in _strategy) i.key];
      _sync.setWeeklyReportStrategyOrder(
          report.weekStart, report.strategyOrder);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final cap = capDomain(st);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Où on va',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('assemblé depuis tes faits',
                  style: TextStyle(
                      fontSize: 11.5, color: cs.onSurface.withOpacity(.45))),
            ),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _capCard(cs, cap),
                  const SizedBox(height: 14),
                  _strategyCard(cs),
                  const SizedBox(height: 14),
                  _tactiqueCard(cs, now),
                  const SizedBox(height: 16),
                  Text(
                      'Rien d\'inventé : intentions, décision du dimanche, artefacts, programme. Le narratif se réécrit 1×/jour max.',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: cs.onSurface.withOpacity(.45))),
                ],
              ),
            ),
    );
  }

  Widget _card(ColorScheme cs, String tag, Widget child,
      {Widget? tagTrailing, Color? accent}) {
    final a = accent ?? cs.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: a.withOpacity(.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: a.withOpacity(.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(tag,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: a)),
            ),
            if (tagTrailing != null) tagTrailing,
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _capCard(ColorScheme cs, ({Domain domain, int rank})? cap) {
    if (cap == null) {
      return _card(
        cs,
        'LE CAP',
        Text(
            'Aucun domaine défini — le cap se pose en session de définition, dans Maintenant.',
            style: TextStyle(
                fontSize: 13.5, color: cs.onSurface.withOpacity(.7))),
      );
    }
    final d = cap.domain;
    final defined = d.definedAt;
    final reneg = d.renegotiatedAt;
    final subParts = <String>[
      '${d.name} n° ${cap.rank}',
      if (defined != null)
        'ta formulation, session du ${defined.day} ${_monthFr(defined.month)}',
      if (reneg != null) 'renégocié le ${reneg.day} ${_monthFr(reneg.month)}',
    ];
    return _card(
      cs,
      'LE CAP',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('« ${d.intention} »',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontStyle: FontStyle.italic,
                        height: 1.3)),
              ),
              TextButton.icon(
                onPressed: () => _editCap(d),
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Changer'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurface.withOpacity(.6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subParts.join(' · '),
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(.55))),
        ],
      ),
    );
  }

  Widget _strategyCard(ColorScheme cs) {
    final report = _report;
    return _card(
      cs,
      'STRATÉGIE · JEU → DIM',
      _strategy.isEmpty
          ? Text(
              report == null
                  ? 'Pas encore de rapport hebdo — la stratégie naît de la décision du dimanche et du vital des domaines.'
                  : 'Rien à prioriser cette semaine — le vital et la décision du rapport rempliront cette carte.',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withOpacity(.65)))
          : ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _strategy.length,
              onReorder: _onReorder,
              itemBuilder: (ctx, i) {
                final s = _strategy[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(s.key),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                color: i == 0
                                    ? cs.primary
                                    : cs.onSurface.withOpacity(.4))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: s.title,
                                style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                            if (s.sub != null)
                              TextSpan(
                                  text: ' — ${s.sub}',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: cs.onSurface.withOpacity(.55))),
                          ])),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Icon(Icons.drag_handle_rounded,
                              size: 18,
                              color: cs.onSurface.withOpacity(.35)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      tagTrailing: Text(
        report != null
            ? 'décision du rapport S${report.isoWeek} · Réordonner ⇅'
            : 'Réordonner ⇅',
        style:
            TextStyle(fontSize: 10.5, color: cs.onSurface.withOpacity(.45)),
      ),
    );
  }

  Widget _tactiqueCard(ColorScheme cs, DateTime now) {
    final todayLine =
        _narrToday ?? tactiqueTodayLine(now, _today?.blocks ?? const []);
    final tomorrowLine = _narrTomorrow ??
        tactiqueTomorrowLine(
          now: now,
          tomorrowBlocks: _tomorrow?.blocks ?? const [],
          artifacts: _artifacts,
          todayBlocks: _today?.blocks ?? const [],
        ) ??
        'à poser ce soir au check-in';
    Widget row(String label, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 62,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: cs.onSurface.withOpacity(.45))),
              ),
              Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 14, height: 1.4)),
              ),
            ],
          ),
        );
    return _card(
      cs,
      'TACTIQUE',
      Column(children: [
        row('AUJ.', todayLine),
        row('DEMAIN', tomorrowLine),
      ]),
    );
  }

  String _monthFr(int m) => const [
        'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
        'août', 'septembre', 'octobre', 'novembre', 'décembre'
      ][m - 1];
}
