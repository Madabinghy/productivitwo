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

    Activity habit(String domainId, String name,
            {HabitFreq freq = HabitFreq.monthly}) =>
        Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          habitFreq: freq,
          habitTarget: 1,
          manualTarget: false,
          autoTune: true,
        );

    // ========== ACTIVITÉS (TIME) ==========
    final activities = <Activity>[
      // --- Spiritualité ---
      timeAct(spiritualite.id, 'Prière'),
      timeAct(spiritualite.id, 'Lecture spirituelle'),

      // --- Environnement / Maison ---
      timeAct(environnement.id, 'Nettoyage'),
      timeAct(environnement.id, 'Rangement'),
      timeAct(environnement.id, 'Lessive'),
      timeAct(environnement.id, 'Extérieur'),

      // --- Sport ---
      timeAct(sport.id, 'Cardio'),
      timeAct(sport.id, 'Renforcement'),
      timeAct(sport.id, 'Étirements'),

      // --- Santé ---
      timeAct(sante.id, 'Soins'),
      timeAct(sante.id, 'Cuisine'),
      timeAct(sante.id, 'Sommeil'),

      // --- Organisation ---
      timeAct(organisation.id, 'Intendance'),
      timeAct(organisation.id, 'Planification'),
      timeAct(
        organisation.id,
        'Courses',
        role: ActivityRole.shopping, // 🔑 clé de ton système
      ),

      // --- Business ---
      timeAct(business.id, 'Facturation'),
      timeAct(business.id, 'Interventions'),
      timeAct(business.id, 'Contenu'),

      // --- Skills ---
      timeAct(skills.id, 'Lecture'),
      timeAct(skills.id, 'Formation'),
    ];

    // ========== ROUTINES (HABITS) ==========
    final habits = <Activity>[
      // --- Santé / Hygiène ---
      habit(sante.id, 'Hygiène du matin', freq: HabitFreq.daily),
      habit(sante.id, 'Hygiène du soir', freq: HabitFreq.daily),
      habit(sante.id, 'Boire de l’eau', freq: HabitFreq.daily),
      habit(sante.id, 'Manger équilibré', freq: HabitFreq.daily),

      // --- Maison ---
      habit(environnement.id, 'Faire la vaisselle', freq: HabitFreq.weekly),
      habit(environnement.id, 'Passer l’aspirateur', freq: HabitFreq.weekly),
      habit(environnement.id, 'Ranger la maison', freq: HabitFreq.weekly),
      habit(environnement.id, 'Faire une lessive', freq: HabitFreq.weekly),

      // --- Organisation ---
      habit(organisation.id, 'Revue hebdomadaire', freq: HabitFreq.weekly),
      habit(organisation.id, 'Saisir mes dépenses', freq: HabitFreq.weekly),

      // --- Spirituel ---
      habit(spiritualite.id, 'Temps calme', freq: HabitFreq.daily),

      // --- Sport ---
      habit(sport.id, 'Séance sport', freq: HabitFreq.weekly),

      // 🔥 UNE SEULE ROUTINE SOUPLESSE
      Activity(
        domainId: sport.id,
        name: 'Étirements',
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: 35, // 🔑 remplace tes 35 routines
        manualTarget: true, // permet checklist / incrément manuel
        autoTune: false,
      ),

      // --- Business ---
      habit(business.id, 'Préparer une intervention', freq: HabitFreq.weekly),
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
      activities: [
        ...activities,
        ...habits,
      ],
      sessions: [],
      habitProgress: [],
      lastGoalsReview: null,
      snoozedUntil: {},
      goals: [],
      inbox: [],
      dayPlan: [],
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
