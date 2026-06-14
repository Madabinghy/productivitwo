import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

const _kBg = Color(0xFF0E1512);

/// UI MOBILE native du « Monde » (reconstruite, pas le portage du sheet web).
/// Étape 1 : la LISTE des domaines. Tap → gameplay mobile du domaine (étape 2).
Future<void> showWorldMobile(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.6),
    builder: (_) => Dialog.fullscreen(
      backgroundColor: _kBg,
      child: _WorldMobileList(logic: logic, sync: sync),
    ),
  );
}

class _WorldMobileList extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _WorldMobileList({required this.logic, required this.sync});
  @override
  State<_WorldMobileList> createState() => _WorldMobileListState();
}

class _WorldMobileListState extends State<_WorldMobileList> {
  AppLogic get logic => widget.logic;

  // Statut du JOUR d'un domaine : nb de nuisibles en retard / faits aujourd'hui,
  // sur ses routines quotidiennes + activités-temps.
  ({int overdue, int done}) _todayStatus(String domainId) {
    var overdue = 0, done = 0;
    for (final a in logic.state.activeActivities) {
      if (a.domainId != domainId) continue;
      final tokens =
          a.isHabit ? logic.routineWeekTokens(a.id) : logic.activityTimeTokens(a.id);
      if (tokens.isEmpty) continue;
      final t = tokens.last.type; // aujourd'hui = dernier
      if (t == 'spider') {
        overdue++;
      } else if (t == 'flame' || t == 'leaf') {
        done++;
      }
    }
    return (overdue: overdue, done: done);
  }

  @override
  Widget build(BuildContext context) {
    final domains = logic.state.activeDomains;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
          child: Row(children: [
            const Text('🌍 Tes domaines',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
        ),
        Expanded(
          child: domains.isEmpty
              ? const Center(
                  child: Text('Aucun domaine actif.',
                      style: TextStyle(color: Colors.white38)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                  itemCount: domains.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _domainTile(domains[i]),
                ),
        ),
      ],
    );
  }

  Widget _domainTile(Domain d) {
    final color = domainColor(d.id, logic.state.activeDomains) ?? const Color(0xFF4FA3FF);
    final st = _todayStatus(d.id);
    return Material(
      color: color.withOpacity(.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Étape 2 (à venir) : ouvrir le gameplay mobile du domaine.
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: color.withOpacity(.85),
            content: Text('Gameplay « ${d.name} » — étape 2 à venir'),
            duration: const Duration(milliseconds: 1400),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(.45)),
          ),
          child: Row(children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ),
            if (st.overdue > 0) ...[
              const Text('🕷️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 3),
              Text('${st.overdue}',
                  style: const TextStyle(
                      color: Color(0xFFE5604D),
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
              const SizedBox(width: 10),
            ],
            if (st.done > 0) ...[
              const Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 3),
              Text('${st.done}',
                  style: TextStyle(
                      color: color.withOpacity(.9),
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: color.withOpacity(.6)),
          ]),
        ),
      ),
    );
  }
}
