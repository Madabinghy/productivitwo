import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineReachedDays;
import 'package:productivitwo_v1/utils/dashboard_tiles.dart' show DashTile, TileMark;
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/utils/minimum.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/embers_view.dart' show kHardDayColor;
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus, routineTodayCount;
import 'package:productivitwo_v1/widgets/undo_snack.dart';

/// Le minimum, écrans (maquette validée 2026-11-06, écrans 5 à 8) : la feuille du choix, la carte en tête
/// d'Aujourd'hui pendant la période (journée tenue au minimum, question tous les 3 jours) et la tuile.

List<Activity> _dailyRoutines(AppLogic logic) =>
    logic.state.activeActivities.where((a) => a.isHabit && a.habitFreq == HabitFreq.daily).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Les routines gardées de la période en cours (encore existantes), dans l'ordre de la liste.
List<Activity> minimumKept(AppLogic logic) {
  final p = logic.minimumNow;
  if (p == null) return const [];
  return [for (final a in _dailyRoutines(logic)) if (p.keep.contains(a.id)) a];
}

bool _reached(AppLogic logic, Activity a) => routineTodayCount(logic, a) >= (a.habitTarget ?? 1).clamp(1, 9999);

/// La tuile du tableau de bord pendant la période : « AU MINIMUM · k / n », à la place de Journée parfaite.
DashTile? minimumTile(AppLogic logic) {
  final p = logic.minimumNow;
  if (p == null) return null;
  final kept = minimumKept(logic);
  final done = kept.where((a) => _reached(logic, a)).length;
  final day = p.dayOf(logic.livedTodayYmd);
  return DashTile(
    label: 'AU MINIMUM',
    badge: 'jour $day',
    value: kept.isEmpty ? 'Rien de gardé' : (done == kept.length ? 'Tenue ✓' : 'Il manque ${kept.length - done}'),
    sub: done == kept.length && kept.isNotEmpty ? 'journée tenue au minimum' : kept.where((a) => !_reached(logic, a)).map((a) => a.name).join(' · '),
    mini: [for (final a in kept) _reached(logic, a) ? TileMark.on : TileMark.off],
  );
}

/// Feuille « Qu'est-ce que tu tiens quand même ? » : 2 ou 3 routines, les autres attendent. Renvoie true quand la
/// période est ouverte (ou les routines changées, si [edit]).
Future<bool?> showMinimumSheet(BuildContext context, {required AppLogic logic, bool fromYesterday = false, bool edit = false}) {
  final routines = _dailyRoutines(logic);
  final reached = {for (final a in routines) a.id: routineReachedDays(a, logic.state.habitHits, dayStartMin: logic.dayStartMin)};
  final picked = <String>{...(edit ? (logic.minimumNow?.keep ?? const <String>[]) : suggestMinimum(reached, logic.livedTodayYmd))};
  final series = {for (final l in logic.lostSeriesIfNotHard()) l.activityId: l.length};
  int? lengthOf(Activity a) {
    final s = reached[a.id]!;
    var n = 0;
    var d = minShift(logic.livedTodayYmd, -1);
    while (s.contains(d) && n < 999) {
      n++;
      d = minShift(d, -1);
    }
    return n > 0 ? n : series[a.id];
  }

  return showFiche<bool>(context, builder: (ctx, scroll) {
    return StatefulBuilder(builder: (ctx, setLocal) {
      final n = picked.length;
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          Row(children: [
            Expanded(
              child: Text(edit ? 'Ton minimum' : 'Qu’est-ce que tu tiens quand même ?',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBText)),
            ),
            const InfoDot(kRuleMinimum),
          ]),
          const SizedBox(height: 4),
          Text(
              '2 ou 3 routines, les plus simples ou celles qui te font du bien. Les autres attendent, gelées${fromYesterday ? ', hier compris' : ''}. '
              'Une journée qui les tient sera « tenue au minimum », pas « parfaite ».',
              style: const TextStyle(fontSize: 13.5, color: kBText3)),
          const SizedBox(height: 12),
          for (final a in routines)
            InkWell(
              key: ValueKey('minimum-pick-${a.id}'),
              onTap: () => setLocal(() => picked.contains(a.id) ? picked.remove(a.id) : picked.add(a.id)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: picked.contains(a.id) ? kHardDayColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: picked.contains(a.id) ? kHardDayColor : kBText4, width: 2),
                    ),
                    child: picked.contains(a.id) ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF0A1033)) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(a.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBText))),
                  if (picked.contains(a.id))
                    Text(lengthOf(a) == null ? '' : '${lengthOf(a)} j', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kBText3))
                  else
                    const Text('gelée', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kHardDayColor)),
                ]),
              ),
            ),
          const SizedBox(height: 10),
          Text(
              n == 0
                  ? 'Choisis au moins une routine.'
                  : (n > 3 ? 'Plus de 3, c’est déjà beaucoup pour une période difficile.' : 'On te redemande dans $kMinimumCheckDays jours.'),
              style: TextStyle(fontSize: 12.5, color: n > 3 ? kPalierAmberText : kBText4)),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('minimum-start'),
            onPressed: n == 0
                ? null
                : () async {
                    final keep = [for (final a in routines) if (picked.contains(a.id)) a.id];
                    if (edit) {
                      await logic.setMinimumKeep(keep);
                    } else {
                      await logic.startMinimum(keep, fromYesterday: fromYesterday);
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: kHardDayColor,
              foregroundColor: const Color(0xFF0A1033),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: Text(edit ? 'Garder ces $n routines' : 'Passer au minimum · $n routine${n > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
        ],
      );
    });
  });
}

/// Ambre lisible sur fond sombre (texte d'avertissement).
const kPalierAmberText = Color(0xFFFFC870);

/// La carte en tête d'Aujourd'hui pendant la période : jour n, journée tenue au minimum k / n, les routines gardées
/// avec leur +1, les gelées qui attendent ; tous les 3 jours, « Comment tu te sens ? ».
class MinimumCard extends StatelessWidget {
  final AppLogic logic;
  final VoidCallback onChanged;
  const MinimumCard({super.key, required this.logic, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = logic.minimumNow;
    if (p == null) return const SizedBox.shrink();
    final today = logic.livedTodayYmd;
    final kept = minimumKept(logic);
    final done = kept.where((a) => _reached(logic, a)).length;
    final frozen = _dailyRoutines(logic).length - kept.length;
    final due = minimumCheckDue(p, today);
    final day = p.dayOf(today);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(18), border: Border.all(color: kHardDayColor.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('LE MINIMUM · JOUR $day', style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kHardDayColor)),
          const InfoDot(kRuleMinimum, size: 16),
          const Spacer(),
          if (!due)
            TextButton(
              key: const ValueKey('minimum-better'),
              onPressed: () => _better(context),
              style: TextButton.styleFrom(foregroundColor: kHardDayColor, visualDensity: VisualDensity.compact),
              child: const Text('Ça va mieux', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
        ]),
        if (due) ...[
          const SizedBox(height: 2),
          const Text('Comment tu te sens ?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBText)),
          const SizedBox(height: 2),
          Text('$frozen série${frozen > 1 ? 's gelées sont intactes' : ' gelée est intacte'}. Tu reprends tout, ou encore $kMinimumCheckDays jours au minimum ?',
              style: const TextStyle(fontSize: 13, color: kBText3)),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('minimum-end'),
            onPressed: () => _better(context, confirm: false),
            style: FilledButton.styleFrom(
              backgroundColor: kHardDayColor,
              foregroundColor: const Color(0xFF0A1033),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('Ça va mieux · je reprends tout', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const ValueKey('minimum-extend'),
            onPressed: () async {
              await logic.extendMinimum();
              onChanged();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: kBText,
              side: const BorderSide(color: kBLine),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: Text('Encore $kMinimumCheckDays jours au minimum', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
        ],
        Text('Journée tenue au minimum · $done / ${kept.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kBText)),
        const Text('sa propre couleur · ne compte pas pour Journée parfaite', style: TextStyle(fontSize: 11.5, color: kBText4)),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < kept.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(height: 8, decoration: BoxDecoration(color: i < done ? kPalierGreenMin : kBRaised, borderRadius: BorderRadius.circular(4))),
            ),
          ],
        ]),
        const SizedBox(height: 4),
        for (final a in kept) _row(context, a),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text('$frozen routine${frozen > 1 ? 's gelées · elles t’attendent' : ' gelée · elle t’attend'}',
                style: const TextStyle(fontSize: 12.5, color: kBText3)),
          ),
          TextButton(
            key: const ValueKey('minimum-edit'),
            onPressed: () async {
              final ok = await showMinimumSheet(context, logic: logic, edit: true);
              if (ok == true) onChanged();
            },
            style: TextButton.styleFrom(foregroundColor: kBText3, visualDensity: VisualDensity.compact),
            child: const Text('Changer', style: TextStyle(fontSize: 12.5, decoration: TextDecoration.underline)),
          ),
        ]),
      ]),
    );
  }

  Widget _row(BuildContext context, Activity a) {
    final count = routineTodayCount(logic, a);
    final target = (a.habitTarget ?? 1).clamp(1, 9999);
    final ok = count >= target;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
      child: Row(children: [
        Expanded(child: Text(a.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kBText))),
        Text('$count / $target', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ok ? kPalierGreenMin : kBText3)),
        const SizedBox(width: 8),
        SizedBox(
          height: 32,
          child: FilledButton(
            key: ValueKey('minimum-plus-${a.id}'),
            onPressed: () {
              routinePlus(logic, a);
              onChanged();
            },
            style: FilledButton.styleFrom(
              backgroundColor: ok ? kBRaised : kHardDayColor,
              foregroundColor: ok ? kBText : const Color(0xFF0A1033),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('+1', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }

  Future<void> _better(BuildContext context, {bool confirm = true}) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ça va mieux ?'),
          content: const Text('Toutes tes routines comptent de nouveau dès aujourd’hui. Tes séries gelées reprennent là où elles étaient.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pas encore')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Je reprends tout')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await logic.endMinimum();
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showClosingSnackBar(const SnackBar(
        content: Text('Tu reprends toutes tes routines · tes séries repartent d’où elles étaient'),
        duration: Duration(seconds: 5),
      ));
    }
  }
}

/// Vert « tenue » du minimum.
const kPalierGreenMin = Color(0xFF2FA36B);
