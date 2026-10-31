import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';

/// Feuille « Dernières 24 h » (pilule 24 h de la barre du haut, refonte
/// 2026-10-31) : la journée en 24 barres horaires à la couleur du domaine, la
/// répartition par domaine, puis les chronos en cartes (tap = modifier,
/// glisser = supprimer). Rafraîchie à chaque changement (`logic.rev`).
Future<void> showLast24hSheet(
  BuildContext context, {
  required AppLogic logic,
  required void Function(Session s) onDelete,
  required Future<void> Function(BuildContext ctx, Session s) onEdit,
}) {
  return showFiche<void>(context, builder: (ctx, scroll) => _Last24h(logic: logic, scroll: scroll, onDelete: onDelete, onEdit: onEdit));
}

/// Minutes de [s] dans la fenêtre [from, to].
int _minutesIn(Session s, DateTime from, DateTime to) {
  final start = s.startAt.isBefore(from) ? from : s.startAt;
  final end0 = s.endAt ?? to;
  final end = end0.isAfter(to) ? to : end0;
  return end.isAfter(start) ? end.difference(start).inMinutes : 0;
}

String _fmt(int min) {
  if (min < 60) return '$min min';
  final m = min % 60;
  return m == 0 ? '${min ~/ 60} h' : '${min ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _Last24h extends StatefulWidget {
  final AppLogic logic;
  final ScrollController scroll;
  final void Function(Session s) onDelete;
  final Future<void> Function(BuildContext ctx, Session s) onEdit;
  const _Last24h({required this.logic, required this.scroll, required this.onDelete, required this.onEdit});

  @override
  State<_Last24h> createState() => _Last24hState();
}

class _Last24hState extends State<_Last24h> {
  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.rev.addListener(_onRev);
  }

  @override
  void dispose() {
    logic.rev.removeListener(_onRev);
    super.dispose();
  }

  void _onRev() {
    if (mounted) setState(() {});
  }

  Activity? _activity(String id) => logic.state.activities.where((a) => a.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final from = now.subtract(const Duration(hours: 24));
    final domains = logic.state.activeDomains;
    final sessions = logic.state.sessions
        .where((s) => !s.deleted && _minutesIn(s, from, now) > 0)
        .toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));

    // Répartition par domaine sur la fenêtre.
    final byDomain = <String?, int>{};
    for (final s in sessions) {
      final d = _activity(s.activityId)?.domainId;
      byDomain[d] = (byDomain[d] ?? 0) + _minutesIn(s, from, now);
    }
    final total = byDomain.values.fold<int>(0, (a, b) => a + b);
    final parts = byDomain.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final bins = logic.minutesByHourLast24(now);
    final binDomains = logic.domainByHourLast24(now);
    final running = sessions.where((s) => s.endAt == null).firstOrNull;

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        FicheHeader(
          title: 'Dernières 24 h',
          chip: total == 0 ? 'rien de chronométré' : '${_fmt(total)} chronométrées',
          chipColor: cs.primary,
          kpi: sessions.isEmpty
              ? null
              : '${sessions.length} chrono${sessions.length > 1 ? 's' : ''}'
                  '${running != null ? ' · ${_activity(running.activityId)?.name ?? 'un chrono'} tourne depuis ${_hm(running.startAt)}' : ''}',
        ),
        const SizedBox(height: 16),
        _hourBand(cs, now, bins, binDomains, domains),
        if (parts.isNotEmpty) ...[
          const SizedBox(height: 20),
          const FicheTitle('RÉPARTITION'),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(children: [
                for (final p in parts)
                  Expanded(
                    flex: p.value < 1 ? 1 : p.value,
                    child: Container(color: domainColor(p.key, domains) ?? cs.primary),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 8, children: [
            for (final p in parts) _legend(cs, domainColor(p.key, domains) ?? cs.primary, _domainName(p.key, domains), p.value, total),
          ]),
        ],
        const SizedBox(height: 22),
        FicheTitle(sessions.isEmpty ? 'CHRONOS' : 'CHRONOS · ${sessions.length}'),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('Aucun chrono sur les dernières 24 h.', style: TextStyle(color: cs.onSurface.withValues(alpha: .6))),
          ),
        for (final s in sessions) _sessionCard(cs, s, from, now, domains),
        if (sessions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Touche un chrono pour le corriger · glisse-le vers la gauche pour le supprimer',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .45))),
          ),
      ],
    );
  }

  String _domainName(String? id, List<Domain> domains) =>
      domains.where((d) => d.id == id).map((d) => d.name).firstOrNull ?? 'Sans domaine';

  /// 24 barres horaires (la dernière = l'heure en cours), remplies selon les
  /// minutes chronométrées, à la couleur du domaine dominant de l'heure.
  Widget _hourBand(ColorScheme cs, DateTime now, List<int> bins, List<String?> binDomains, List<Domain> domains) {
    final firstHour = DateTime(now.year, now.month, now.day, now.hour).subtract(const Duration(hours: 23));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Column(children: [
        SizedBox(
          height: 84,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 24; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: _bar(cs, i < bins.length ? bins[i].clamp(0, 60) : 0,
                      (i < binDomains.length ? domainColor(binDomains[i], domains) : null) ?? cs.primary, current: i == 23),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < 24; i++)
            Expanded(
              child: Text(
                i % 6 == 0 || i == 23 ? (i == 23 ? 'now' : '${firstHour.add(Duration(hours: i)).hour}h') : '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: TextStyle(fontSize: 10, fontWeight: i == 23 ? FontWeight.w800 : FontWeight.w500, color: cs.onSurface.withValues(alpha: i == 23 ? .8 : .45)),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _bar(ColorScheme cs, int mins, Color color, {required bool current}) {
    final frac = mins / 60.0;
    return LayoutBuilder(builder: (_, c) {
      final h = c.maxHeight;
      return Stack(alignment: Alignment.bottomCenter, children: [
        Container(
          height: h,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(4),
            border: current ? Border.all(color: cs.onSurface.withValues(alpha: .35), width: 1) : null,
          ),
        ),
        if (mins > 0)
          Container(
            height: (h * frac).clamp(3.0, h),
            decoration: BoxDecoration(
              color: current ? color : color.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ]);
    });
  }

  Widget _legend(ColorScheme cs, Color color, String name, int min, int total) {
    final pct = total == 0 ? 0 : (min * 100 / total).round();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(width: 5),
      Text('${_fmt(min)} · $pct %', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
    ]);
  }

  Widget _sessionCard(ColorScheme cs, Session s, DateTime from, DateTime now, List<Domain> domains) {
    final a = _activity(s.activityId);
    final color = domainColor(a?.domainId, domains) ?? cs.primary;
    final live = s.endAt == null;
    final mins = s.duration.inMinutes;
    final dName = a == null ? null : domains.where((d) => d.id == a.domainId).map((d) => d.name).firstOrNull;
    // ignore: non_const_argument_for_const_parameter
    final icon = a?.iconCode != null ? IconData(a!.iconCode!, fontFamily: 'MaterialIcons') : Icons.timer_outlined;
    final started = s.startAt.isBefore(from) ? 'hier ${_hm(s.startAt)}' : _hm(s.startAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(s.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
        ),
        onDismissed: (_) => widget.onDelete(s),
        child: Material(
          color: live ? color.withValues(alpha: .14) : cs.surfaceContainerHighest.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => widget.onEdit(context, s),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: .2), shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a?.name.isNotEmpty == true ? a!.name : 'Activité',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [if (dName != null) dName, '$started → ${live ? 'maintenant' : _hm(s.endAt!)}'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6)),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                if (live)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                    child: Text('en cours · ${_fmt(mins)}',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black)),
                  )
                else
                  Text(_fmt(mins), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
