import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

// ─── Clé localStorage pour le web ───────────────────────────────────────────
const _kWebKey = 'productivitwo_data';

class FileStore {
  static const _fileName = 'productivitwo.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> wipe() async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      await prefs.remove(_kWebKey);
    } else {
      final f = await _file();
      if (await f.exists()) await f.delete();
    }
    await prefs.clear();
  }

void _migrateLinkedActivities(AppState st) {
  if (st.linkedActivitiesMigratedOnce) return;

  Domain? santeDomain;
  for (final d in st.domains) {
    if (d.name == 'Santé' || d.name == 'Sante') {
      santeDomain = d;
      break;
    }
  }
  if (santeDomain == null) return;

  // Trouve ou crée l'activité "Soin" dans Santé
  Activity? soinAct;
  for (final a in st.activities) {
    if (a.domainId == santeDomain.id && a.name == 'Soins' && a.type == 'time') {
      soinAct = a;
      break;
    }
  }

  if (soinAct == null) {
    soinAct = Activity(domainId: santeDomain.id, name: 'Soins', type: 'time', goalMin: 1);
    st.activities.add(soinAct);
  }

  // Lie Hygiène du matin et Hygiène du soir à Soin si pas encore fait
  for (int i = 0; i < st.activities.length; i++) {
    final a = st.activities[i];
    if (!a.isHabit) continue;
    if (a.name != 'Hygiène du matin' && a.name != 'Hygiène du soir') continue;
    final linked = (a.linkedActivityId ?? '').trim();
    if (linked.isNotEmpty) continue;
    st.activities[i] = a.copyWith(linkedActivityId: soinAct.id);
  }

  st.linkedActivitiesMigratedOnce = true;
}

void _migrateVoitureActivity(AppState st) {
  if (st.voitureMigratedOnce) return;

  Domain? environnementDomain;
  for (final d in st.domains) {
    if (d.name == 'Environnement') {
      environnementDomain = d;
      break;
    }
  }
  if (environnementDomain == null) return;

  // Trouve ou crée l'activité "Voiture"
  Activity? voitureAct;
  for (final a in st.activities) {
    if (a.domainId == environnementDomain.id && a.name == 'Voiture' && a.type == 'time') {
      voitureAct = a;
      break;
    }
  }
  if (voitureAct == null) {
    voitureAct = Activity(domainId: environnementDomain.id, name: 'Voiture', type: 'time', goalMin: 1);
    st.activities.add(voitureAct);
  }

  // Lie "Gérer la voiture" à l'activité "Voiture"
  for (int i = 0; i < st.activities.length; i++) {
    final a = st.activities[i];
    if (!a.isHabit) continue;
    if (a.name != 'Gérer la voiture') continue;
    st.activities[i] = a.copyWith(linkedActivityId: voitureAct.id);
  }

  st.voitureMigratedOnce = true;
}


Future<AppState> loadOrInitCleaner() async {
  AppState? tryDecode(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      return AppState.decode(t);
    } catch (_) {
      return null;
    }
  }

  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWebKey);
    if (raw != null) {
      final st = tryDecode(raw);
      if (st != null) {
        await save(st);
        return st;
      }
    }
    final st = _seedMinimal();
    await save(st);
    return st;
  }

  final f = await _file();
  final bak = File('${f.path}.bak');

  if (await f.exists()) {
    final main = tryDecode(await f.readAsString());
    if (main != null) {
      _migrateLinkedActivities(main);
      _migrateVoitureActivity(main);
      await save(main);
      return main;
    }

    if (await bak.exists()) {
      final b = tryDecode(await bak.readAsString());
      if (b != null) {
        _migrateLinkedActivities(b);
        _migrateVoitureActivity(b);
        await save(b);
        return b;
      }
    }

    final st = _seedMinimal();
    await save(st);
    return st;
  }

  final st = _seedMinimal();
  await save(st);
  return st;
}

  Future<AppState> loadOrInit() async {
    AppState? tryDecode(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      try {
        return AppState.decode(t);
      } catch (_) {
        return null;
      }
    }

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kWebKey);
      if (raw != null) {
        final st = tryDecode(raw);
        if (st != null) return st;
      }
      final st = AppState(
        domains: [],
        activities: [],
        sessions: [],
        habitProgress: [],
      );
      await save(st);
      return st;
    }

    final f = await _file();
    final bak = File('${f.path}.bak');

    if (await f.exists()) {
      final main = tryDecode(await f.readAsString());
      if (main != null) {
        _migrateLinkedActivities(main);
        _migrateVoitureActivity(main);
        await save(main);
        return main;
      }

      if (await bak.exists()) {
        final b = tryDecode(await bak.readAsString());
        if (b != null) {
          _migrateLinkedActivities(b);
          _migrateVoitureActivity(b);
          await save(b);
          return b;
        }
      }

      final st = _seedMinimal();
      await save(st);
      return st;
    }

    // Nouvelle installation → état vide pour l'onboarding
    final st = AppState(
      domains: [],
      activities: [],
      sessions: [],
      habitProgress: [],
    );
    await save(st);
    return st;
  }

  AppState _seedMinimal() {
    // ========== Domaines ==========
    final sante = Domain(name: 'Santé', autoGoal: true);
    final organisation = Domain(name: 'Organisation', autoGoal: true);
    final business = Domain(name: 'Business', autoGoal: true);
    final skills = Domain(name: 'Skills', autoGoal: true);
    final spiritualite = Domain(name: 'Spiritualité', autoGoal: true);
    final environnement = Domain(name: 'Environnement', autoGoal: true);
    final sport = Domain(name: 'Sport', autoGoal: true);

    // ========== Helpers ==========
    Activity timeAct(
      String domainId,
      String name, {
      ActivityRole role = ActivityRole.generic,
      int goalMin = 1,
    }) =>
        Activity(
          domainId: domainId,
          name: name,
          type: 'time',
          goalMin: goalMin,
          role: role,
        );

    /// ✅ “bonne” fonction habit : pas de 30j par défaut global.
    /// Tu choisis la fréquence au cas par cas dans le seed.
    Activity habit(
      String domainId,
      String name, {
      required HabitFreq freq,
      int target = 1,
      bool manualTarget = true,
      bool autoTune = false,
      String? linkedActivityId,
    }) =>
        Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          habitFreq: freq,
          habitTarget: target,
          manualTarget: manualTarget,
          autoTune: autoTune,
          linkedActivityId: linkedActivityId,
        );

    Activity weeklyCountHabit(
      String domainId,
      String name, {
      required int target,
      String? linkedActivityId,
    }) =>
        Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          habitFreq: HabitFreq.weekly,
          habitTarget: target,
          manualTarget: true,
          autoTune: false,
          linkedActivityId: linkedActivityId,
        );

    Activity dailyCountHabit(
      String domainId,
      String name, {
      required int target,
      String? linkedActivityId,
      int? iconCode,
    }) =>
        Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          habitFreq: HabitFreq.daily,
          habitTarget: target,
          manualTarget: true,
          autoTune: false,
          linkedActivityId: linkedActivityId,
          iconCode: iconCode,
        );

    // ========== Activités (time) ==========
    final soinAct           = timeAct(sante.id, 'Soins');
    final hydratationAct    = timeAct(sante.id, 'Hydratation');
    final cuisineAct     = timeAct(sante.id, 'Cuisiner');
    final nettoyerAct    = timeAct(environnement.id, 'Nettoyer');
    final vaisselleAct   = timeAct(environnement.id, 'Vaisselle');
    final lessiveAct     = timeAct(environnement.id, 'Lessive');
    final exterieurAct   = timeAct(environnement.id, 'Extérieur');
    final voitureAct     = timeAct(environnement.id, 'Voiture');
    final etirementAct   = timeAct(sport.id, 'Étirements');
    final intendanceAct  = timeAct(organisation.id, 'Intendance');
    final planifAct      = timeAct(organisation.id, 'Planification', role: ActivityRole.planning);
    final prierAct       = timeAct(spiritualite.id, 'Prier');
    final lireBibleAct   = timeAct(spiritualite.id, 'Lire la Bible');
    final interventAct   = timeAct(business.id, 'Interventions');

    final activities = <Activity>[
      // Spiritualité
      prierAct,
      timeAct(spiritualite.id, 'Méditation'),
      lireBibleAct,

      // Environnement / Maison
      nettoyerAct,
      vaisselleAct,
      timeAct(environnement.id, 'Ranger'),
      lessiveAct,
      exterieurAct,
      voitureAct,
      timeAct(environnement.id, 'Rénovation'),

      // Sport
      timeAct(sport.id, 'Courir'),
      timeAct(sport.id, 'Musculation'),
      etirementAct,

      // Santé
      soinAct,
      hydratationAct,
      cuisineAct,
      timeAct(sante.id, 'Sommeil'),

      // Organisation
      intendanceAct,
      planifAct,
      timeAct(organisation.id, 'Préparation'),
      timeAct(organisation.id, 'Courses', role: ActivityRole.shopping),

      // Business
      interventAct,
      timeAct(business.id, 'Suivi'),
      timeAct(business.id, 'Facturation'),
      timeAct(business.id, 'Contenu'),

      // Skills
      timeAct(skills.id, 'Lecture'),
      timeAct(skills.id, 'Formation'),
    ];

    // ========== Routines (habits) ==========
    final habits = <Activity>[
      // --- HYGIÈNE / SANTÉ ---
      habit(sante.id, 'Hygiène du matin', freq: HabitFreq.daily, linkedActivityId: soinAct.id),
      habit(sante.id, 'Hygiène du soir', freq: HabitFreq.daily, linkedActivityId: soinAct.id),
      habit(sante.id, 'Hygiène hebdomadaire', freq: HabitFreq.weekly, linkedActivityId: soinAct.id),
      dailyCountHabit(
        sante.id,
        "Boire de l'eau",
        target: 8,
        linkedActivityId: hydratationAct.id,
        iconCode: 0xf0695, // Icons.water_drop_outlined
      ),
      dailyCountHabit(
        sante.id,
        "Manger équilibré",
        target: 3,
        linkedActivityId: cuisineAct.id,
      ),
      weeklyCountHabit(
        sante.id,
        "Planifier les repas",
        target: 2,
        linkedActivityId: cuisineAct.id,
      ),
      weeklyCountHabit(
        sante.id,
        "Batch cooking",
        target: 2,
        linkedActivityId: cuisineAct.id,
      ),

      // --- MAISON ---
      habit(environnement.id, 'Faire la vaisselle', freq: HabitFreq.daily, linkedActivityId: vaisselleAct.id),
      habit(environnement.id, "Passer l'aspirateur", freq: HabitFreq.weekly, linkedActivityId: nettoyerAct.id),
      weeklyCountHabit(
        environnement.id,
        "Nettoyage rapide",
        target: 3,
        linkedActivityId: nettoyerAct.id,
      ),
      weeklyCountHabit(
        environnement.id,
        "Faire une lessive",
        target: 3,
        linkedActivityId: lessiveAct.id,
      ),
      habit(environnement.id, 'Gérer la voiture', freq: HabitFreq.weekly, linkedActivityId: voitureAct.id),
      habit(environnement.id, 'Changer draps/serviettes', freq: HabitFreq.weekly, linkedActivityId: lessiveAct.id),

      // --- ORGANISATION / GTD ---
      habit(organisation.id, 'Revue hebdomadaire', freq: HabitFreq.weekly, linkedActivityId: planifAct.id),
      habit(organisation.id, 'Saisir mes dépenses', freq: HabitFreq.daily, linkedActivityId: intendanceAct.id),
      habit(organisation.id, 'Suivre mon budget', freq: HabitFreq.weekly, linkedActivityId: intendanceAct.id),

      // --- SPIRITUEL ---
      dailyCountHabit(
        spiritualite.id,
        "Lire un chapitre",
        target: 3,
        linkedActivityId: lireBibleAct.id,
      ),
      weeklyCountHabit(
        spiritualite.id,
        "Aller à la Prière",
        target: 2,
        linkedActivityId: prierAct.id,
      ),

      // --- SPORT ---
      weeklyCountHabit(
        sport.id,
        "Séance sport",
        target: 3,
      ),

      habit(sport.id, 'Étirements', freq: HabitFreq.weekly, linkedActivityId: etirementAct.id),

      // --- BUSINESS ---
      habit(business.id, 'Préparer une intervention', freq: HabitFreq.daily, linkedActivityId: interventAct.id),
    ];

    Activity habitByName(String name) =>
        habits.firstWhere((h) => h.name == name);

    final hMatin = habitByName('Hygiène du matin');
    final hSoir = habitByName('Hygiène du soir');
    final hHebdo = habitByName('Hygiène hebdomadaire');

    final hEau = habitByName("Boire de l'eau");

    final hMangerEq = habitByName('Manger équilibré');

    final hVaiss = habitByName('Faire la vaisselle');
    final hAspi = habitByName("Passer l'aspirateur");
    final hClean = habitByName('Nettoyage rapide');
    final hLessive = habitByName('Faire une lessive');
    final hVoiture = habitByName('Gérer la voiture');
    final hDraps = habitByName('Changer draps/serviettes');

    final hPlanRepas = habitByName('Planifier les repas');
    final hBatch = habitByName('Batch cooking');

    final hRevue = habitByName('Revue hebdomadaire');
    final hDep = habitByName('Saisir mes dépenses');
    final hBudget = habitByName('Suivre mon budget');

    final hSport = habitByName('Séance sport');
    final hStretch = habitByName('Étirements');

    // ========== CHECKLISTS seed ==========
    final habitChecklistByHabitId = <String, List<String>>{
      // Hygiène matin
      hMatin.id: [
        'Prendre mon café',
        'Douche',
        'Brosser les dents',
        'Maquillage (si nécessaire)',
        'Skincare (visage)',
        'Ranger salle de bain (rapide)',
        'Déodorant',
        'Coiffure',
        'Parfum (option)',
        'Faire le lit',
      ],

      //Eau
      hEau.id: [
        'Préparer ma boutille d\'eau',
        '1 verre d\'eau au réveil',
      ],

      // Hygiène soir
      hSoir.id: [
        'Mettre téléphone en charge',
        'Démaquillage (si besoin)',
        'Douche',
        'Brosser les dents',
        'Skincare (visage)',
        'Préparer vêtements (option)',
      ],

      // Hygiène hebdo
      hHebdo.id: [
        'Couper les ongles',
        'Couper mes cheveux',
        'Me raser',
        'Ranger trousse de toilette',
        'Vérifier trousse à pharmacie',
        'Skincare hebdo',
      ],

      //Manger équilibré

      hMangerEq.id: [
        'Protéines',
        'Fibres',
        'Féculents',
      ],

      // Vaisselle
      hVaiss.id: [
        'Laver & Rincer',
        'Essuyer',
        'Ranger',
        'Nettoyer évier',
      ],

      // Aspirateur
      hAspi.id: [
        'Aspirer la chambre',
        'Aspirer le salon',
        'Aspirer le couloir',
        'Aspirer la salle de bain',
        'Aspirer la cuisine',
      ],

      // Nettoyage rapide
      hClean.id: [
        'Ranger 5 minutes',
        'Essuyer surfaces (rapide)',
        'Vider poubelles si besoin',
        'Aérer 10 minutes',
      ],

      // Lessive
      hLessive.id: [
        'Trier linge',
        'Lancer machine',
        'Étendre / sécher',
        'Plier / ranger',
      ],

      hVoiture.id: [
        'Vider la voiture',
        'Aspirer la voiture',
        'Nettoyer la voiture',
        'Niveau lave glaces',
        'Liquide de refroidissement',
        'Vérifier les pneus',
      ],

      // Draps/serviettes
      hDraps.id: [
        'Changer draps',
        "Changer taies d'oreiller",
        'Changer serviettes',
        'Lancer lavage draps/serviettes',
      ],

      // Préparer repas
      hPlanRepas.id: [
        'Vérifier frigo',
        'Planifier 3 repas',
        'Préparer liste courses',
        'Cuisiner 1 repas simple',
        'Ranger cuisine',
      ],

      // Batch cooking
      hBatch.id: [
        'Choisir menus (2–3)',
        'Préparer ingrédients',
        'Cuire (four / casserole)',
        'Portionner',
        'Étiqueter',
        'Nettoyer + vaisselle',
      ],

      // Revue hebdo (GTD light)
      hRevue.id: [
        'Vider inbox / notes',
        'Revoir “À faire”',
        'Supprimer / archiver actions',
        'Planifier la semaine',
        'Vérifier rendez-vous',
      ],

      // Dépenses
      hDep.id: [
        'Rassembler tickets',
        'Saisir dépenses',
        'Vérifier solde',
      ],

      // Budget
      hBudget.id: [
        'Comparer prévu / réel',
        'Ajuster enveloppes',
        'Prévoir factures',
      ],

      // Sport
      hSport.id: [
        'Échauffement',
        'Séance',
        'Étirements',
        'Hydratation',
      ],

      // Étirements – mobilité (35)
      hStretch.id: [
        'Souplesse 1',
        'Souplesse 2',
        'Souplesse 3',
        'Souplesse 4',
        'Souplesse 5',
        'Souplesse 6',
        'Souplesse 7',
        'Souplesse 8',
        'Souplesse 9',
        'Souplesse 10',
        'Souplesse 11',
        'Souplesse 12',
        'Souplesse 13',
        'Souplesse 14',
        'Souplesse 15',
        'Souplesse 16',
        'Souplesse 17',
        'Souplesse 18',
        'Souplesse 19',
        'Souplesse 20',
        'Souplesse 21',
        'Souplesse 22',
        'Souplesse 23',
        'Souplesse 24',
        'Souplesse 25',
        'Souplesse 26',
        'Souplesse 27',
        'Souplesse 28',
        'Souplesse 29',
        'Souplesse 30',
        'Souplesse 31',
        'Souplesse 32',
        'Souplesse 33',
        'Souplesse 34',
        'Souplesse 35',
      ],
    };

    // ========== Blocs par défaut ==========
    // "Boire de l'eau" est placée dans tous les blocs comme exemple concret
    // pour montrer à l'utilisateur qu'une routine peut traverser toute la journée.
    final seedBlocks = <DayBlock>[];
    const blockNames = [
      'Miracle Morning',
      'Matinée',
      'Midi',
      'Après-midi',
      'Soir',
      'Routine Soir',
    ];
    for (var i = 0; i < blockNames.length; i++) {
      seedBlocks.add(DayBlock(
        name: blockNames[i],
        order: i,
        activityIds: [hEau.id],
      ));
    }

    return AppState(
      domains: [
        sante,
        organisation,
        business,
        skills,
        spiritualite,
        environnement,
        sport,
      ],
      activities: [...activities, ...habits],
      sessions: [],
      habitProgress: [],
      snoozedUntil: {},
      inbox: [],
      focusTodayIds: [],
      sortTodayByDashboard: false,
      habitHits: [],
      habitPinnedActivity: {},
      blocks: seedBlocks,

      // ✅ checklists seedées
      habitChecklistByHabitId: habitChecklistByHabitId,
    );
  }

Future<void> save(AppState st) async {
  final content = st.encode();

  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebKey, content);
    return;
  }

  final f = await _file();
  final tmp = File('${f.path}.tmp');
  final bak = File('${f.path}.bak');

  // 1) écrit dans tmp
  await tmp.writeAsString(content, flush: true);

  // 2) backup de l'ancien
  if (await f.exists()) {
    try {
      await f.copy(bak.path);
    } catch (_) {}
  }

  // 3) replace atomique
  await tmp.rename(f.path);

  // 🔍 DEBUG : vérifier si toPlan=true est bien écrit dans le fichier
/*   final s = await f.readAsString();
  debugPrint(
    s.contains('"toPlan":true')
        ? "SAVE FILE → has toPlan true"
        : "SAVE FILE → no toPlan true",
  ); */
}
}
