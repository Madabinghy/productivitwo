import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';

// ─── « OÙ ON VA » (24d) — la ligne d'horizon, 100 % assemblage de faits ──────
//
// 3 cartes : le cap (intention n° 1, mots du user), la stratégie (décision du
// rapport + vital compté, réordonnable), la tactique (programme du jour +
// entries d'artefacts de J+1). Rien d'inventé : une donnée absente = ligne
// absente. Seul le narratif (2 lignes) passe par le modèle — hors de ce
// fichier, avec fallback sur les lignes déterministes construites ici.

/// Le cap : premier domaine DÉFINI de la liste (l'ordre de st.domains EST le
/// rang posé au nommage). Null si aucun domaine défini — la carte le dit.
({Domain domain, int rank})? capDomain(AppState st) {
  var rank = 1;
  for (final d in st.domains) {
    if (d.deleted) continue;
    if (d.isDefined) return (domain: d, rank: rank);
    rank++;
  }
  return null;
}

/// Une priorité de la stratégie. [key] est STABLE (persistance de l'ordre).
class StrategyItem {
  final String key;
  final String title;
  final String? sub;
  const StrategyItem({required this.key, required this.title, this.sub});
}

/// Les priorités jeu → dim, issues des faits : décision APPLIQUÉE du rapport
/// hebdo d'abord, puis le minimum vital compté en direct (max 2 domaines),
/// puis la micro-action Gantt en bonus. Jamais de priorité inventée.
List<StrategyItem> buildStrategyItems({
  required DateTime now,
  required AppState st,
  WeeklyReport? report,
  GanttMicroAction? gantt,
}) {
  final items = <StrategyItem>[];

  final decision = report?.proposedDecision;
  if (decision != null && report!.decisionStatus == 'applied') {
    items.add(StrategyItem(
      key: 'decision',
      title: decision.to,
      sub:
          'décision du rapport S${report.isoWeek}${decision.domainName.isNotEmpty ? ' · ${decision.domainName}' : ''}',
    ));
  }

  // Vital compté : métriques sessions* hebdo des domaines définis, comptées
  // depuis les sessions réelles (≥ 10 min) de la semaine en cours.
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final ymd = _ymd(now);
  var vitals = 0;
  for (final d in st.domains) {
    if (d.deleted || !d.isDefined) continue;
    if (d.tracking == 'declared' || d.suspendedOn(ymd)) continue;
    for (final v in d.vitalMinimum) {
      if (v.period != 'week' || v.target <= 0) continue;
      if (!v.metric.startsWith('sessions')) continue;
      var count = 0;
      for (final s in st.sessions) {
        if (s.startAt.isBefore(monday)) continue;
        final act =
            st.activities.where((a) => a.id == s.activityId).firstOrNull;
        if (act == null || act.domainId != d.id) continue;
        if ((s.endAt ?? now).difference(s.startAt).inMinutes >= 10) count++;
      }
      items.add(StrategyItem(
        key: 'vital:${d.id}',
        title: 'Vital ${d.name} : ${v.label}',
        sub: '$count / ${v.target.toInt()} · sem.',
      ));
      vitals++;
      break; // une priorité vitale par domaine
    }
    if (vitals >= 2) break;
  }

  if (gantt != null) {
    items.add(StrategyItem(
      key: 'gantt',
      title: gantt.taskTitle,
      sub: 'du bonus, pas du dû',
    ));
  }
  return items;
}

/// Applique l'ordre du user (⇅, persisté sur le rapport) : les clés connues
/// dans l'ordre stocké d'abord, les nouvelles priorités ensuite (ordre des
/// faits). Un item disparu des faits disparaît — l'ordre ne ressuscite rien.
List<StrategyItem> applyStrategyOrder(
    List<StrategyItem> items, List<String> order) {
  if (order.isEmpty) return items;
  final byKey = {for (final i in items) i.key: i};
  final out = <StrategyItem>[
    for (final k in order)
      if (byKey.containsKey(k)) byKey.remove(k)!,
  ];
  out.addAll(items.where((i) => byKey.containsKey(i.key)));
  return out;
}

/// Ligne « AUJ. » déterministe : les prochains engagements du jour (pending,
/// hors prep/pause), 3 max. Fallback du narratif — et vérité s'il est absent.
String tactiqueTodayLine(DateTime now, List<ScheduleBlock> blocks) {
  final pending = blocks
      .where((b) =>
          b.status == 'pending' && !b.isPrep && b.category != 'break')
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (pending.isEmpty) return 'rien de posé — 2 min pour planifier';
  final parts = pending
      .take(3)
      .map((b) => '${_hhmmToFr(b.startTime)} ${b.title}')
      .toList();
  final more = pending.length > 3 ? ' (+${pending.length - 3})' : '';
  return '${parts.join(' · ')}$more';
}

/// Ligne « DEMAIN » déterministe : programme de demain s'il est posé, sinon
/// les entries d'artefacts datées de demain ; + la prep de ce soir si elle
/// existe. Null = rien à dire (la carte affiche « à poser au check-in »).
String? tactiqueTomorrowLine({
  required DateTime now,
  List<ScheduleBlock> tomorrowBlocks = const [],
  List<Artifact> artifacts = const [],
  List<ScheduleBlock> todayBlocks = const [],
}) {
  final t = now.add(const Duration(days: 1));
  final tomorrowYmd = _ymd(t);
  const codes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final wd = codes[t.weekday - 1];

  final parts = <String>[];
  final pending = tomorrowBlocks
      .where((b) =>
          b.status == 'pending' && !b.isPrep && b.category != 'break')
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (pending.isNotEmpty) {
    parts.addAll(
        pending.take(3).map((b) => '${_hhmmToFr(b.startTime)} ${b.title}'));
  } else {
    // Le programme n'est pas posé : les artefacts disent déjà demain.
    for (final a in artifacts) {
      if (a.deleted) continue;
      for (final e in a.entries) {
        if (e.date == tomorrowYmd || (e.date == null && e.weekday == wd)) {
          parts.add(
              '${_hhmmToFr(e.time)} ${e.title} (${a.kind == 'weekly_menu' ? 'menu' : 'plan'})');
          break; // une entrée par artefact — la ligne reste courte
        }
      }
      if (parts.length >= 2) break;
    }
  }

  // Prep de ce soir liée à demain : « demain se gagne ce soir ».
  ScheduleBlock? prep;
  for (final b in todayBlocks) {
    if (b.isPrep && b.status == 'pending' && b.prepForDate == tomorrowYmd) {
      prep = b;
      break;
    }
  }
  if (prep != null) {
    parts.add('prep ce soir ${_hhmmToFr(prep.startTime)}');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

// ── Helpers locaux ───────────────────────────────────────────────────────────

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "07:15" → "7 h 15" ; "07:00" → "7 h".
String _hhmmToFr(String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  return m == '00' ? '$h h' : '$h h $m';
}
