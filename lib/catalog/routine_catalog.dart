import 'package:productivitwo_v1/models.dart';

/// Catalogue de routines (maquette validée 2026-11-01 « Catalogue de
/// routines ») : composé par l'administrateur, lu par tous. Chaque routine a
/// sa carte illustrée (un SVG 100 × 100 et une couleur de fond) et ses
/// réglages de départ ; « Activer » la crée chez la personne avec
/// `Activity.catalogId`. Source : la collection racine `routine_catalog`
/// (lecture seule côté client), sinon le premier lot ci-dessous, composé à
/// partir des routines de l'administrateur. Logique pure.

class CatalogRoutine {
  final String id;
  final String name;
  final String text;
  /// Rubrique du catalogue (Santé, Sport, Esprit, Foi, Maison, Finances, Travail).
  final String rubric;
  final HabitFreq freq;
  final int target;
  final String? unit;
  final int? timerMin;
  /// Moment (clé de `kTimeContexts` : morning / midday / afternoon / evening / allday…).
  final String? timeContext;
  /// Routine répartie : deux moments ou plus.
  final List<String> splitMoments;
  /// Fond de l'illustration (ARGB).
  final int bg;
  /// Le dessin, SVG 100 × 100.
  final String svg;
  final int order;
  const CatalogRoutine({
    required this.id,
    required this.name,
    required this.text,
    required this.rubric,
    this.freq = HabitFreq.daily,
    this.target = 1,
    this.unit,
    this.timerMin,
    this.timeContext,
    this.splitMoments = const [],
    required this.bg,
    required this.svg,
    this.order = 0,
  });

  /// « 1 fois / jour », « 20 / jour », « 3 / semaine ».
  String get cadence {
    final per = switch (freq) { HabitFreq.daily => 'jour', HabitFreq.weekly => 'semaine', HabitFreq.monthly => 'mois' };
    if (target == 1) return '1 fois / $per';
    return '$target${unit == null ? '' : ' $unit'} / $per';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'text': text,
        'rubric': rubric,
        'freq': freq.index,
        'target': target,
        if (unit != null) 'unit': unit,
        if (timerMin != null) 'timerMin': timerMin,
        if (timeContext != null) 'timeContext': timeContext,
        if (splitMoments.isNotEmpty) 'splitMoments': splitMoments,
        'bg': bg,
        'svg': svg,
        'order': order,
      };

  static CatalogRoutine? from(Map j) {
    final id = j['id']?.toString();
    final name = j['name']?.toString();
    final svg = j['svg']?.toString();
    if (id == null || name == null || svg == null || j['published'] == false) return null;
    final f = (j['freq'] as num?)?.toInt() ?? 0;
    return CatalogRoutine(
      id: id,
      name: name,
      text: j['text']?.toString() ?? '',
      rubric: j['rubric']?.toString() ?? 'Autres',
      freq: HabitFreq.values[f.clamp(0, HabitFreq.values.length - 1)],
      target: (j['target'] as num?)?.toInt() ?? 1,
      unit: j['unit']?.toString(),
      timerMin: (j['timerMin'] as num?)?.toInt(),
      timeContext: j['timeContext']?.toString(),
      splitMoments: (j['splitMoments'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      bg: (j['bg'] as num?)?.toInt() ?? 0xFF1F4A5C,
      svg: svg,
      order: (j['order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Ordre des rubriques à l'écran.
const kCatalogRubrics = ['Santé', 'Sport', 'Esprit', 'Foi', 'Maison', 'Finances', 'Travail'];

const _health = 0xFF1F3F5C, _sport = 0xFF5A2E1F, _mind = 0xFF5C4A1D, _faith = 0xFF3D3366, _home = 0xFF2B4A3F, _money = 0xFF4A3F12, _work = 0xFF4A1F3A;

String _svg(String body) => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">$body</svg>';

/// Le premier lot (2026-11-01) : les routines de l'administrateur.
final kRoutineCatalogSeed = <CatalogRoutine>[
  CatalogRoutine(
    id: 'boire-eau', order: 1, name: 'Boire de l’eau', rubric: 'Santé', target: 6, unit: 'verres', bg: _health,
    splitMoments: const ['morning', 'midday', 'afternoon', 'evening'],
    text: 'Six verres répartis dans la journée : un au réveil, un à chaque repas, le reste entre deux. La fatigue de l’après-midi vient souvent de là.',
    svg: _svg('<path d="M30 22h40l-6 62H36z" fill="none" stroke="#9FD8FF" stroke-width="5" stroke-linejoin="round"/><path d="M33 47h34l-4 35H37z" fill="#7FD3FF" opacity=".85"/><circle cx="45" cy="60" r="3" fill="#DFF3FF"/><circle cx="56" cy="70" r="2.2" fill="#DFF3FF"/><path d="M50 6c4 6 6.5 9 6.5 12a6.5 6.5 0 0 1-13 0c0-3 2.5-6 6.5-12z" fill="#9FD8FF"/>'),
  ),
  CatalogRoutine(
    id: 'hygiene-matin', order: 2, name: 'Hygiène du matin', rubric: 'Santé', timeContext: 'morning', bg: _health,
    text: 'Douche, dents, visage : la même suite chaque matin, sans y penser. Le premier geste qui lance la journée.',
    svg: _svg('<circle cx="70" cy="26" r="10" fill="#FFD98A"/><path d="M70 8v5M70 39v5M52 26h5M83 26h5M57 13l3.5 3.5M80 36l3.5 3.5M57 39l3.5-3.5M80 16l3.5-3.5" stroke="#FFD98A" stroke-width="3" stroke-linecap="round"/><path d="M20 84 52 52" stroke="#9FD8FF" stroke-width="7" stroke-linecap="round"/><rect x="48" y="38" width="12" height="20" rx="3" transform="rotate(45 54 48)" fill="#DFF3FF"/><path d="M50 45l9 9M47 48l9 9" stroke="#7FD3FF" stroke-width="2.5"/>'),
  ),
  CatalogRoutine(
    id: 'hygiene-soir', order: 3, name: 'Hygiène du soir', rubric: 'Santé', timeContext: 'evening', bg: _health,
    text: 'Dents, visage, préparer le lendemain. Le signal pour le corps que la journée se ferme.',
    svg: _svg('<path d="M74 12a17 17 0 1 0 12 28 14 14 0 0 1-12-28z" fill="#C6C9FF"/><path d="M20 84 52 52" stroke="#9FD8FF" stroke-width="7" stroke-linecap="round"/><rect x="48" y="38" width="12" height="20" rx="3" transform="rotate(45 54 48)" fill="#DFF3FF"/><path d="M50 45l9 9M47 48l9 9" stroke="#7FD3FF" stroke-width="2.5"/>'),
  ),
  CatalogRoutine(
    id: 'cafe', order: 4, name: 'Café', rubric: 'Santé', timeContext: 'morning', bg: _health,
    text: 'Le café du matin, posé, assis : cinq minutes pour soi avant de commencer.',
    svg: _svg('<path d="M24 44h42v18a18 18 0 0 1-18 18h-6a18 18 0 0 1-18-18z" fill="#D9A06A"/><path d="M66 50h6a8 8 0 0 1 0 16h-7" fill="none" stroke="#D9A06A" stroke-width="5"/><path d="M18 86h56" stroke="#8A5226" stroke-width="5" stroke-linecap="round"/><path d="M36 36c-4-6 4-8 0-14M48 36c-4-6 4-8 0-14" stroke="#F0C08A" stroke-width="3.5" stroke-linecap="round" fill="none"/>'),
  ),
  CatalogRoutine(
    id: 'repas-equilibre', order: 5, name: 'Repas équilibré', rubric: 'Santé', target: 2, bg: _health,
    splitMoments: const ['midday', 'evening'],
    text: 'Midi et soir : des légumes, une protéine, un féculent. Pas de régime, une assiette pensée.',
    svg: _svg('<circle cx="50" cy="54" r="30" fill="none" stroke="#9FF0C1" stroke-width="5"/><circle cx="50" cy="54" r="20" fill="#2B5A46"/><path d="M42 50c4-10 14-12 18-4-6 0-12 2-18 4z" fill="#9FF0C1"/><circle cx="56" cy="60" r="5" fill="#FFB38A"/><path d="M12 30v20M8 30v10a4 4 0 0 0 8 0V30M12 50v32M88 30c-6 4-6 16 0 20v32" stroke="#9FF0C1" stroke-width="3.5" stroke-linecap="round" fill="none"/>'),
  ),
  CatalogRoutine(
    id: 'cuisiner', order: 6, name: 'Cuisiner', rubric: 'Santé', timeContext: 'evening', bg: _health,
    text: 'Préparer un vrai repas, même simple. Cuisiner deux portions = le midi de demain déjà prêt.',
    svg: _svg('<path d="M20 50h52v12a14 14 0 0 1-14 14H34a14 14 0 0 1-14-14z" fill="#FFB38A"/><path d="M72 54h16" stroke="#FFB38A" stroke-width="6" stroke-linecap="round"/><path d="M16 50h60" stroke="#8A5226" stroke-width="4" stroke-linecap="round"/><path d="M34 40c-4-6 4-8 0-14M46 40c-4-6 4-8 0-14M58 40c-4-6 4-8 0-14" stroke="#FFD9B0" stroke-width="3.5" stroke-linecap="round" fill="none"/>'),
  ),
  CatalogRoutine(
    id: 'pompes', order: 10, name: 'Faire des pompes', rubric: 'Sport', target: 20, unit: 'pompes', bg: _sport,
    splitMoments: const ['morning', 'evening'],
    text: 'Vingt pompes, en deux fois : dix le matin, dix le soir. Genoux au sol au début, c’est très bien aussi.',
    svg: _svg('<circle cx="80" cy="36" r="7" fill="#FFB38A"/><path d="M72 41 30 54" stroke="#FFB38A" stroke-width="8" stroke-linecap="round"/><path d="M30 54 13 63" stroke="#FFB38A" stroke-width="7" stroke-linecap="round"/><path d="M64 44 62 70M45 50 47 70" stroke="#FFB38A" stroke-width="6" stroke-linecap="round"/><path d="M8 72h84" stroke="#8A5226" stroke-width="4" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'tractions', order: 11, name: 'Tractions', rubric: 'Sport', target: 10, unit: 'tractions', bg: _sport,
    splitMoments: const ['morning', 'evening'],
    text: 'Dix tractions, matin et soir par séries courtes. Une barre de porte suffit.',
    svg: _svg('<path d="M14 16h72" stroke="#8A5226" stroke-width="5" stroke-linecap="round"/><path d="M36 16v14M64 16v14" stroke="#FFB38A" stroke-width="6" stroke-linecap="round"/><path d="M36 30c4 8 24 8 28 0" stroke="#FFB38A" stroke-width="6" stroke-linecap="round" fill="none"/><circle cx="50" cy="30" r="8" fill="#FFB38A"/><path d="M50 40v26M50 66l-8 18M50 66l8 18" stroke="#FFB38A" stroke-width="7" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'footing', order: 12, name: 'Footing', rubric: 'Sport', freq: HabitFreq.weekly, target: 3, bg: _sport,
    text: 'Trois sorties par semaine, à ton rythme : on doit pouvoir parler en courant. La régularité compte plus que la distance.',
    svg: _svg('<circle cx="58" cy="16" r="7" fill="#9FF0C1"/><path d="M56 25 46 50l12 10 4 22M46 50 36 80M52 32l14 10M52 32 36 42" stroke="#9FF0C1" stroke-width="6" stroke-linecap="round" fill="none"/><path d="M10 88h80" stroke="#2B5A46" stroke-width="3"/><path d="M14 40h14M10 50h12M16 60h10" stroke="#9FF0C1" stroke-width="3" stroke-linecap="round" opacity=".6"/>'),
  ),
  CatalogRoutine(
    id: 'salle', order: 13, name: 'Aller à la salle', rubric: 'Sport', freq: HabitFreq.weekly, target: 2, bg: _sport,
    text: 'Deux séances de musculation par semaine. Le plus dur, c’est de franchir la porte : le reste suit.',
    svg: _svg('<rect x="10" y="38" width="10" height="24" rx="3" fill="#FFB38A"/><rect x="20" y="32" width="10" height="36" rx="3" fill="#FFB38A"/><rect x="70" y="32" width="10" height="36" rx="3" fill="#FFB38A"/><rect x="80" y="38" width="10" height="24" rx="3" fill="#FFB38A"/><path d="M30 50h40" stroke="#F0C08A" stroke-width="7" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'lecture', order: 20, name: 'Lecture', rubric: 'Esprit', timeContext: 'evening', timerMin: 20, bg: _mind,
    text: 'Vingt minutes de papier avant de dormir : ça calme la tête et ça remplace l’écran. Le minuteur sonne à la fin.',
    svg: _svg('<path d="M50 30C40 24 26 23 14 26v46c12-3 26-2 36 4 10-6 24-7 36-4V26c-12-3-26-2-36 4z" fill="none" stroke="#FFD98A" stroke-width="5" stroke-linejoin="round"/><path d="M50 30v46" stroke="#FFD98A" stroke-width="4"/><path d="M22 38c7-1 14 0 20 3M22 48c7-1 14 0 20 3M22 58c7-1 14 0 20 3M58 41c6-3 13-4 20-3M58 51c6-3 13-4 20-3M58 61c6-3 13-4 20-3" stroke="#FFD98A" stroke-width="3" stroke-linecap="round" opacity=".7"/>'),
  ),
  CatalogRoutine(
    id: 'motivation', order: 21, name: 'Motivation', rubric: 'Esprit', timeContext: 'morning', bg: _mind,
    text: 'Une vidéo, un texte, une phrase qui te remet dans l’axe. Cinq minutes pour rallumer le pourquoi.',
    svg: _svg('<path d="M10 84 40 34l14 22 10-14 26 42z" fill="#8A6E2A"/><path d="M40 34l7 11-7 4-7-4z" fill="#FFF3C4"/><path d="M64 42v-30" stroke="#FFD98A" stroke-width="4" stroke-linecap="round"/><path d="M64 12h18l-5 6 5 6H64z" fill="#FF8A5C"/>'),
  ),
  CatalogRoutine(
    id: 'planifier-journee', order: 22, name: 'Planifier ma journée', rubric: 'Esprit', timeContext: 'morning', bg: _mind,
    text: 'Deux minutes le matin (ou la veille) : ce qui compte aujourd’hui, et quand. Une journée posée se tient mieux.',
    svg: _svg('<rect x="18" y="20" width="64" height="64" rx="8" fill="none" stroke="#FFD98A" stroke-width="5"/><path d="M18 36h64" stroke="#FFD98A" stroke-width="5"/><path d="M34 12v14M66 12v14" stroke="#FFD98A" stroke-width="5" stroke-linecap="round"/><path d="M30 52l5 5 9-10M30 70l5 5 9-10" stroke="#9FF0C1" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M52 52h18M52 70h18" stroke="#FFD98A" stroke-width="4" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'lire-bible', order: 30, name: 'Lire la Bible', rubric: 'Foi', timeContext: 'morning', bg: _faith,
    text: 'Une page par jour. Lire lentement, garder une phrase pour la journée.',
    svg: _svg('<rect x="24" y="14" width="52" height="72" rx="5" fill="#2C1D5C" stroke="#D3C6FF" stroke-width="4"/><path d="M30 14v72" stroke="#D3C6FF" stroke-width="3"/><path d="M53 30v34M43 42h20" stroke="#FFE7A0" stroke-width="5" stroke-linecap="round"/><path d="M66 86v8l-4-3-4 3v-8" fill="#FF8A8A"/>'),
  ),
  CatalogRoutine(
    id: 'louanges', order: 31, name: 'Louanges', rubric: 'Foi', bg: _faith,
    text: 'Un chant, un temps de louange. Commencer ou finir la journée par la gratitude.',
    svg: _svg('<path d="M38 70V24l36-8v46" fill="none" stroke="#D3C6FF" stroke-width="5" stroke-linejoin="round"/><ellipse cx="30" cy="70" rx="10" ry="8" fill="#D3C6FF"/><ellipse cx="66" cy="62" rx="10" ry="8" fill="#D3C6FF"/><path d="M38 34l36-8" stroke="#D3C6FF" stroke-width="5"/><path d="M84 30l4-4M86 40h6M84 50l4 4" stroke="#FFE7A0" stroke-width="3" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'faire-lit', order: 40, name: 'Faire mon lit', rubric: 'Maison', timeContext: 'morning', bg: _home,
    text: 'La première chose réussie de la journée, en une minute. Et le soir, un lit qui t’attend.',
    svg: _svg('<rect x="12" y="46" width="76" height="22" rx="4" fill="#9FF0C1"/><rect x="18" y="36" width="22" height="14" rx="5" fill="#E8F1EC"/><path d="M12 30v52M88 50v32" stroke="#5E8A72" stroke-width="5" stroke-linecap="round"/><path d="M44 56h40" stroke="#2B5A46" stroke-width="3" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'vaisselle', order: 41, name: 'Faire la vaisselle', rubric: 'Maison', timeContext: 'evening', bg: _home,
    text: 'Une cuisine propre avant d’aller dormir : le matin commence sans retard.',
    svg: _svg('<circle cx="46" cy="56" r="26" fill="#E8F1EC"/><circle cx="46" cy="56" r="16" fill="none" stroke="#9FD8FF" stroke-width="3"/><circle cx="74" cy="26" r="8" fill="none" stroke="#9FD8FF" stroke-width="3"/><circle cx="84" cy="44" r="5" fill="none" stroke="#9FD8FF" stroke-width="3"/><circle cx="64" cy="14" r="4" fill="none" stroke="#9FD8FF" stroke-width="2.5"/>'),
  ),
  CatalogRoutine(
    id: 'lessive', order: 42, name: 'Faire la lessive', rubric: 'Maison', freq: HabitFreq.weekly, target: 3, bg: _home,
    text: 'Trois machines par semaine, étendues dans la foulée. Le linge ne s’entasse plus.',
    svg: _svg('<rect x="20" y="12" width="60" height="78" rx="8" fill="none" stroke="#9FD8FF" stroke-width="5"/><path d="M20 28h60" stroke="#9FD8FF" stroke-width="4"/><circle cx="30" cy="20" r="3" fill="#9FD8FF"/><circle cx="50" cy="58" r="20" fill="#1F3F5C" stroke="#9FD8FF" stroke-width="4"/><path d="M36 62c6-6 10 6 16 0s10 6 14 0" stroke="#7FD3FF" stroke-width="3.5" fill="none" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'aspirateur', order: 43, name: 'Passer l’aspirateur', rubric: 'Maison', freq: HabitFreq.weekly, target: 2, bg: _home,
    text: 'Deux passages par semaine, une pièce après l’autre. Quinze minutes suffisent.',
    svg: _svg('<path d="M62 10c10 0 14 8 10 16L54 70" stroke="#D3C6FF" stroke-width="5" stroke-linecap="round" fill="none"/><path d="M30 66h34a8 8 0 0 1 8 8v6H22v-6a8 8 0 0 1 8-8z" fill="#D3C6FF"/><circle cx="32" cy="84" r="5" fill="#5A3FA0"/><circle cx="62" cy="84" r="5" fill="#5A3FA0"/><path d="M10 88h8M8 80h6" stroke="#D3C6FF" stroke-width="3" stroke-linecap="round" opacity=".6"/>'),
  ),
  CatalogRoutine(
    id: 'ranger', order: 44, name: 'Ranger', rubric: 'Maison', bg: _home,
    text: 'Dix minutes par jour, chaque chose à sa place. Pas de grand ménage, juste remettre en ordre.',
    svg: _svg('<path d="M16 40h68v42H16z" fill="#8A6E2A"/><path d="M16 40 26 24h48l10 16" fill="#C9A44A"/><path d="M40 52h20" stroke="#FFE7A0" stroke-width="5" stroke-linecap="round"/><path d="M50 22V8M44 14l6-6 6 6" stroke="#FFD98A" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" fill="none"/>'),
  ),
  CatalogRoutine(
    id: 'laver-voiture', order: 45, name: 'Laver la voiture', rubric: 'Maison', freq: HabitFreq.monthly, target: 1, bg: _home,
    text: 'Une fois par mois : l’extérieur au jet, l’intérieur à l’aspirateur.',
    svg: _svg('<path d="M14 66V54l10-16h52l10 16v12z" fill="#7FD3FF"/><path d="M28 40h44l7 12H21z" fill="#1F3F5C"/><circle cx="30" cy="68" r="8" fill="#13201B" stroke="#DFF3FF" stroke-width="3"/><circle cx="70" cy="68" r="8" fill="#13201B" stroke="#DFF3FF" stroke-width="3"/><path d="M30 10c3 5 5 7 5 9a5 5 0 0 1-10 0c0-2 2-4 5-9zM52 14c3 5 5 7 5 9a5 5 0 0 1-10 0c0-2 2-4 5-9zM72 8c3 5 5 7 5 9a5 5 0 0 1-10 0c0-2 2-4 5-9z" fill="#9FD8FF"/>'),
  ),
  CatalogRoutine(
    id: 'budget', order: 50, name: 'Suivre mon budget', rubric: 'Finances', timeContext: 'evening', bg: _money,
    text: 'Chaque soir, noter les dépenses du jour. Deux minutes, et plus aucune surprise en fin de mois.',
    svg: _svg('<ellipse cx="50" cy="76" rx="26" ry="8" fill="#B8862B"/><rect x="24" y="62" width="52" height="14" fill="#B8862B"/><ellipse cx="50" cy="62" rx="26" ry="8" fill="#FFD36A"/><ellipse cx="50" cy="50" rx="26" ry="8" fill="#B8862B"/><rect x="24" y="36" width="52" height="14" fill="#B8862B"/><ellipse cx="50" cy="36" rx="26" ry="8" fill="#FFE7A0"/><path d="M50 30v12M45 34h7a3 3 0 0 1 0 6h-4a3 3 0 0 0 0 6h7" stroke="#8A6520" stroke-width="2.5" fill="none" stroke-linecap="round"/>'),
  ),
  CatalogRoutine(
    id: 'creer-contenu', order: 60, name: 'Créer du contenu', rubric: 'Travail', bg: _work,
    text: 'Un post, une vidéo, un brouillon : créer un peu chaque jour plutôt que beaucoup une fois.',
    svg: _svg('<rect x="12" y="30" width="56" height="42" rx="8" fill="none" stroke="#FF8A8A" stroke-width="5"/><path d="M68 44l20-12v36L68 56z" fill="#FF8A8A"/><circle cx="40" cy="51" r="11" fill="none" stroke="#FFB3AB" stroke-width="4"/><circle cx="40" cy="51" r="4" fill="#FFB3AB"/><circle cx="22" cy="38" r="3" fill="#FF6B5E"/>'),
  ),
];

/// Le catalogue servi : la collection serveur si elle a des routines, sinon
/// le premier lot ; trié par rubrique puis par ordre.
List<CatalogRoutine> catalogOrSeed(List<CatalogRoutine> remote) {
  final list = remote.isEmpty ? [...kRoutineCatalogSeed] : [...remote];
  int rub(String r) {
    final i = kCatalogRubrics.indexOf(r);
    return i < 0 ? 99 : i;
  }

  list.sort((a, b) {
    final c = rub(a.rubric).compareTo(rub(b.rubric));
    return c != 0 ? c : a.order.compareTo(b.order);
  });
  return list;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[’\']'), ' ')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâ]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùû]'), 'u')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// La routine de la personne qui correspond à une routine du catalogue :
/// celle qui porte son `catalogId`, sinon (proposition à lier) une routine
/// active du même nom.
({Activity? linked, Activity? sameName}) catalogMatch(CatalogRoutine c, List<Activity> activities) {
  final routines = activities.where((a) => !a.deleted && a.isHabit).toList();
  final linked = routines.where((a) => a.catalogId == c.id).firstOrNull;
  if (linked != null) return (linked: linked, sameName: null);
  final n = _norm(c.name);
  final same = routines.where((a) => a.catalogId == null && (_norm(a.name) == n || n.contains(_norm(a.name)) && _norm(a.name).length >= 5)).firstOrNull;
  return (linked: null, sameName: same);
}

/// Le domaine proposé à l'activation : celui dont le nom rappelle la
/// rubrique, sinon le premier.
String? domainForRubric(String rubric, List<Domain> domains) {
  const hints = {
    'Santé': ['santé', 'sante', 'bien-être', 'hygiène'],
    'Sport': ['sport', 'muscu', 'fitness', 'course'],
    'Esprit': ['mindset', 'esprit', 'développement', 'mental', 'lecture'],
    'Foi': ['spiritualité', 'foi', 'église', 'prière'],
    'Maison': ['intendance', 'maison', 'foyer', 'ménage'],
    'Finances': ['finance', 'budget', 'argent'],
    'Travail': ['business', 'travail', 'pro', 'carrière'],
  };
  final keys = hints[rubric] ?? const <String>[];
  for (final d in domains) {
    final n = d.name.toLowerCase();
    if (keys.any(n.contains)) return d.id;
  }
  return domains.firstOrNull?.id;
}

/// La routine créée par « Activer ».
Activity activityFromCatalog(CatalogRoutine c, String domainId) => Activity(
      domainId: domainId,
      name: c.name,
      type: 'habit',
      habitFreq: c.freq,
      habitTarget: c.target,
      unit: c.unit,
      timerMin: c.timerMin,
      timeContext: c.splitMoments.isNotEmpty ? c.splitMoments.first : c.timeContext,
      splitMoments: c.splitMoments.length >= 2 ? [...c.splitMoments] : null,
      catalogId: c.id,
    );

/// « Matin », « midi et soir »…
String momentLabel(CatalogRoutine c) {
  const names = {'morning': 'matin', 'midday': 'midi', 'afternoon': 'après-midi', 'evening': 'soir', 'allday': 'toute la journée', 'day': 'journée'};
  if (c.splitMoments.length >= 2) {
    final l = [for (final m in c.splitMoments) names[m] ?? m];
    return l.length == 2 ? '${l[0]} et ${l[1]}' : '${l.sublist(0, l.length - 1).join(', ')} et ${l.last}';
  }
  return c.timeContext == null ? 'quand tu veux' : (names[c.timeContext] ?? c.timeContext!);
}
