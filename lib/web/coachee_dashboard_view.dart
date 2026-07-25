import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/web/palier_colors.dart';

// ─── HUB ACTIONS + TABLEAU DE BORD DU COACHÉ (web) ───────────────────────────
//
// L'onglet Actions devient un hub à rail gauche :
//   Actions · Ma semaine · un bouton par domaine.
// « Ma semaine » = la MÊME lecture que la console coach 8a, mais sur ses
// propres données, tous domaines confondus — transparence totale : le coaché
// voit ce que le coach voit (le coach, lui, ne voit que le périmètre
// partagé). Une vue par domaine détaille engagements, temps 7 j, projets
// actifs et actions en attente.

class ActionsHubView extends StatefulWidget {
  final List<Domain> domains;
  final List<Activity> activities;
  final List<Project> projects;
  final FirestoreSync sync;

  /// L'onglet Actions existant (WebActionsView), construit par le parent.
  final Widget actionsView;

  const ActionsHubView({
    super.key,
    required this.domains,
    required this.activities,
    required this.projects,
    required this.sync,
    required this.actionsView,
  });

  @override
  State<ActionsHubView> createState() => _ActionsHubViewState();
}

class _ActionsHubViewState extends State<ActionsHubView> {
  String _section = 'actions'; // actions | semaine | <domainId>
  List<HabitHit> _hits = [];
  List<Session> _sessions = [];
  bool _statsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    // 28 jours de coches (tendance 4 semaines) + 7 jours de sessions (temps).
    final results = await Future.wait([
      widget.sync.fetchRecentHabitHits(28),
      widget.sync.fetchRecentSessions(7),
    ]);
    if (!mounted) return;
    setState(() {
      _hits = results[0] as List<HabitHit>;
      _sessions = results[1] as List<Session>;
      _statsLoaded = true;
    });
  }

  List<Domain> get _activeDomains =>
      widget.domains.where((d) => !d.deleted).toList();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final wide = box.maxWidth >= 800;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 210, child: _rail(vertical: true)),
            VerticalDivider(width: 1, color: Colors.white.withOpacity(.07)),
            Expanded(child: _content()),
          ],
        );
      }
      return Column(children: [
        SizedBox(height: 48, child: _rail(vertical: false)),
        Divider(height: 1, color: Colors.white.withOpacity(.07)),
        Expanded(child: _content()),
      ]);
    });
  }

  // ── Rail ────────────────────────────────────────────────────────────────────

  Widget _rail({required bool vertical}) {
    final cs = Theme.of(context).colorScheme;

    Widget item(String key, String label, {IconData? icon, Color? dot}) {
      final sel = _section == key;
      final child = Container(
        margin: vertical
            ? const EdgeInsets.only(bottom: 4)
            : const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF12241B) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: sel ? kPalierGreen.withOpacity(.35) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null)
            Icon(icon,
                size: 15,
                color: sel ? kPalierGreen : cs.onSurface.withOpacity(.55)),
          if (dot != null)
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          vertical
              ? Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel
                              ? cs.onSurface
                              : cs.onSurface.withOpacity(.7))))
              : Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color:
                          sel ? cs.onSurface : cs.onSurface.withOpacity(.7))),
        ]),
      );
      return InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => setState(() => _section = key),
        child: child,
      );
    }

    final items = <Widget>[
      item('actions', 'Actions', icon: Icons.checklist_rounded),
      item('semaine', 'Ma semaine', icon: Icons.insights_rounded),
      if (vertical)
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6, left: 12),
          child: Text('DOMAINES',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: cs.onSurface.withOpacity(.4))),
        ),
      for (final d in _activeDomains)
        item(d.id, d.name,
            dot: domainColor(d.id, _activeDomains) ?? cs.primary),
    ];

    return vertical
        ? ListView(padding: const EdgeInsets.all(10), children: items)
        : ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: items);
  }

  // ── Contenu ─────────────────────────────────────────────────────────────────

  Widget _content() {
    if (_section == 'actions') return widget.actionsView;
    if (!_statsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_section == 'semaine') return _weekDashboard();
    final domain =
        _activeDomains.where((d) => d.id == _section).firstOrNull;
    if (domain == null) return widget.actionsView;
    return _domainDashboard(domain);
  }

  // Widgets partagés par les deux tableaux de bord.

  Widget _bigNumber(ColorScheme cs, String label, String value, Color? color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(value,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: color ?? cs.onSurface)),
        Text(label,
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(.45))),
      ]);

  Widget _sectionLabel(ColorScheme cs, String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.35,
                color: cs.onSurface.withOpacity(.45))),
      );

  Widget _engagementRow(ColorScheme cs, EngagementStat e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(e.kept ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: e.kept ? kPalierGreen : cs.onSurface.withOpacity(.35)),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(e.label, style: const TextStyle(fontSize: 13.5))),
          Text('${e.done} / ${e.target}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: e.kept
                      ? kPalierGreen
                      : cs.onSurface.withOpacity(.7))),
        ]),
      );

  Widget _trendTiles(List<({String startYmd, int pct})> weeks) {
    const labels = ['S-3', 'S-2', 'S-1', 'S'];
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      for (var i = 0; i < weeks.length; i++) ...[
        Expanded(
          child: Column(children: [
            Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palierColor(weeks[i].pct).withOpacity(.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palierColor(weeks[i].pct)),
              ),
              child: Text('${weeks[i].pct} %',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(height: 4),
            Text(labels[i],
                style: TextStyle(
                    fontSize: 10.5, color: cs.onSurface.withOpacity(.45))),
          ]),
        ),
        if (i < weeks.length - 1) const SizedBox(width: 8),
      ],
    ]);
  }

  String _lastLabel(DateTime? last) {
    if (last == null) return '—';
    final days = DateTime.now().difference(last).inDays;
    return days <= 0 ? 'auj.' : (days == 1 ? 'hier' : 'il y a $days j');
  }

  // ── « Ma semaine » : la vue coach, sur soi ──────────────────────────────────

  Widget _weekDashboard() {
    final cs = Theme.of(context).colorScheme;
    final monday = mondayOf(DateTime.now());
    final engagements = weekEngagements(
        activities: widget.activities, hits: _hits, weekStart: monday);
    final weeks =
        fourWeekTrend(activities: widget.activities, hits: _hits);
    final kept = engagements.where((e) => e.kept).length;
    final total = engagements.length;
    final pct = total == 0 ? 0 : ((kept / total) * 100).round();
    final delta = weeks.length >= 2
        ? weeks.last.pct - weeks[weeks.length - 2].pct
        : 0;
    final last = lastActivityAt(sessions: _sessions, hits: _hits);
    final byDomain = <String, List<EngagementStat>>{};
    for (final e in engagements) {
      byDomain.putIfAbsent(e.domainId, () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ma semaine',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                Text(
                    'La même lecture que ton coach — lui ne voit que les '
                    'domaines que tu partages.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withOpacity(.55))),
              ],
            ),
          ),
          if (total > 0) ...[
            _bigNumber(cs, 'ENGAGEMENTS', '$kept / $total', palierColor(pct)),
            const SizedBox(width: 22),
            _bigNumber(cs, 'TENDANCE', '${delta >= 0 ? '+' : ''}$delta pts',
                delta >= 0 ? kPalierGreen : kPalierCoral),
            const SizedBox(width: 22),
            _bigNumber(cs, 'DERNIÈRE ACTIVITÉ', _lastLabel(last), null),
          ],
          const SizedBox(width: 8),
          IconButton(
              tooltip: 'Rafraîchir',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _loadStats),
        ]),
        _sectionLabel(cs, '4 DERNIÈRES SEMAINES'),
        _trendTiles(weeks),
        if (engagements.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
                'Aucun engagement hebdo — crée des routines (quotidiennes ou '
                'hebdomadaires) pour voir ta semaine se mesurer ici.',
                style: TextStyle(
                    fontSize: 13.5, color: cs.onSurface.withOpacity(.55))),
          ),
        for (final d in _activeDomains)
          if (byDomain.containsKey(d.id)) ...[
            _sectionLabel(cs, d.name.toUpperCase()),
            for (final e in byDomain[d.id]!) _engagementRow(cs, e),
          ],
      ],
    );
  }

  // ── Vue domaine : stats, projets, actions, routines ────────────────────────

  Widget _domainDashboard(Domain domain) {
    final cs = Theme.of(context).colorScheme;
    final monday = mondayOf(DateTime.now());
    final ids = {domain.id};
    final engagements = weekEngagements(
        activities: widget.activities,
        hits: _hits,
        weekStart: monday,
        domainIds: ids);
    final weeks = fourWeekTrend(
        activities: widget.activities, hits: _hits, domainIds: ids);
    final minutes = weekMinutesByActivity(
        activities: widget.activities, sessions: _sessions, domainIds: ids);
    final topTime = minutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final projects = widget.projects
        .where((p) =>
            p.domainId == domain.id && p.status == 'active' && !p.paused)
        .toList();
    final domainActivities = widget.activities
        .where((a) => !a.deleted && a.domainId == domain.id)
        .toList();
    final pendingOwnActions = [
      for (final a in domainActivities)
        for (final act in a.ownActions)
          if (!act.done) (activity: a, action: act),
    ];
    final kept = engagements.where((e) => e.kept).length;
    final color = domainColor(domain.id, _activeDomains) ?? cs.primary;

    String fmtMin(int m) => m >= 60
        ? '${m ~/ 60} h${(m % 60) > 0 ? ' ${(m % 60).toString().padLeft(2, '0')}' : ''}'
        : '$m min';

    int pendingActionsOf(Project p) {
      var n = 0;
      for (final t in p.tasks) {
        if (t.isMilestone || t.status == 'done' || t.status == 'skipped') {
          continue;
        }
        n += t.actions.where((a) => !a.done).length;
      }
      return n;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(domain.name,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700)),
          ),
          if (engagements.isNotEmpty)
            _bigNumber(
                cs,
                'ENGAGEMENTS',
                '$kept / ${engagements.length}',
                palierColor(engagements.isEmpty
                    ? 0
                    : ((kept / engagements.length) * 100).round())),
        ]),
        _sectionLabel(cs, '4 DERNIÈRES SEMAINES'),
        _trendTiles(weeks),
        if (engagements.isNotEmpty) ...[
          _sectionLabel(cs, 'ROUTINES DE LA SEMAINE'),
          for (final e in engagements) _engagementRow(cs, e),
        ],
        if (topTime.isNotEmpty) ...[
          _sectionLabel(cs, 'TEMPS · 7 DERNIERS JOURS'),
          for (final e in topTime.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(fontSize: 13.5))),
                Text(fmtMin(e.value),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
        if (projects.isNotEmpty) ...[
          _sectionLabel(cs, 'PROJETS EN COURS'),
          for (final p in projects)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(Icons.flag_outlined,
                    size: 15, color: cs.onSurface.withOpacity(.5)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5))),
                Text(
                    pendingActionsOf(p) == 0
                        ? 'à définir'
                        : '${pendingActionsOf(p)} action(s)',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(.5))),
              ]),
            ),
        ],
        if (pendingOwnActions.isNotEmpty) ...[
          _sectionLabel(cs, 'ACTIONS SIMPLES EN ATTENTE'),
          for (final e in pendingOwnActions.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.radio_button_unchecked,
                    size: 14, color: cs.onSurface.withOpacity(.35)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(e.action.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))),
                Text(e.activity.name,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withOpacity(.45))),
              ]),
            ),
        ],
        if (engagements.isEmpty &&
            topTime.isEmpty &&
            projects.isEmpty &&
            pendingOwnActions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
                'Rien à montrer pour ce domaine — pas encore de routine, de '
                'temps loggé ni de projet actif.',
                style: TextStyle(
                    fontSize: 13.5, color: cs.onSurface.withOpacity(.55))),
          ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
