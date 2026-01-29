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

  Activity habit(String domainId, String name) => Activity(
        domainId: domainId,
        name: name,
        type: 'habit',
        habitFreq: HabitFreq.monthly,
        habitTarget: 1,
        manualTarget: false,
        autoTune: true,
      );

  // ========== Activités (time) ==========
  final activities = <Activity>[
    // Spiritualité
    timeAct(spiritualite.id, 'GDS'),
    timeAct(spiritualite.id, 'Kingdom'),
    timeAct(spiritualite.id, 'Prier'),
    timeAct(spiritualite.id, 'Lire la Bible'),

    // Environnement
    timeAct(environnement.id, 'Nettoyer'),
    timeAct(environnement.id, 'Ranger'),
    timeAct(environnement.id, 'Extérieur'),
    timeAct(environnement.id, 'Rénovation'),
    timeAct(environnement.id, 'Lessive'),

    // Sport
    timeAct(sport.id, 'Courir'),
    timeAct(sport.id, 'Musculation'),
    timeAct(sport.id, 'Étirements'),

    // Santé
    timeAct(sante.id, 'Soins'),
    timeAct(sante.id, 'Cuisiner'),
    timeAct(sante.id, 'Sommeil'),
    timeAct(sante.id, 'Sieste'),
    timeAct(sante.id, 'Manger'),

    // Organisation
    timeAct(organisation.id, 'Intendance'),
    timeAct(organisation.id, 'Planification'),
    timeAct(organisation.id, 'Préparation'),
    Activity(
      domainId: organisation.id,
      name: 'Courses',
      type: 'time',
      goalMin: 1,
      role: ActivityRole.shopping,
    ),
    timeAct(organisation.id, 'Rendre service'),

    // Business
    timeAct(business.id, 'Facturation'),
    timeAct(business.id, 'Suivi'),
    timeAct(business.id, 'Interventions'),
    timeAct(business.id, 'Contenu'),
    timeAct(business.id, 'Productivitwo'),

    // Skills
    timeAct(skills.id, 'Lecture'),
    timeAct(skills.id, 'PLF Coaching'),
  ];

  // ========== Routines ==========
  final habits = <Activity>[
    // Spiritualité
    habit(spiritualite.id, 'Aller à GDS'),
    habit(spiritualite.id, 'Lire un chapitre'),

    // Environnement
    habit(environnement.id, 'Faire la vaisselle'),
    habit(environnement.id, "Passer la serpillière"),
    habit(environnement.id, "Passer l'aspirateur"),
    habit(environnement.id, 'Faire le lit'),
    habit(environnement.id, 'Ranger la maison'),

    // Sport
    habit(sport.id, 'Faire des pompes'),
    habit(sport.id, 'Faire des tractions'),

    // Santé
    habit(sante.id, 'Prendre un bain de mer'),
    habit(sante.id, 'Prendre un petit-déj'),
    habit(sante.id, 'Mode batch cooking'),
    habit(sante.id, 'Me coucher à 22h'),
    habit(sante.id, 'Boire de l\'eau'),
    habit(sante.id, 'Manger équilibré'),

    // Organisation — NOUVELLES ROUTINES
    habit(organisation.id, 'Hygiène du matin'),
    habit(organisation.id, 'Hygiène du soir'),
    habit(organisation.id, 'Saisir mes dépenses'),
    habit(organisation.id, 'Suivre mon budget'),
    habit(organisation.id, 'Préparer mon matos'),

    // Business
    habit(business.id, 'Faire une facture'),
    habit(business.id, 'Préparer une intervention'),
  ];

  // Sport — Souplesse
  for (int i = 1; i <= 35; i++) {
    habits.add(habit(sport.id, 'Souplesse $i'));
  }

  // ========== Pré-remplissage des actions (checklists + à prévoir) ==========
  final courses = activities.firstWhere(
      (a) => a.role == ActivityRole.shopping,
      orElse: () => throw Exception('Courses introuvable'));

  Activity habitByName(String name) =>
      habits.firstWhere((h) => h.name == name);

  DayPlanItem action({
    required String title,
    required Activity habit,
    Activity? activity,
  }) =>
      DayPlanItem(
        id: UniqueKey().toString(),
        kind: PlanKind.action,
        title: title,
        habitId: habit.id,
        domainId: habit.domainId,
        activityId: activity?.id,
        yyyymmdd: yyyymmdd(DateTime.now()),
        done: false,
        archived: false,
      );

  final dayPlan = <DayPlanItem>[
    // --- Hygiène du matin ---
    action(title: 'Douche', habit: habitByName('Hygiène du matin')),
    action(title: 'Brosser les dents', habit: habitByName('Hygiène du matin')),
    action(title: 'Déodorant', habit: habitByName('Hygiène du matin')),
    action(
      title: 'Dentifrice',
      habit: habitByName('Hygiène du matin'),
      activity: courses,
    ),

    // --- Hygiène du soir ---
    action(title: 'Douche', habit: habitByName('Hygiène du soir')),
    action(title: 'Brosser les dents', habit: habitByName('Hygiène du soir')),
    action(title: 'Skincare', habit: habitByName('Hygiène du soir')),

    // --- Vaisselle ---
    action(title: 'Laver', habit: habitByName('Faire la vaisselle')),
    action(title: 'Rincer', habit: habitByName('Faire la vaisselle')),
    action(title: 'Essuyer', habit: habitByName('Faire la vaisselle')),
    action(
      title: 'Liquide vaisselle',
      habit: habitByName('Faire la vaisselle'),
      activity: courses,
    ),
    action(
      title: 'Éponge',
      habit: habitByName('Faire la vaisselle'),
      activity: courses,
    ),

    // --- Aspirateur ---
    action(title: 'Chambre', habit: habitByName("Passer l'aspirateur")),
    action(title: 'Salon', habit: habitByName("Passer l'aspirateur")),
    action(title: 'Couloir', habit: habitByName("Passer l'aspirateur")),
    action(title: 'Salle de bain', habit: habitByName("Passer l'aspirateur")),
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
