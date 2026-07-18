part of '../models.dart';

// ─── ARTEFACTS STRUCTURÉS ─────────────────────────────────────────────────────
//
// Un artefact (plan d'entraînement, menu de la semaine) est une SOURCE DE
// BLOCS, pas un document à lire : ses `entries` datées sont instanciées par la
// proposition de planification avec leur provenance. Collection dédiée
// users/{uid}/artifacts/{id} (les documents HTML restent dans `documents` ;
// le domaine référence l'artefact via artifactIds).
// « Vivant, pas gravé » : ⟳ régénère LA SUITE depuis les faits — le passé
// n'est jamais réécrit (jamais de culpabilité rétroactive).

class ArtifactEntry {
  String? date; // "YYYY-MM-DD" (exclusif avec weekday)
  String? weekday; // "mon".."sun" — motif hebdo récurrent (menu)
  String time; // "HH:mm"
  String title;
  int durationMin;
  String? detail; // « squats · fentes · gainage — 3×10, tranquille »
  int? portions; // menu uniquement
  bool optional; // « optionnelle, hors vital »

  ArtifactEntry({
    this.date,
    this.weekday,
    required this.time,
    required this.title,
    this.durationMin = 30,
    this.detail,
    this.portions,
    this.optional = false,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'weekday': weekday,
        'time': time,
        'title': title,
        'durationMin': durationMin,
        'detail': detail,
        'portions': portions,
        'optional': optional,
      };

  static ArtifactEntry from(Map j) => ArtifactEntry(
        date: j['date'],
        weekday: j['weekday'],
        time: j['time'] ?? '09:00',
        title: j['title'] ?? '',
        durationMin: (j['durationMin'] as num?)?.toInt() ?? 30,
        detail: j['detail'],
        portions: (j['portions'] as num?)?.toInt(),
        optional: j['optional'] == true,
      );
}

class ShoppingItem {
  String label;
  String qty;
  // Coché en faisant les courses (@courses) — remis à zéro à la régénération
  // (la liste est réécrite par le serveur).
  bool checked;
  ShoppingItem({required this.label, this.qty = '', this.checked = false});

  Map<String, dynamic> toJson() =>
      {'label': label, 'qty': qty, 'checked': checked};

  static ShoppingItem from(Map j) => ShoppingItem(
      label: j['label'] ?? '',
      qty: j['qty']?.toString() ?? '',
      checked: j['checked'] == true);
}

class Artifact {
  String id;
  String kind; // "training_plan" | "weekly_menu"
  String domainId; // raccord au domaine — l'artefact cite son intention
  DateTime generatedAt;
  Map<String, dynamic> params; // les 3-4 paramètres confirmés au cadrage
  List<ArtifactEntry> entries;
  List<ShoppingItem> shoppingList; // menu uniquement — dérivée des repas
  List<String> offSlots; // « on ne touche pas » — contrainte dure (ex: fri_evening)
  // Fait tracké de la carte midi (15c) : date → "eaten" | "other".
  // « Autre chose » fait glisser le menu d'un jour, sans pénalité.
  Map<String, String> mealLog;
  bool deleted; // soft-delete comme partout

  Artifact({
    String? id,
    required this.kind,
    required this.domainId,
    DateTime? generatedAt,
    Map<String, dynamic>? params,
    List<ArtifactEntry>? entries,
    List<ShoppingItem>? shoppingList,
    List<String>? offSlots,
    Map<String, String>? mealLog,
    this.deleted = false,
  })  : id = id ?? _uuid.v4(),
        generatedAt = generatedAt ?? DateTime.now(),
        params = params ?? {},
        entries = entries ?? [],
        shoppingList = shoppingList ?? [],
        offSlots = offSlots ?? [],
        mealLog = mealLog ?? {};

  String get title => switch (kind) {
        'training_plan' => 'Plan de reprise',
        'weekly_menu' => 'Menu de la semaine',
        _ => 'Artefact',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'domainId': domainId,
        'generatedAt': generatedAt.toIso8601String(),
        'params': params,
        'entries': entries.map((e) => e.toJson()).toList(),
        'shoppingList': shoppingList.map((s) => s.toJson()).toList(),
        'offSlots': offSlots,
        'mealLog': mealLog,
        'deleted': deleted,
      };

  static Artifact from(Map j) => Artifact(
        id: j['id'],
        kind: j['kind'] ?? 'training_plan',
        domainId: j['domainId'] ?? '',
        generatedAt: _parseDate(j['generatedAt']),
        params: (j['params'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v)) ??
            {},
        entries: (j['entries'] as List?)
                ?.whereType<Map>()
                .map(ArtifactEntry.from)
                .toList() ??
            [],
        shoppingList: (j['shoppingList'] as List?)
                ?.whereType<Map>()
                .map(ShoppingItem.from)
                .toList() ??
            [],
        offSlots:
            (j['offSlots'] as List?)?.map((e) => e.toString()).toList() ?? [],
        mealLog: (j['mealLog'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            {},
        deleted: j['deleted'] == true,
      );
}

/// Semaine minimale (17c) : « la S2 se rejoue, pas la S3 » — les entrées
/// datées à partir de [fromDate] reculent de 7 jours (la semaine du plan se
/// REJOUE, jamais sautée). Le passé et le motif hebdo ne bougent pas.
/// Fonction pure, testable.
void recaleArtifactOneWeek(Artifact artifact, String fromDate) {
  for (final e in artifact.entries) {
    final d = e.date;
    if (d == null || d.compareTo(fromDate) < 0) continue;
    final parsed = DateTime.tryParse(d);
    if (parsed == null) continue;
    final shifted = parsed.add(const Duration(days: 7));
    e.date =
        '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}-${shifted.day.toString().padLeft(2, '0')}';
  }
}

/// « Autre chose aujourd'hui » : fait glisser le menu d'UN jour, sans pénalité
/// — les entrées datées à partir de [fromDate] reculent d'un jour ; le motif
/// hebdo (weekday) n'est pas touché (il se rejouera naturellement). Fonction
/// pure, testable.
void shiftMenuOneDay(Artifact menu, String fromDate) {
  for (final e in menu.entries) {
    final d = e.date;
    if (d == null || d.compareTo(fromDate) < 0) continue; // passé intouché
    final parsed = DateTime.tryParse(d);
    if (parsed == null) continue;
    final shifted = parsed.add(const Duration(days: 1));
    e.date =
        '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}-${shifted.day.toString().padLeft(2, '0')}';
  }
}
