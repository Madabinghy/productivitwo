import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';

/// L'ANCIEN Miracle Morning (2026-11-16) : des étapes dans un ordre, déroulées sur un écran à part. Depuis le
/// 2026-11-21 il est un MOMENT de la journée (`kMomentMiracle`) et c'est le Sniper qui le déroule. Il ne reste ici
/// que la lecture des étapes déjà réglées (`data/meta.miracleMorning {steps: [...]}`) et leur PASSAGE en routines
/// du moment ([miraclePassage], [applyMiraclePassage]). Les matinées déjà faites restent des `ChainRun`
/// `kind: "miracle"`.
const kMiracleKind = 'miracle';

class MiracleStep {
  final String id;
  final String name;
  final String? routineId;
  final int minutes;
  final String? note;
  const MiracleStep({required this.id, required this.name, this.routineId, this.minutes = 5, this.note});

  MiracleStep copyWith({String? name, int? minutes, String? note, bool clearNote = false}) =>
      MiracleStep(id: id, name: name ?? this.name, routineId: routineId, minutes: minutes ?? this.minutes, note: clearNote ? null : (note ?? this.note));

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (routineId != null) 'routineId': routineId,
        'minutes': minutes,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  static MiracleStep? from(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    final m = raw['minutes'];
    final r = raw['routineId'], n = raw['note'];
    return MiracleStep(
      id: id,
      name: name,
      routineId: r is String && r.isNotEmpty ? r : null,
      minutes: m is num ? m.round().clamp(1, 120) : 5,
      note: n is String && n.isNotEmpty ? n : null,
    );
  }
}

class MiracleMorning {
  final List<MiracleStep> steps;
  const MiracleMorning(this.steps);

  int get totalMin => steps.fold(0, (s, x) => s + x.minutes);
  bool get isEmpty => steps.isEmpty;

  Map<String, dynamic> toJson() => {'steps': [for (final s in steps) s.toJson()]};

  /// null = jamais réglé (on part des routines du matin).
  static MiracleMorning? from(dynamic raw) {
    if (raw is! Map || raw['steps'] is! List) return null;
    return MiracleMorning([for (final s in raw['steps'] as List) if (MiracleStep.from(s) case final x?) x]);
  }
}

/// Ce que devient une étape au passage.
enum PassageKind {
  /// Sa routine passe au moment Miracle Morning.
  moved,

  /// Sa routine est répartie : elle garde ses moments et prend une part au Miracle Morning.
  shared,

  /// Étape libre (sans routine) : elle devient une routine quotidienne du moment.
  created,
}

class PassageLine {
  final MiracleStep step;
  final PassageKind kind;
  final Activity? routine;
  const PassageLine(this.step, this.kind, [this.routine]);

  /// « routine · matin », « routine répartie », « étape libre · 5 min ».
  String get before => switch (kind) {
        PassageKind.created => 'étape libre · ${step.minutes} min',
        PassageKind.shared => 'routine répartie',
        PassageKind.moved => () {
            final m = momentOf(momentKeyOf(routine!));
            return m.timed && m.key != kMomentMiracle ? 'routine · ${m.label.toLowerCase()}' : 'routine';
          }(),
      };

  /// Ce qui lui arrive, en une ligne.
  String get after => switch (kind) {
        PassageKind.created => 'devient une routine de ${step.minutes} min, chaque jour',
        PassageKind.shared => 'garde ses moments, + une part au Miracle Morning',
        PassageKind.moved => 'passe au moment Miracle Morning',
      };
}

/// Le passage, étape par étape, dans l'ordre réglé. Une routine citée deux fois ne compte qu'une fois ; une
/// étape dont la routine n'existe plus est une étape libre.
List<PassageLine> miraclePassage(MiracleMorning mm, List<Activity> activities) {
  final byId = {for (final a in activities) if (!a.deleted && a.isHabit) a.id: a};
  final seen = <String>{};
  final out = <PassageLine>[];
  for (final s in mm.steps) {
    final a = s.routineId == null ? null : byId[s.routineId];
    if (a == null) {
      out.add(PassageLine(s, PassageKind.created));
    } else if (seen.add(a.id)) {
      final keys = splitMomentsOf(a);
      out.add(PassageLine(s, keys.isNotEmpty && !keys.contains(kMomentMiracle) && (a.habitTarget ?? 1) >= 2 ? PassageKind.shared : PassageKind.moved, a));
    }
  }
  return out;
}

/// Fin du moment Miracle Morning proposée au passage : le temps de toutes les étapes plus un quart d'heure,
/// arrondi à la demi-heure, une heure au moins.
int miracleEndFor(MiracleMorning mm, int dayStartMin) {
  final need = mm.totalMin + 15;
  final span = need <= 60 ? 60 : ((need + 29) ~/ 30) * 30;
  return dayStartMin + span;
}

/// Applique le passage : les routines changent sur place, les étapes libres gardées deviennent des routines
/// (renvoyées dans `created`, à ajouter). [dropped] = ids des étapes libres à ne pas garder ; [domainId] = le
/// domaine des routines créées. L'ordre des étapes devient l'ordre des routines du moment.
({List<Activity> changed, List<Activity> created}) applyMiraclePassage(List<PassageLine> lines, {Set<String> dropped = const {}, required String domainId}) {
  final changed = <Activity>[], created = <Activity>[];
  var order = 0;
  for (final l in lines) {
    switch (l.kind) {
      case PassageKind.created:
        if (dropped.contains(l.step.id)) continue;
        created.add(Activity(
          domainId: domainId,
          name: l.step.name,
          type: 'habit',
          habitFreq: HabitFreq.daily,
          habitTarget: 1,
          timeContext: kMomentMiracle,
          timerMin: l.step.minutes,
        )..routineOrder = order++);
      case PassageKind.moved:
        final a = l.routine!;
        if (splitMomentsOf(a).isEmpty) {
          a.timeContext = kMomentMiracle;
          a.splitMoments = [];
          a.momentShares = {};
        }
        // Une routine à faire une fois, sans durée : elle prend celle de l'étape.
        if ((a.habitTarget ?? 1) <= 1 && a.onceMin == null && l.step.minutes > 0) a.timerMin = l.step.minutes;
        a.routineOrder = order++;
        changed.add(a);
      case PassageKind.shared:
        final a = l.routine!;
        final old = splitMomentsOf(a);
        final parts = momentParts(a.habitTarget ?? 1, old, a.momentShares);
        // Une part au Miracle Morning, prise sur la plus grosse des autres.
        var from = 0;
        for (var i = 1; i < parts.length; i++) {
          if (parts[i] > parts[from]) from = i;
        }
        parts[from]--;
        a.splitMoments = [kMomentMiracle, ...old];
        a.momentShares = {kMomentMiracle: 1, for (var i = 0; i < old.length; i++) old[i]: parts[i]};
        a.timeContext = kMomentMiracle;
        a.routineOrder = order++;
        changed.add(a);
    }
  }
  return (changed: changed, created: created);
}
