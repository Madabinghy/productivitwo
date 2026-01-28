import 'dart:io';
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
    // ========== Domaines (tous autoGoal) ==========
    final sante = Domain(name: 'Santé', autoGoal: true);
    final organisation = Domain(name: 'Organisation', autoGoal: true);
    final business = Domain(name: 'Business', autoGoal: true);
    final skills = Domain(name: 'Skills', autoGoal: true);
    final spiritualite = Domain(name: 'Spiritualité', autoGoal: true);
    final environnement = Domain(name: 'Environnement', autoGoal: true);
    final sport = Domain(name: 'Sport', autoGoal: true);

    // Helpers
    Activity timeAct(String domainId, String name) => Activity(
          domainId: domainId,
          name: name,
          type: 'time',
          goalMin: 1,
        );

    Activity habit(String domainId, String name) => Activity(
          domainId: domainId,
          name: name,
          type: 'habit',
          habitFreq: HabitFreq.monthly, // ✅ 30j par défaut (ton choix)
          habitTarget: 1,
          manualTarget: false,
          autoTune: true,
        );

    // ========== Activités (time) ==========
    final activities = <Activity>[
      // Spiritualité — Activités
      timeAct(spiritualite.id, 'GDS'),
      timeAct(spiritualite.id, 'Kingdom'),
      timeAct(spiritualite.id, 'Prier'),
      timeAct(spiritualite.id, 'Lire la Bible'),

      // Environnement — Activités
      timeAct(environnement.id, 'Nettoyer'),
      timeAct(environnement.id, 'Ranger'),
      timeAct(environnement.id, 'Extérieur'),
      timeAct(environnement.id, 'Rénovation'),
      timeAct(environnement.id, 'Lessive'),

      // Sport — Activités
      timeAct(sport.id, 'Courir'),
      timeAct(sport.id, 'Musculation'),
      timeAct(sport.id, 'Étirements'),

      // Santé — Activités
      timeAct(sante.id, 'Soins'),
      timeAct(sante.id, 'Cuisiner'),
      timeAct(sante.id, 'Sommeil'),
      timeAct(sante.id, 'Sieste'),
      timeAct(sante.id, 'Manger'),

      // Organisation — Activités
      timeAct(organisation.id, 'Intendance'),
      timeAct(organisation.id, 'Planification'),
      timeAct(organisation.id, 'Préparation'),
      timeAct(organisation.id, 'Courses'),
      timeAct(organisation.id, 'Rendre service'),

      // Business — Activités
      timeAct(business.id, 'Facturation'),
      timeAct(business.id, 'Suivi'),
      timeAct(business.id, 'Interventions'),
      timeAct(business.id, 'Contenu'),
      timeAct(business.id, 'Productivitwo'),

      // Skills — Activités
      timeAct(skills.id, 'Lecture'),
      timeAct(skills.id, 'PLF Coaching'),
    ];

    // ========== Routines (habits) ==========
    final habits = <Activity>[
      // Spiritualité — Routines
      habit(spiritualite.id, 'Aller à GDS'),
      habit(spiritualite.id, 'Lire un chapitre'),

      // Environnement — Routines
      habit(environnement.id, 'Faire la vaisselle'),
      habit(environnement.id, "Passer la serpillière"),
      habit(environnement.id, "Passer l'aspirateur"),
      habit(environnement.id, 'Couper les herbes'),
      habit(environnement.id, 'Passer le kasher'),
      habit(environnement.id, 'Tailler les haies'),
      habit(environnement.id, 'Faire le lit'),
      habit(environnement.id, 'Faire le tri'),
      habit(environnement.id, 'Ranger la maison'),
      habit(environnement.id, 'Nettoyer les murs'),
      habit(environnement.id, 'Nettoyer le frigo'),
      habit(environnement.id, 'Nettoyer par derrière'),

      // Sport — Routines (hors souplesse)
      habit(sport.id, 'Faire des pompes'),
      habit(sport.id, 'Faire des tractions'),

      // Santé — Routines
      habit(sante.id, 'Prendre un bain de mer'),
      habit(sante.id, 'Prendre un petit-déj'),
      habit(sante.id, 'Mode batch cooking'),
      habit(sante.id, 'Me coucher à 22h'),
      habit(sante.id, 'Boire de l\'eau'),
      habit(sante.id, 'Manger équilibré'),

      // Organisation — Routines
      habit(organisation.id, 'Saisir mes dépenses'),
      habit(organisation.id, 'Suivre mon budget'),
      habit(organisation.id, 'Faire les courses'),
      habit(organisation.id, 'Préparer mon matos'),
      habit(organisation.id, 'Aller à la répète'),
      habit(organisation.id, 'Réveil à 4h'),

      // Business — Routines
      habit(business.id, 'Faire une facture'),
      habit(business.id, 'Préparer une intervention'),

      // Skills — Routines : non listées sur ta carte mentale (laisse vide pour l’instant)
      // (si tu veux, ajoute-les ici)
    ];

    // Sport — Souplesse 1..35 (Routines)
    for (int i = 1; i <= 35; i++) {
      habits.add(habit(sport.id, 'Souplesse $i'));
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
