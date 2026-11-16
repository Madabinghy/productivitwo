import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart' show kMomentMorning, momentKeyOf;

/// Miracle Morning (2026-11-16, maquette validée « Mon Miracle Morning ») : la matinée de la
/// personne, ses étapes dans son ordre. L'heure ne compte pas : on le fait quand on se lève.
/// Une étape peut porter une routine (elle prend son +1 quand l'étape est faite) et lancer le
/// chrono de l'activité liée de la routine. Stockage `data/meta.miracleMorning {steps: [...]}`.
/// Une matinée faite = une `ChainRun` `kind: "miracle"` du jour vécu.
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

/// Au départ : les routines du matin de la personne, rien d'imposé. Durée = le minuteur de la
/// routine, sinon 5 min.
MiracleMorning defaultMiracle(List<Activity> activities) {
  final morning = activities
      .where((a) => !a.deleted && a.isHabit && a.habitFreq == HabitFreq.daily && momentKeyOf(a) == kMomentMorning)
      .toList()
    ..sort((a, b) => (a.routineOrder ?? 999).compareTo(b.routineOrder ?? 999));
  return MiracleMorning([
    for (final a in morning) MiracleStep(id: 'r-${a.id}', name: a.name, routineId: a.id, minutes: (a.timerMin ?? 5).clamp(1, 120)),
  ]);
}

/// Les idées du classique S.A.V.E.R.S., proposées sans rien imposer.
const kMiracleIdeas = <(String, int, String)>[
  ('Silence', 5, 'méditer, respirer, prier'),
  ('Affirmations', 3, 'ce que tu veux être aujourd’hui'),
  ('Visualisation', 3, 'vois ta journée réussie'),
  ('Exercice', 10, 'bouger, même un peu'),
  ('Lecture', 10, 'quelques pages'),
  ('Écriture', 5, 'journal, gratitude'),
];

/// La matinée de ce jour vécu, si elle a été faite.
ChainRun? miracleDoneOn(List<ChainRun> runs, String ymd) =>
    runs.where((r) => r.kind == kMiracleKind && r.date == ymd).firstOrNull;

/// « Silence · Prière · Visualisation · +2 »
String miracleNames(MiracleMorning m, {int max = 3}) {
  final names = m.steps.map((s) => s.name).toList();
  return [...names.take(max), if (names.length > max) '+${names.length - max}'].join(' · ');
}
