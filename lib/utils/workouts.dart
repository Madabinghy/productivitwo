// Séances de muscu (2026-11-04, maquette validée « Séances de muscu », lot 1) — logique pure.
//
// Exercices et séances types vivent dans `data/meta.gym {exercises: {<id>: …}, templates: {<id>: …}}` ;
// chaque séance faite est un doc `users/{uid}/workouts/{id}` (une ligne par série). Rien de stocké ici n'est
// recalculé ailleurs : volume, records et comparaisons se lisent à la volée.

/// Avec poids (kg), au poids du corps (répétitions) ou en durée (secondes).
enum ExerciseKind { weight, bodyweight, duration }

ExerciseKind exerciseKindOf(Object? v) => switch (v) {
      'bodyweight' => ExerciseKind.bodyweight,
      'duration' => ExerciseKind.duration,
      _ => ExerciseKind.weight,
    };

const int kDefaultRestSec = 90;
const double kDefaultStepKg = 2.5;

/// Où se fait une séance type : à la maison ou à la salle (simple étiquette).
const String kPlaceHome = 'maison';
const String kPlaceGym = 'salle';

class Exercise {
  final String id;
  final String name;
  /// Machine ou matériel (« banc », « machine 7 », « chaise »), facultatif.
  final String? gear;
  final ExerciseKind kind;
  /// Repos retenu entre deux séries, en secondes.
  final int restSec;
  /// Pas du poids proposé (kg).
  final double stepKg;
  final bool deleted;
  const Exercise({
    required this.id,
    required this.name,
    this.gear,
    this.kind = ExerciseKind.weight,
    this.restSec = kDefaultRestSec,
    this.stepKg = kDefaultStepKg,
    this.deleted = false,
  });

  Exercise copyWith({String? name, String? gear, bool clearGear = false, ExerciseKind? kind, int? restSec, double? stepKg, bool? deleted}) =>
      Exercise(
        id: id,
        name: name ?? this.name,
        gear: clearGear ? null : (gear ?? this.gear),
        kind: kind ?? this.kind,
        restSec: restSec ?? this.restSec,
        stepKg: stepKg ?? this.stepKg,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (gear != null && gear!.isNotEmpty) 'gear': gear,
        'kind': kind.name,
        'restSec': restSec,
        if (stepKg != kDefaultStepKg) 'stepKg': stepKg,
        if (deleted) 'deleted': true,
      };

  static Exercise? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    return Exercise(
      id: id,
      name: name,
      gear: (raw['gear'] as String?)?.trim(),
      kind: exerciseKindOf(raw['kind']),
      restSec: (raw['restSec'] as num?)?.toInt() ?? kDefaultRestSec,
      stepKg: (raw['stepKg'] as num?)?.toDouble() ?? kDefaultStepKg,
      deleted: raw['deleted'] == true,
    );
  }
}

/// Une ligne de séance type : n séries de m répétitions (ou m secondes) à tel poids.
class TemplateItem {
  final String exerciseId;
  final int sets;
  /// Répétitions par série, ou secondes pour un exercice en durée ; null = « max ».
  final int? reps;
  final double? weightKg;
  const TemplateItem({required this.exerciseId, this.sets = 3, this.reps, this.weightKg});

  TemplateItem copyWith({int? sets, int? reps, bool clearReps = false, double? weightKg, bool clearWeight = false}) => TemplateItem(
        exerciseId: exerciseId,
        sets: sets ?? this.sets,
        reps: clearReps ? null : (reps ?? this.reps),
        weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
      );

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'sets': sets,
        if (reps != null) 'reps': reps,
        if (weightKg != null) 'weightKg': weightKg,
      };

  static TemplateItem? fromJson(Object? raw) {
    if (raw is! Map || raw['exerciseId'] is! String) return null;
    return TemplateItem(
      exerciseId: raw['exerciseId'] as String,
      sets: ((raw['sets'] as num?)?.toInt() ?? 3).clamp(1, 20),
      reps: (raw['reps'] as num?)?.toInt(),
      weightKg: (raw['weightKg'] as num?)?.toDouble(),
    );
  }
}

/// Une séance type (« Haut du corps · maison »), relancée telle quelle.
class WorkoutTemplate {
  final String id;
  final String name;
  /// `maison`, `salle` ou null.
  final String? place;
  final List<TemplateItem> items;
  final bool deleted;
  const WorkoutTemplate({required this.id, required this.name, this.place, this.items = const [], this.deleted = false});

  WorkoutTemplate copyWith({String? name, String? place, bool clearPlace = false, List<TemplateItem>? items, bool? deleted}) => WorkoutTemplate(
        id: id,
        name: name ?? this.name,
        place: clearPlace ? null : (place ?? this.place),
        items: items ?? this.items,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (place != null) 'place': place,
        'items': [for (final i in items) i.toJson()],
        if (deleted) 'deleted': true,
      };

  static WorkoutTemplate? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    return WorkoutTemplate(
      id: id,
      name: name,
      place: raw['place'] as String?,
      items: (raw['items'] as List? ?? const []).map(TemplateItem.fromJson).whereType<TemplateItem>().toList(),
      deleted: raw['deleted'] == true,
    );
  }
}

/// Exercices et séances types (`data/meta.gym`).
class Gym {
  final Map<String, Exercise> exercises;
  final Map<String, WorkoutTemplate> templates;
  const Gym({this.exercises = const {}, this.templates = const {}});

  Gym copyWith({Map<String, Exercise>? exercises, Map<String, WorkoutTemplate>? templates}) =>
      Gym(exercises: exercises ?? this.exercises, templates: templates ?? this.templates);

  List<Exercise> get liveExercises =>
      exercises.values.where((e) => !e.deleted).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  List<WorkoutTemplate> get liveTemplates =>
      templates.values.where((t) => !t.deleted).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Map<String, dynamic> toJson() => {
        'exercises': {for (final e in exercises.values) e.id: e.toJson()},
        'templates': {for (final t in templates.values) t.id: t.toJson()},
      };
}

Gym parseGym(Object? raw) {
  if (raw is! Map) return const Gym();
  final ex = raw['exercises'] is Map ? raw['exercises'] as Map : const {};
  final tp = raw['templates'] is Map ? raw['templates'] as Map : const {};
  return Gym(
    exercises: {
      for (final e in ex.entries)
        if (Exercise.fromJson('${e.key}', e.value) case final x?) x.id: x
    },
    templates: {
      for (final e in tp.entries)
        if (WorkoutTemplate.fromJson('${e.key}', e.value) case final x?) x.id: x
    },
  );
}

/// Une série faite.
class SetLog {
  final String exerciseId;
  /// Répétitions (poids ou poids du corps) ; 0 pour un exercice en durée.
  final int reps;
  final double? weightKg;
  /// Secondes tenues (exercice en durée).
  final int? seconds;
  /// Repos réellement pris AVANT cette série (secondes), null pour la première.
  final int? restSec;
  /// Fin de la série (ms epoch).
  final int at;
  const SetLog({required this.exerciseId, this.reps = 0, this.weightKg, this.seconds, this.restSec, required this.at});

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'reps': reps,
        if (weightKg != null) 'weightKg': weightKg,
        if (seconds != null) 'seconds': seconds,
        if (restSec != null) 'restSec': restSec,
        'at': at,
      };

  static SetLog? fromJson(Object? raw) {
    if (raw is! Map || raw['exerciseId'] is! String) return null;
    return SetLog(
      exerciseId: raw['exerciseId'] as String,
      reps: (raw['reps'] as num?)?.toInt() ?? 0,
      weightKg: (raw['weightKg'] as num?)?.toDouble(),
      seconds: (raw['seconds'] as num?)?.toInt(),
      restSec: (raw['restSec'] as num?)?.toInt(),
      at: (raw['at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Une séance faite (`users/{uid}/workouts/{id}`).
class Workout {
  final String id;
  final String? templateId;
  final String name;
  final String? place;
  /// Jour vécu de la séance (YYYY-MM-DD).
  final String ymd;
  final int startAt;
  final int? endAt;
  final List<SetLog> sets;
  /// Activité de sport sur laquelle le chrono a tourné.
  final String? activityId;
  final bool deleted;
  const Workout({
    required this.id,
    this.templateId,
    required this.name,
    this.place,
    required this.ymd,
    required this.startAt,
    this.endAt,
    this.sets = const [],
    this.activityId,
    this.deleted = false,
  });

  bool get finished => endAt != null;

  int get durationMin {
    final end = endAt ?? (sets.isEmpty ? startAt : sets.last.at);
    return ((end - startAt) / 60000).round().clamp(0, 24 * 60);
  }

  Workout copyWith({List<SetLog>? sets, int? endAt, bool? deleted, String? activityId}) => Workout(
        id: id,
        templateId: templateId,
        name: name,
        place: place,
        ymd: ymd,
        startAt: startAt,
        endAt: endAt ?? this.endAt,
        sets: sets ?? this.sets,
        activityId: activityId ?? this.activityId,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (templateId != null) 'templateId': templateId,
        'name': name,
        if (place != null) 'place': place,
        'ymd': ymd,
        'startAt': startAt,
        if (endAt != null) 'endAt': endAt,
        'sets': [for (final s in sets) s.toJson()],
        if (activityId != null) 'activityId': activityId,
        if (deleted) 'deleted': true,
      };

  static Workout? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['ymd'] is! String) return null;
    return Workout(
      id: raw['id'] as String,
      templateId: raw['templateId'] as String?,
      name: (raw['name'] as String?) ?? 'Séance',
      place: raw['place'] as String?,
      ymd: raw['ymd'] as String,
      startAt: (raw['startAt'] as num?)?.toInt() ?? 0,
      endAt: (raw['endAt'] as num?)?.toInt(),
      sets: (raw['sets'] as List? ?? const []).map(SetLog.fromJson).whereType<SetLog>().toList(),
      activityId: raw['activityId'] as String?,
      deleted: raw['deleted'] == true,
    );
  }
}

// ── Exercices ────────────────────────────────────────────────────────────────

/// Clé d'un nom d'exercice : minuscules, sans accents ni ponctuation.
String exerciseKey(String name) {
  const from = 'àâäáãéèêëíìîïóòôöõúùûüçñœæ';
  const to = 'aaaaaeeeeiiiiooooouuuucnoa';
  final b = StringBuffer();
  for (final r in name.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// L'exercice déjà connu sous ce nom (sans accents ni casse), sinon null — comme un mot de la liste de courses.
Exercise? exerciseByName(Gym gym, String name) {
  final k = exerciseKey(name);
  if (k.isEmpty) return null;
  for (final e in gym.exercises.values) {
    if (!e.deleted && exerciseKey(e.name) == k) return e;
  }
  return null;
}

// ── Historique ───────────────────────────────────────────────────────────────

List<Workout> liveWorkouts(Iterable<Workout> all) =>
    all.where((w) => !w.deleted && w.sets.isNotEmpty).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));

/// Les séries de cet exercice dans la dernière séance qui l'a vu, avant [beforeMs].
List<SetLog> lastSetsOf(String exerciseId, Iterable<Workout> workouts, {int? beforeMs}) {
  final list = liveWorkouts(workouts).reversed;
  for (final w in list) {
    if (beforeMs != null && w.startAt >= beforeMs) continue;
    final s = w.sets.where((x) => x.exerciseId == exerciseId).toList();
    if (s.isNotEmpty) return s;
  }
  return const [];
}

/// La dernière séance faite de cette séance type, avant [beforeMs].
Workout? lastWorkoutOf(String templateId, Iterable<Workout> workouts, {int? beforeMs}) {
  for (final w in liveWorkouts(workouts).reversed) {
    if (w.templateId != templateId) continue;
    if (beforeMs != null && w.startAt >= beforeMs) continue;
    return w;
  }
  return null;
}

/// Poids proposé pour la prochaine fois : toutes les séries prévues faites au poids d'avant → un pas de plus ;
/// sinon le même. Null hors exercice avec poids ou sans historique.
double? suggestedWeight(Exercise e, TemplateItem item, List<SetLog> last) {
  if (e.kind != ExerciseKind.weight) return null;
  final w = last.map((s) => s.weightKg).whereType<double>().fold<double?>(null, (m, x) => m == null || x > m ? x : m);
  if (w == null) return item.weightKg;
  final target = item.reps;
  final atW = last.where((s) => s.weightKg == w).toList();
  final allDone = target != null && atW.length >= item.sets && atW.every((s) => s.reps >= target);
  return allDone ? w + e.stepKg : w;
}

/// Ce qu'on propose pour la série [index] (0…) : poids et répétitions repris de la même série la fois d'avant, sinon de la séance type.
SetLog plannedSet(Exercise e, TemplateItem item, List<SetLog> last, int index, {int at = 0}) {
  final prev = index < last.length ? last[index] : (last.isEmpty ? null : last.last);
  final w = e.kind == ExerciseKind.weight ? (suggestedWeight(e, item, last) ?? prev?.weightKg ?? item.weightKg) : null;
  return SetLog(
    exerciseId: e.id,
    reps: e.kind == ExerciseKind.duration ? 0 : (item.reps ?? prev?.reps ?? 10),
    weightKg: w,
    seconds: e.kind == ExerciseKind.duration ? (item.reps ?? prev?.seconds ?? 30) : null,
    at: at,
  );
}

// ── Mesures ──────────────────────────────────────────────────────────────────

/// Volume = Σ répétitions × poids (kg) ; seules les séries avec poids comptent.
double volumeOf(Iterable<SetLog> sets) => sets.fold(0.0, (s, x) => s + (x.weightKg == null ? 0 : x.reps * x.weightKg!));

int repsOf(Iterable<SetLog> sets) => sets.fold(0, (s, x) => s + x.reps);

/// Repos moyen réellement pris (secondes), null sans repos mesuré.
int? avgRestSec(Iterable<SetLog> sets) {
  final r = sets.map((s) => s.restSec).whereType<int>().where((x) => x > 0).toList();
  if (r.isEmpty) return null;
  return (r.reduce((a, b) => a + b) / r.length).round();
}

/// Meilleure série d'un exercice : poids le plus lourd (puis répétitions), sinon répétitions, sinon secondes.
int _cmpSet(SetLog a, SetLog b) {
  final w = (a.weightKg ?? 0).compareTo(b.weightKg ?? 0);
  if (w != 0) return w;
  final r = a.reps.compareTo(b.reps);
  if (r != 0) return r;
  return (a.seconds ?? 0).compareTo(b.seconds ?? 0);
}

SetLog? bestSet(Iterable<SetLog> sets) => sets.isEmpty ? null : sets.reduce((a, b) => _cmpSet(a, b) >= 0 ? a : b);

/// La série bat-elle tout ce qui a été fait avant sur cet exercice ? (Première fois = pas un record.)
bool isRecord(SetLog s, Iterable<Workout> history, {required int beforeMs}) {
  SetLog? best;
  for (final w in liveWorkouts(history)) {
    if (w.startAt >= beforeMs) continue;
    for (final x in w.sets) {
      if (x.exerciseId != s.exerciseId) continue;
      if (best == null || _cmpSet(x, best) > 0) best = x;
    }
  }
  return best != null && _cmpSet(s, best) > 0;
}

enum DeltaKind { better, same, worse, first }

/// Écart d'un exercice avec la fois d'avant, en une étiquette courte (« +2,5 kg », « +2 reps », « pareil », « −10 s »).
class ExerciseDelta {
  final DeltaKind kind;
  final String label;
  const ExerciseDelta(this.kind, this.label);
}

ExerciseDelta compareExercise(List<SetLog> now, List<SetLog> before) {
  if (before.isEmpty) return const ExerciseDelta(DeltaKind.first, 'première fois');
  final wNow = now.map((s) => s.weightKg ?? 0).fold<double>(0, (m, x) => x > m ? x : m);
  final wBefore = before.map((s) => s.weightKg ?? 0).fold<double>(0, (m, x) => x > m ? x : m);
  if (wNow != wBefore) {
    final d = wNow - wBefore;
    return ExerciseDelta(d > 0 ? DeltaKind.better : DeltaKind.worse, '${d > 0 ? '+' : '−'}${kgLabel(d.abs())} kg');
  }
  final sNow = now.fold<int>(0, (a, x) => a + (x.seconds ?? 0));
  final sBefore = before.fold<int>(0, (a, x) => a + (x.seconds ?? 0));
  if (sNow != sBefore && (sNow > 0 || sBefore > 0)) {
    final d = sNow - sBefore;
    return ExerciseDelta(d > 0 ? DeltaKind.better : DeltaKind.worse, '${d > 0 ? '+' : '−'}${d.abs()} s');
  }
  final rNow = repsOf(now), rBefore = repsOf(before);
  if (rNow != rBefore) {
    final d = rNow - rBefore;
    return ExerciseDelta(d > 0 ? DeltaKind.better : DeltaKind.worse, '${d > 0 ? '+' : '−'}${d.abs()} rep${d.abs() > 1 ? 's' : ''}');
  }
  return const ExerciseDelta(DeltaKind.same, 'pareil');
}

/// Bilan d'une séance face à la même séance type la fois d'avant.
class WorkoutSummary {
  final double volume;
  final int reps;
  final int sets;
  final int durationMin;
  final int? avgRest;
  final int records;
  /// Écart de volume en % avec la fois d'avant (null sans fois d'avant ou sans poids).
  final int? volumeDeltaPct;
  final Map<String, ExerciseDelta> byExercise;
  const WorkoutSummary({
    required this.volume,
    required this.reps,
    required this.sets,
    required this.durationMin,
    this.avgRest,
    required this.records,
    this.volumeDeltaPct,
    this.byExercise = const {},
  });
}

WorkoutSummary summarize(Workout w, Iterable<Workout> history) {
  final prev = w.templateId == null ? null : lastWorkoutOf(w.templateId!, history, beforeMs: w.startAt);
  final ids = <String>[for (final s in w.sets) s.exerciseId].toSet();
  final records = ids.where((id) {
    final best = bestSet(w.sets.where((s) => s.exerciseId == id));
    return best != null && isRecord(best, history, beforeMs: w.startAt);
  }).length;
  final vol = volumeOf(w.sets);
  final prevVol = prev == null ? 0.0 : volumeOf(prev.sets);
  return WorkoutSummary(
    volume: vol,
    reps: repsOf(w.sets),
    sets: w.sets.length,
    durationMin: w.durationMin,
    avgRest: avgRestSec(w.sets),
    records: records,
    volumeDeltaPct: prevVol > 0 && vol > 0 ? ((vol - prevVol) / prevVol * 100).round() : null,
    byExercise: {
      for (final id in ids)
        id: compareExercise(
          w.sets.where((s) => s.exerciseId == id).toList(),
          lastSetsOf(id, history, beforeMs: w.startAt),
        ),
    },
  );
}

// ── Semaine, mois ────────────────────────────────────────────────────────────

/// Séances faites dont le jour vécu tombe dans [from, to] (YYYY-MM-DD inclus).
List<Workout> workoutsBetween(Iterable<Workout> all, String from, String to) =>
    liveWorkouts(all).where((w) => w.ymd.compareTo(from) >= 0 && w.ymd.compareTo(to) <= 0).toList();

/// Nombre de séances par séance type (clé = nom de la séance), du plus fréquent au moins fréquent.
List<MapEntry<String, int>> countByName(Iterable<Workout> list) {
  final m = <String, int>{};
  for (final w in list) {
    m[w.name] = (m[w.name] ?? 0) + 1;
  }
  return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

// ── Libellés ─────────────────────────────────────────────────────────────────

/// « 42,5 », « 40 ».
String kgLabel(double kg) {
  final s = kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);
  return s.replaceAll('.', ',');
}

/// « 45 s », « 1 min », « 1 min 30 », « 2 min ».
String restLabel(int sec) {
  if (sec < 60) return '$sec s';
  final m = sec ~/ 60, s = sec % 60;
  return s == 0 ? '$m min' : '$m min ${s.toString().padLeft(2, '0')}';
}

/// « 10 × 42,5 kg », « 22 », « 45 s ».
String setLabel(SetLog s) {
  if (s.seconds != null && s.seconds! > 0 && s.reps == 0) return '${s.seconds} s';
  if (s.weightKg != null) return '${s.reps} × ${kgLabel(s.weightKg!)} kg';
  return '${s.reps}';
}

/// « 4 × 10 à 42,5 kg · repos 1 min 30 », « 3 × max · poids du corps », « 3 × 45 s ».
String itemLabel(Exercise e, TemplateItem i) {
  final rest = 'repos ${restLabel(e.restSec)}';
  return switch (e.kind) {
    ExerciseKind.weight => '${i.sets} × ${i.reps ?? 'max'}${i.weightKg == null ? '' : ' à ${kgLabel(i.weightKg!)} kg'} · $rest',
    ExerciseKind.bodyweight => '${i.sets} × ${i.reps ?? 'max'} · poids du corps · $rest',
    ExerciseKind.duration => '${i.sets} × ${i.reps ?? 30} s · $rest',
  };
}
