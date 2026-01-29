import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class FileStore {
  static const _fileName = 'productivitwo.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // NEW: supprime le fichier de données
  Future<void> wipe() async {
    final f = await _file();
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<AppState> loadOrInit() async {
    final f = await _file();
    final bak = File('${f.path}.bak');

    AppState? tryDecode(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      try {
        return AppState.decode(t);
      } catch (_) {
        return null;
      }
    }

    if (await f.exists()) {
      final main = tryDecode(await f.readAsString());
      if (main != null) return main;

      if (await bak.exists()) {
        final b = tryDecode(await bak.readAsString());
        if (b != null) {
          await save(b); // répare le main
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
    Activity timeAct(String domainId, String name,
            {ActivityRole role = ActivityRole.generic}) =>
        Activity(
          domainId: domainId,
          name: name,
          type: 'time',
          goalMin: 1,
          role: role,
        );

    Activity habit(
      String domainId,
      String name, {
      HabitFreq freq = HabitFreq.monthly, // ton default = 30j
      int target = 1,
      bool manualTarget = false,
      bool autoTune = true,
    }) =>
        Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          habitFreq: freq,
          habitTarget: target,
          manualTarget: manualTarget,
          autoTune: autoTune,
        );

    // ========== Activités (time) ==========
    final activities = <Activity>[
      // Spiritualité
      timeAct(spiritualite.id, 'Prier'),
      timeAct(spiritualite.id, 'Lire la Bible'),

      // Environnement
      timeAct(environnement.id, 'Nettoyer'),
      timeAct(environnement.id, 'Ranger'),
      timeAct(environnement.id, 'Lessive'),
      timeAct(environnement.id, 'Extérieur'),
      timeAct(environnement.id, 'Rénovation'),

      // Sport
      timeAct(sport.id, 'Courir'),
      timeAct(sport.id, 'Musculation'),
      timeAct(sport.id, 'Étirements'),

      // Santé
      timeAct(sante.id, 'Soins'),
      timeAct(sante.id, 'Cuisine'),
      timeAct(sante.id, 'Sommeil'),

      // Organisation
      timeAct(organisation.id, 'Intendance'),
      timeAct(organisation.id, 'Planification'),
      timeAct(organisation.id, 'Préparation'),
      timeAct(organisation.id, 'Courses', role: ActivityRole.shopping),

      // Business
      timeAct(business.id, 'Productivitwo'),
      timeAct(business.id, 'Facturation'),
      timeAct(business.id, 'Contenu'),

      // Skills
      timeAct(skills.id, 'Lecture'),
      timeAct(skills.id, 'Formation'),
    ];

    // ========== Routines (habits) ==========
    final habits = <Activity>[
      // --- HYGIÈNE ---
      habit(sante.id, 'Hygiène du matin', freq: HabitFreq.daily),
      habit(sante.id, 'Hygiène du soir', freq: HabitFreq.daily),
      habit(sante.id, 'Hygiène hebdomadaire', freq: HabitFreq.weekly),

      // --- SANTÉ ---
      habit(sante.id, 'Boire de l’eau', freq: HabitFreq.daily),
      habit(sante.id, 'Manger équilibré', freq: HabitFreq.daily),
      habit(sante.id, 'Préparer les repas', freq: HabitFreq.weekly),
      habit(sante.id, 'Batch cooking', freq: HabitFreq.weekly),

      // --- MAISON ---
      habit(environnement.id, 'Faire la vaisselle', freq: HabitFreq.weekly),
      habit(environnement.id, "Passer l'aspirateur", freq: HabitFreq.weekly),
      habit(environnement.id, 'Nettoyage rapide', freq: HabitFreq.weekly),
      habit(environnement.id, 'Faire une lessive', freq: HabitFreq.weekly),
      habit(environnement.id, 'Changer draps/serviettes',
          freq: HabitFreq.weekly),

      // --- ORGANISATION / GTD ---
      habit(organisation.id, 'Revue hebdomadaire', freq: HabitFreq.weekly),
      habit(organisation.id, 'Saisir mes dépenses', freq: HabitFreq.weekly),
      habit(organisation.id, 'Suivre mon budget', freq: HabitFreq.weekly),

      // --- SPIRITUEL ---
      habit(spiritualite.id, 'Temps calme', freq: HabitFreq.daily),

      // --- SPORT ---
      habit(sport.id, 'Séance sport', freq: HabitFreq.weekly),

      // ✅ Souplesse regroupée en 1 routine (35 étapes via checklist)
      habit(
        sport.id,
        'Étirements – mobilité (35)',
        freq: HabitFreq.weekly,
        target: 1, // la routine = 1, la checklist = 35 étapes
        manualTarget: false,
        autoTune: true,
      ),

      // --- BUSINESS ---
      habit(business.id, 'Préparer une intervention', freq: HabitFreq.weekly),
    ];

    Activity habitByName(String name) =>
        habits.firstWhere((h) => h.name == name);

    final hMatin = habitByName('Hygiène du matin');
    final hSoir = habitByName('Hygiène du soir');
    final hHebdo = habitByName('Hygiène hebdomadaire');
    final hVaiss = habitByName('Faire la vaisselle');
    final hAspi = habitByName("Passer l'aspirateur");
    final hClean = habitByName('Nettoyage rapide');
    final hLessive = habitByName('Faire une lessive');
    final hDraps = habitByName('Changer draps/serviettes');
    final hPrep = habitByName('Préparer les repas');
    final hBatch = habitByName('Batch cooking');
    final hRevue = habitByName('Revue hebdomadaire');
    final hDep = habitByName('Saisir mes dépenses');
    final hBudget = habitByName('Suivre mon budget');
    final hSport = habitByName('Séance sport');
    final hStretch = habitByName('Étirements – mobilité (35)');

    final coursesAct =
        activities.firstWhere((a) => a.role == ActivityRole.shopping);

    // ========== CHECKLISTS (seed) ==========
    final habitChecklistByHabitId = <String, List<String>>{
      // Hygiène matin
      hMatin.id: [
        'Boire un verre d’eau',
        'Douche',
        'Brosser les dents',
        'Skincare (visage)',
        'Déodorant',
        'Coiffure',
        'Parfum (option)',
        'Ranger salle de bain (rapide)',
      ],

      // Hygiène soir
      hSoir.id: [
        'Démaquillage (si besoin)',
        'Brosser les dents',
        'Skincare (visage)',
        'Préparer vêtements (option)',
        'Mettre téléphone en charge',
      ],

      // Hygiène hebdo
      hHebdo.id: [
        'Couper les ongles',
        'Nettoyer/affûter rasoir ou tondeuse',
        'Changer brosse à dents si usée',
        'Nettoyer trousse de toilette',
        'Ranger/vider trousse à pharmacie',
      ],

      // Vaisselle
      hVaiss.id: [
        'Laver',
        'Rincer',
        'Essuyer',
        'Ranger',
        'Nettoyer évier',
      ],

      // Aspirateur (checklist pièces)
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

      // Draps/serviettes
      hDraps.id: [
        'Changer draps',
        'Changer taies d’oreiller',
        'Changer serviettes',
        'Lancer lavage draps/serviettes',
      ],

      // Préparer repas
      hPrep.id: [
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
        'Nettoyer actions (supprimer / archiver)',
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

    // ========== À PRÉVOIR (Courses) seedé, lié aux routines ==========
    int _seq = 0;
    String _newId() =>
        'seed:${DateTime.now().millisecondsSinceEpoch}:${_seq++}';

    DayPlanItem toPlan({
      required String title,
      required Activity habit,
    }) {
      return DayPlanItem(
        id: _newId(),
        kind: PlanKind.action,
        title: title,
        yyyymmdd: yyyymmdd(DateTime.now()),
        done: false,
        archived: false,
        doneCount: 0,
        allDay: true,
        order: 0,
        domainId: habit.domainId,
        habitId: habit.id,
        activityId: coursesAct.id, // ✅ section Courses
      );
    }

    // Liste courses exhaustive (personne seule) — l’utilisateur supprime ce qu’il veut
    final dayPlan = <DayPlanItem>[
      // --- Hygiène (matin/soir/hebdo) ---
      toPlan(title: 'Dentifrice', habit: hMatin),
      toPlan(title: 'Brosse à dents', habit: hMatin),
      toPlan(title: 'Fil dentaire', habit: hMatin),
      toPlan(title: 'Bain de bouche', habit: hSoir),
      toPlan(title: 'Savon / gel douche', habit: hMatin),
      toPlan(title: 'Shampoing', habit: hMatin),
      toPlan(title: 'Après-shampoing', habit: hMatin),
      toPlan(title: 'Déodorant', habit: hMatin),
      toPlan(title: 'Crème visage', habit: hSoir),
      toPlan(title: 'Crème corps', habit: hHebdo),
      toPlan(title: 'Coton', habit: hSoir),
      toPlan(title: 'Cotons-tiges', habit: hHebdo),
      toPlan(title: 'Rasoir (jetable) / lames', habit: hHebdo), // homme/femme
      toPlan(title: 'Mousse/gel à raser', habit: hHebdo),
      toPlan(title: 'After shave / baume', habit: hHebdo),
      toPlan(title: 'Serviettes hygiéniques', habit: hHebdo), // femme
      toPlan(title: 'Tampons', habit: hHebdo), // femme
      toPlan(title: 'Protège-slips', habit: hHebdo), // femme
      toPlan(title: 'Démaquillant', habit: hSoir), // femme (option)
      toPlan(title: 'Lait corporel', habit: hHebdo),

      // --- Vaisselle ---
      toPlan(title: 'Liquide vaisselle', habit: hVaiss),
      toPlan(title: 'Éponges', habit: hVaiss),
      toPlan(title: 'Gants vaisselle', habit: hVaiss),
      toPlan(title: 'Produit multi-usage cuisine', habit: hVaiss),
      toPlan(title: 'Essuie-tout (Sopalin)', habit: hVaiss),

      // --- Aspirateur / Nettoyage ---
      toPlan(title: 'Sacs aspirateur', habit: hAspi),
      toPlan(title: 'Filtre aspirateur', habit: hAspi),
      toPlan(title: 'Sacs poubelle (petits)', habit: hClean),
      toPlan(title: 'Sacs poubelle (grands)', habit: hClean),
      toPlan(title: 'Produit multi-surfaces', habit: hClean),
      toPlan(title: 'Lingettes (option)', habit: hClean),
      toPlan(title: 'Javel (option)', habit: hClean),
      toPlan(title: 'Serpillière / microfibres', habit: hClean),

      // --- Lessive / Draps ---
      toPlan(title: 'Lessive', habit: hLessive),
      toPlan(title: 'Adoucissant (option)', habit: hLessive),
      toPlan(title: 'Détachant', habit: hLessive),
      toPlan(title: 'Pinces à linge', habit: hLessive),

      // --- Cuisine / Repas / Batch ---
      toPlan(title: 'Huile', habit: hPrep),
      toPlan(title: 'Sel', habit: hPrep),
      toPlan(title: 'Poivre', habit: hPrep),
      toPlan(title: 'Riz', habit: hPrep),
      toPlan(title: 'Pâtes', habit: hPrep),
      toPlan(title: 'Farine', habit: hBatch),
      toPlan(title: 'Sucre', habit: hBatch),
      toPlan(title: 'Œufs', habit: hPrep),
      toPlan(title: 'Lait', habit: hPrep),
      toPlan(title: 'Beurre', habit: hPrep),
      toPlan(title: 'Yaourts', habit: hPrep),
      toPlan(title: 'Poulet / protéines', habit: hBatch),
      toPlan(title: 'Légumes', habit: hBatch),
      toPlan(title: 'Fruits', habit: hPrep),
      toPlan(title: 'Conserves (thon/haricots)', habit: hBatch),
      toPlan(title: 'Épices (curry/paprika)', habit: hBatch),
      toPlan(title: 'Oignons / ail', habit: hPrep),
      toPlan(title: 'Sauce tomate', habit: hPrep),

      // --- Organisation (papier, maison) ---
      toPlan(title: 'Papier toilette', habit: hClean),
      toPlan(title: 'Mouchoirs', habit: hHebdo),
      toPlan(title: 'Piles', habit: hRevue),
      toPlan(title: 'Ampoules', habit: hRevue),
    ];

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
      lastGoalsReview: null,
      snoozedUntil: {},
      goals: [],
      inbox: [],
      dayPlan: dayPlan,
      focusTodayIds: [],
      sortTodayByDashboard: false,
      habitHits: [],
      habitPinnedActivity: {},

      // ✅ seed checklist
      habitChecklistByHabitId: habitChecklistByHabitId,
    );
  }

  Future<void> save(AppState st) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    final bak = File('${f.path}.bak');

    final content = st.encode();

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
  }
}
