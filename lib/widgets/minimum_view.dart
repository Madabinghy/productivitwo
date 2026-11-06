import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineReachedDays, BadgeState, kHoldOnTiers;
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
  final c = logic.climbNow;
  if (c != null && logic.minimumNow == null) {
    final todo = _toRevive(logic, c);
    final total = todo.length + c.revived.length;
    return DashTile(
      label: 'REMONTÉE',
      badge: 'jour ${_climbDay(logic, c)}',
      value: '${c.revived.length} / $total ravivées',
      sub: _revivedToday(logic, c) ? 'une série ravivée aujourd’hui' : 'ravive une série aujourd’hui',
      mini: [for (var i = 0; i < total; i++) i < c.revived.length ? TileMark.on : TileMark.off],
    );
  }
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
        if (!due) _veilleuse(p, frozen),
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

  /// La veilleuse (lot 3) : « Tu gardes le feu », les journées tenues de la période, Tenir bon, les séries sous la cendre.
  Widget _veilleuse(MinimumPeriod p, int frozen) {
    final routines = _dailyRoutines(logic);
    final reached = {for (final a in routines) a.id: routineReachedDays(a, logic.state.habitHits, dayStartMin: logic.dayStartMin)};
    final heldHere = minimumHeldDays([p], reached, logic.livedTodayYmd).length;
    final heldAll = minimumHeldDays(logic.minimumPeriods, reached, logic.livedTodayYmd).length;
    final next = kHoldOnTiers.where((t) => t > heldAll).firstOrNull;
    final asleep = [for (final a in routines) if (!p.keep.contains(a.id)) a]..sort((x, y) => logic.currentSeriesOf(y).compareTo(logic.currentSeriesOf(x)));
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.local_fire_department_rounded, size: 38 + (heldHere.clamp(0, 7) * 2).toDouble(), color: kVeilleuse),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tu gardes le feu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kBText)),
              Text(heldHere == 0 ? 'Ta première journée au minimum se joue aujourd’hui.' : '$heldHere journée${heldHere > 1 ? 's tenues' : ' tenue'} au minimum. La veilleuse brille un peu plus chaque jour.',
                  style: const TextStyle(fontSize: 12.5, color: kBText3)),
            ]),
          ),
        ]),
        if (next != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < next; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(child: Container(height: 6, decoration: BoxDecoration(color: i < heldAll ? kVeilleuse : kBRaised, borderRadius: BorderRadius.circular(3)))),
            ],
          ]),
          const SizedBox(height: 3),
          Text('Tenir bon · $heldAll / $next jours pour la carte', style: const TextStyle(fontSize: 11.5, color: kBText4)),
        ],
        if (asleep.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('SOUS LA CENDRE · $frozen', style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
          const SizedBox(height: 3),
          Text(asleep.take(4).map((a) => '${a.name} ${logic.currentSeriesOf(a)} j').join(' · ') + (asleep.length > 4 ? '…' : ''),
              style: const TextStyle(fontSize: 12.5, color: kBText3)),
        ],
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
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ça va mieux ?'),
        content: const Text('Pas à pas : tu ravives une série par jour, en plus de ton minimum. C’est comme ça qu’on ne rechute pas. '
            'Ou tu reprends tout d’un coup, dès aujourd’hui.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Pas encore')),
          TextButton(key: const ValueKey('minimum-all'), onPressed: () => Navigator.pop(ctx, 'all'), child: const Text('Tout d’un coup')),
          FilledButton(key: const ValueKey('minimum-climb'), onPressed: () => Navigator.pop(ctx, 'climb'), child: const Text('Pas à pas')),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'climb') {
      await logic.startClimb();
    } else {
      await logic.endMinimum();
    }
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
        content: Text(choice == 'climb'
            ? 'La remontée commence · ravive une série aujourd’hui'
            : 'Tu reprends toutes tes routines · tes séries repartent d’où elles étaient'),
        duration: const Duration(seconds: 5),
      ));
    }
  }
}

/// Vert « tenue » du minimum.
const kPalierGreenMin = Color(0xFF2FA36B);

/// Flamme de la veilleuse.
const kVeilleuse = Color(0xFFFFB347);

List<Activity> _toRevive(AppLogic logic, MinimumPeriod c) =>
    [for (final a in _dailyRoutines(logic)) if (!c.keep.contains(a.id) && !c.revived.containsKey(a.id)) a];

int _climbDay(AppLogic logic, MinimumPeriod c) => c.to == null ? 1 : DateTime.parse(logic.livedTodayYmd).difference(DateTime.parse(c.to!)).inDays;

bool _revivedToday(AppLogic logic, MinimumPeriod c) => c.revived.values.contains(logic.livedTodayYmd);

/// La remontée (lot 3) : après « Ça va mieux · pas à pas », une série ravivée par jour en plus du minimum ; les autres
/// restent sous la cendre, intactes. Au bout : la carte « La remontée ».
class ClimbCard extends StatefulWidget {
  final AppLogic logic;
  final VoidCallback onChanged;
  /// Les cartes du deck, pour « Tes luttes ».
  final List<BadgeState> Function()? badges;
  const ClimbCard({super.key, required this.logic, required this.onChanged, this.badges});

  @override
  State<ClimbCard> createState() => _ClimbCardState();
}

class _ClimbCardState extends State<ClimbCard> {
  bool _more = false;

  AppLogic get logic => widget.logic;

  @override
  Widget build(BuildContext context) {
    final c = logic.climbNow;
    if (c == null || logic.minimumNow != null) return const SizedBox.shrink();
    final todo = _toRevive(logic, c)..sort((x, y) => logic.currentSeriesOf(y).compareTo(logic.currentSeriesOf(x)));
    final total = todo.length + c.revived.length;
    final today = _revivedToday(logic, c);
    final names = {for (final a in logic.state.activities) a.id: a.name};
    final todayName = [for (final e in c.revived.entries) if (e.value == logic.livedTodayYmd) names[e.key] ?? ''].join(', ');
    final open = !today || _more;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(18), border: Border.all(color: kVeilleuse.withValues(alpha: .45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('REMONTÉE · JOUR ${_climbDay(logic, c)}', style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kVeilleuse)),
          const InfoDot(kRuleClimb, size: 16),
        ]),
        const SizedBox(height: 2),
        Text('${c.revived.length} / $total séries ravivées', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kBText)),
        const SizedBox(height: 8),
        Wrap(spacing: 5, runSpacing: 5, children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < c.revived.length ? const Color(0xFFFF8A3D) : const Color(0xFF2A2622),
                border: Border.all(color: i < c.revived.length ? const Color(0xFFFF8A3D) : const Color(0xFF3A342E)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        const Text('Ton minimum + 1 série par jour. Pas tout d’un coup : c’est comme ça qu’on ne rechute pas.', style: TextStyle(fontSize: 12.5, color: kBText3)),
        if (today) ...[
          const SizedBox(height: 8),
          Text('✓ $todayName ravivée aujourd’hui · la suivante demain', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kPalierGreenMin)),
          if (!_more)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _more = true),
                style: TextButton.styleFrom(foregroundColor: kBText3, padding: EdgeInsets.zero),
                child: const Text('En raviver une de plus', style: TextStyle(fontSize: 12.5, decoration: TextDecoration.underline)),
              ),
            ),
        ],
        if (open && todo.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('AUJOURD’HUI, TU RAVIVES', style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: kBText3)),
          for (final a in todo.take(4))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
              child: Row(children: [
                Expanded(child: Text(a.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kBText))),
                Text('${logic.currentSeriesOf(a)} j', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kBText3)),
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    key: ValueKey('revive-${a.id}'),
                    onPressed: () => _revive([a.id]),
                    style: FilledButton.styleFrom(
                      backgroundColor: kVeilleuse,
                      foregroundColor: const Color(0xFF2A1600),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('Raviver', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          if (todo.length > 4) Text('+ ${todo.length - 4} autres sous la cendre', style: const TextStyle(fontSize: 12, color: kBText4)),
        ],
        Row(children: [
          TextButton(
            key: const ValueKey('climb-all'),
            onPressed: () => _all(context, todo),
            style: TextButton.styleFrom(foregroundColor: kBText3, padding: EdgeInsets.zero),
            child: const Text('Tout reprendre d’un coup', style: TextStyle(fontSize: 12.5, decoration: TextDecoration.underline)),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => showStrugglesSheet(context, logic: logic, badges: widget.badges?.call() ?? const []),
            style: TextButton.styleFrom(foregroundColor: kBText3, padding: EdgeInsets.zero),
            child: const Text('Tes luttes ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }

  Future<void> _revive(List<String> ids) async {
    await logic.reviveRoutines(ids);
    setState(() => _more = false);
    widget.onChanged();
    if (mounted && logic.climbNow == null) {
      ScaffoldMessenger.of(context).showClosingSnackBar(const SnackBar(
        content: Text('Toutes tes séries sont ravivées · carte « La remontée »'),
        duration: Duration(seconds: 5),
      ));
    }
  }

  Future<void> _all(BuildContext context, List<Activity> todo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tout reprendre d’un coup ?'),
        content: Text('Les ${todo.length} séries encore sous la cendre comptent de nouveau dès aujourd’hui.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pas à pas')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tout reprendre')),
        ],
      ),
    );
    if (ok == true) await _revive([for (final a in todo) a.id]);
  }
}

/// Tes luttes (lot 3) : ce que tu as gagné quand c'était dur — contre la flemme, contre les envies (privé), contre les
/// journées difficiles. Chiffres tirés des cartes existantes.
Future<void> showStrugglesSheet(BuildContext context, {required AppLogic logic, required List<BadgeState> badges}) {
  BadgeState? b(String id) => badges.where((x) => x.def.id == id).firstOrNull;
  int v(String id) => (b(id)?.value ?? 0).round();
  final urges = b('liberte-envies');
  Widget fight(String n, String what, String sub, {bool private = false}) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: kBSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(n, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kBText)),
            const SizedBox(width: 10),
            Expanded(child: Text(what, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kBText))),
            if (private)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: kBRaised, borderRadius: BorderRadius.circular(10)),
                child: const Text('privé', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kBText3)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 12.5, color: kBText3)),
        ]),
      );
  return showFiche<void>(context, builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          const Text('Tes luttes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBText)),
          const SizedBox(height: 2),
          const Text('Ce que tu as gagné quand c’était dur.', style: TextStyle(fontSize: 13, color: kBText3)),
          fight('${v('malgre-tout')}', 'contre la flemme', 'victoires en Flemme · ${v('guerilla')} guérilla${v('guerilla') > 1 ? 's' : ''}'),
          if (urges != null) fight('${v('liberte-envies')}', 'contre les envies', 'envies surmontées · le coach ne voit jamais ce chiffre', private: true),
          fight('${v('tenir-bon')}', 'contre les journées difficiles',
              'journées tenues au minimum · ${v('remontee')} remontée${v('remontee') > 1 ? 's' : ''} · ${v('reprise')} reprise${v('reprise') > 1 ? 's' : ''}'),
          const SizedBox(height: 14),
          const Text('On récompense ce qui demande du courage : tenir, remonter, gagner quand c’est dur. Jamais le fait d’entrer dans le minimum.',
              style: TextStyle(fontSize: 12, color: kBText4)),
        ],
      ));
}
