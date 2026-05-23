import 'package:flutter/material.dart';

class _Entry {
  final String version;
  final String date;
  final List<(IconData, String)> changes;
  const _Entry(this.version, this.date, this.changes);
}

const _changelog = [
  _Entry('5.9', '23 mai 2026', [
    (Icons.touch_app_outlined, 'Projets iOS : tap action = éditer, appui long = réordonner, tap carte = ouvrir la tâche'),
    (Icons.emoji_events_outlined, 'Gamification : sous-actions projet branchées aux badges (comptage immédiat + persistance)'),
    (Icons.tune_outlined, 'Widget score : paliers basés sur les vraies actions Gantt + label "Actions du jour"'),
    (Icons.play_arrow_rounded, 'FAB restauré : ▶ Lancer activité (groupé par domaine, scrollable) + mini Routine & Action'),
    (Icons.radio_button_unchecked, 'Dashboard : anneaux épurés — chiffres + icône, sans texte'),
    (Icons.smart_toy_outlined, 'ORION : "cycles" → "actions stratégiques aujourd\'hui"'),
  ]),
  _Entry('5.8', '23 mai 2026', [
    (Icons.check_circle_outline, 'Projets iOS : section RÉALISÉ — projets avec toutes leurs tâches ok, au-dessus de Hors scope'),
  ]),
  _Entry('5.7', '23 mai 2026', [
    (Icons.delete_outline, 'Gantt web : suppression d\'un fichier depuis la fiche tâche'),
    (Icons.picture_as_pdf_outlined, 'Gantt web : upload PDF (< 700 Ko) avec aperçu intégré'),
    (Icons.notes_outlined, 'Gantt web : description de tâche éditable (tap sur le champ)'),
    (Icons.drive_file_rename_outline, 'Gantt web : renommer une phase en tapant sur la bande'),
  ]),
  _Entry('5.6', '23 mai 2026', [
    (Icons.touch_app_outlined, 'Focus : tap sur la tâche Gantt liée ouvre la fiche (appui long = délier)'),
    (Icons.upload_file_outlined, 'Gantt web : upload de fichiers dans une tâche (txt, md, html, json, images…)'),
  ]),
  _Entry('5.5', '23 mai 2026', [
    (Icons.add_circle_outline, 'Gantt web : bouton + dans la barre pour ajouter une tâche (titre, phase, dates, jalon)'),
    (Icons.layers_outlined, 'Gantt web : changer la phase d\'une tâche depuis la fiche (déplace visuellement la tâche)'),
    (Icons.palette_outlined, 'Gantt web : color picker sur la barre de chaque tâche (palette + couleur de la phase)'),
    (Icons.search_outlined, 'Archives web : recherche + filtre Tout / Actifs / Archivés'),
  ]),
  _Entry('5.4', '22 mai 2026', [
    (Icons.format_list_bulleted, 'Maintenant : sous-actions scrollables quand la liste est longue'),
    (Icons.bolt_outlined, 'ORION : fix erreur index Firestore sur les messages'),
  ]),
  _Entry('5.3', '22 mai 2026', [
    (Icons.timer_outlined, 'Dashboard : icônes dans les jauges (⏱ ↺ ⬡)'),
    (Icons.account_tree_outlined, 'Projets iOS : tâches correctement groupées par phase (fix groupLabel)'),
    (Icons.archive_outlined, 'Projets iOS : archiver/réactiver un projet depuis la fiche'),
    (Icons.view_agenda_outlined, 'Projets iOS : sections Hors scope et En veille'),
    (Icons.reorder, 'Projets iOS : appui long pour réordonner les sous-actions directement'),
    (Icons.play_arrow_outlined, 'Sheet démarrer : affichage du temps loggué aujourd\'hui par activité'),
    (Icons.link_outlined, 'Web : chemin MCP mis à jour (Paramètres → Personnaliser → Connecteurs)'),
  ]),
  _Entry('5.2', '22 mai 2026', [
    (Icons.dashboard_outlined, 'Dashboard : 3ème jauge Projets (tâches Gantt actives du jour)'),
    (Icons.move_to_inbox_outlined, 'Projets : changer de domaine depuis iOS et le web'),
    (Icons.light_mode_outlined, 'Gantt web : toggle clair/sombre déplacé dans la barre Semaine/Jour'),
    (Icons.star_outlined, 'Badges : 🎯 10/50/100 tâches Gantt validées (remplace les actions)'),
    (Icons.cleaning_services_outlined, 'Purge automatique des anciennes actions au démarrage'),
  ]),
  _Entry('5.1', '22 mai 2026', [
    (Icons.repeat_rounded, 'App bar : bouton Routines — liste du jour avec progression et incrément'),
    (Icons.smart_toy_outlined, 'ORION : intégré comme onglet natif dans la nav principale'),
    (Icons.cloud_outlined, 'Statut sync/Pro déplacé dans le menu ⋮'),
    (Icons.play_circle_outline, 'Maintenant : FAB Démarrer (remplace le bouton), clavier ORION corrigé'),
    (Icons.check_rounded, 'Projets : bouton Valider quand tâche à 100%, bouton + pour ajouter une action'),
    (Icons.task_outlined, 'Fiche projet : tap tâche → sheet détail avec swipe delete + reorder actions'),
    (Icons.close, 'Sheet activité : bouton fermer ajouté'),
  ]),
  _Entry('5.0', '22 mai 2026', [
    (Icons.account_tree_outlined, 'Nouvelle nav : Accueil · Projets · Maintenant · ORION'),
    (Icons.play_circle_outline, 'Maintenant : camembert du jour + flow démarrer (activité → tâche Gantt)'),
    (Icons.checklist_outlined, 'Maintenant actif : timer + tâche Gantt liée + sous-actions cochables'),
    (Icons.account_tree_outlined, 'Projets : bouton ▶ sur chaque tâche pour lancer directement'),
    (Icons.document_scanner_outlined, 'Fiche projet : documents liés au projet visibles en bas'),
    (Icons.today_outlined, 'Projets : phases affichées, tâches filtrées sur aujourd\'hui uniquement'),
  ]),
  _Entry('4.4', '22 mai 2026', [
    (Icons.picture_as_pdf_outlined, 'PDF Gantt : emojis retirés des titres et descriptions'),
  ]),
  _Entry('4.3', '22 mai 2026', [
    (Icons.image_outlined, 'Gantt : export PNG haute résolution (bouton 🖼 dans la barre de la grille)'),
    (Icons.delete_outline, 'Gantt : suppression d\'une tâche depuis la fiche'),
    (Icons.drag_handle, 'Gantt : réorganisation des actions par drag & drop'),
    (Icons.open_in_full, 'Gantt : dialog tâche plus large (720px)'),
    (Icons.light_mode_outlined, 'Gantt : bouton mode clair dans l\'app bar'),
  ]),
  _Entry('4.2', '22 mai 2026', [
    (Icons.account_tree_outlined, 'Objectifs unifiés — les projets Gantt sont désormais la seule source de vérité, accessibles via le bouton ⬡ dans la barre'),
    (Icons.flag_outlined, 'Suppression du système GTD Goals — plus de confusion entre deux systèmes'),
    (Icons.bolt_rounded, 'À faire : directement les actions, sans l\'onglet Objectifs'),
  ]),
  _Entry('4.1', '22 mai 2026', [
    (Icons.delete_outline, 'Web : suppression définitive d\'un projet archivé'),
    (Icons.help_outline_rounded, 'Web : schéma "Comment ça marche ?" dans le tab ORION'),
  ]),
  _Entry('4.0', '22 mai 2026', [
    (Icons.bolt_outlined, 'Web : fix actions rapides ORION (Analyser retards, Deadlines…) — envoyées au bon endpoint'),
  ]),
  _Entry('3.9', '22 mai 2026', [
    (Icons.account_tree_outlined, 'Objectifs : tâches Gantt actives enfin visibles — retards en rouge, tap ouvre la fiche projet'),
    (Icons.flag_outlined, 'Objectifs : fix clavier caché + erreur index Firestore'),
  ]),
  _Entry('3.8', '22 mai 2026', [
    (Icons.notifications_outlined, 'Notifications push ORION — reçois un message dès qu\'ORION génère un conseil (cron 6h, déclenchement manuel iOS ou web)'),
  ]),
  _Entry('3.7', '22 mai 2026', [
    (Icons.smart_toy_outlined, 'ORION : nouvelle page dédiée avec identité visuelle, onboarding et statut de plan (Gratuit ∞ · Pro)'),
    (Icons.message_outlined, 'Messages ORION redesignés : cards hiérarchisées, badge PRÉVU, réponse rapide en bas de page'),
  ]),
  _Entry('3.6', '22 mai 2026', [
    (Icons.sync_outlined, 'iOS : projets, goals et domaines synchronisés en temps réel depuis Firestore'),
    (Icons.account_tree_outlined, 'Fix : projets Gantt affichés même si le domaine n\'est pas encore connu localement'),
  ]),
  _Entry('3.5', '22 mai 2026', [
    (Icons.key_outlined, 'Fix : tokens API affichés correctement (Timestamp Firestore → DateTime)'),
  ]),
  _Entry('3.4', '22 mai 2026', [
    (Icons.smart_toy_outlined, 'ORION autonome : agent IA qui génère des messages contextuels toutes les 6h'),
    (Icons.tune, 'Configuration ORION : instructions persistantes + réponse directe depuis le menu'),
  ]),
  _Entry('3.3', '22 mai 2026', [
    (Icons.sync_outlined, 'iOS : projets Gantt mis à jour en temps réel dans la vue Objectifs'),
  ]),
  _Entry('3.2', '21 mai 2026', [
    (Icons.account_tree_outlined, 'Objectifs unifiés : tâches Gantt actives visibles dans la vue Objectifs iOS'),
    (Icons.check_box_outlined, 'Sous-actions des tâches Gantt cochables directement depuis les Objectifs'),
    (Icons.open_in_new, 'Tap sur une tâche → fiche projet complète avec scroll vers la tâche'),
  ]),
  _Entry('3.1', '21 mai 2026', [
    (Icons.account_tree_outlined, 'iOS : fiche projet Gantt — tâches, phases, retards, statuts modifiables'),
    (Icons.open_in_new, 'ORION : bouton "Voir la tâche" ouvre directement la fiche Gantt concernée'),
    (Icons.delete_outline, 'Suppression de documents depuis l\'app web et iOS'),
    (Icons.history, 'Fix : messages ORION fallback visibles dans l\'historique'),
  ]),
  _Entry('3.0', '21 mai 2026', [
    (Icons.smart_toy_outlined, 'Assistant ORION : messages contextuels avec effet typewriter, planifiés par Claude'),
    (Icons.notifications_outlined, 'Fallbacks autonomes : deadlines proches, jalons, retards — sans connexion Claude'),
    (Icons.history, 'Historique ORION : accès aux messages passés et à venir via le bouton robot 🤖'),
  ]),
  _Entry('2.9', '21 mai 2026', [
    (Icons.tune, 'Cibles de temps 100% manuelles — la progression automatique a été retirée'),
    (Icons.timer_outlined, 'Fiche activité : saisie directe de la cible quotidienne (en minutes)'),
  ]),
  _Entry('2.8', '21 mai 2026', [
    (Icons.delete_outline, 'Fix : supprimer une action en swipe est maintenant persistant après redémarrage'),
    (Icons.download_outlined, 'Bouton téléchargement (.html) dans la visionneuse de programmes depuis la liste des projets'),
  ]),
  _Entry('2.7', '19 mai 2026', [
    (Icons.smart_toy_outlined, 'Claude peut supprimer activités, actions et routines du plan'),
    (Icons.folder_outlined, 'Claude peut créer et supprimer des domaines de vie'),
    (Icons.sync_outlined, 'Sync : suppressions faites par Claude résistantes à la synchronisation'),
  ]),
  _Entry('2.6', '19 mai 2026', [
    (Icons.archive_outlined, 'Projets Gantt : mettre en veille et réactiver depuis le web app'),
    (Icons.add_circle_outline, 'Claude peut créer et modifier des activités directement'),
  ]),
  _Entry('2.5', '19 mai 2026', [
    (Icons.apple, 'Compte Apple : affichage clair de l\'état connecté + messages d\'erreur'),
    (Icons.key_outlined, 'Tokens API : UID Apple visible et copiable pour lier au web app'),
  ]),
  _Entry('2.4', '19 mai 2026', [
    (Icons.link_outlined, 'Liaison compte iOS ↔ web app : connecte-toi avec ton UID + token iOS sur productivitwo-app.web.app'),
    (Icons.smart_toy_outlined, 'Claude peut lire et modifier tes activités, routines et plan du jour via MCP'),
  ]),
  _Entry('2.3', '19 mai 2026', [
    (Icons.schedule_outlined, 'Routines temporelles : définis une période de début/fin sur chaque action récurrente'),
    (Icons.account_tree_outlined, 'Actions de tâche Gantt : ajoute le détail opérationnel à chaque tâche, planifiable au quotidien'),
  ]),
  _Entry('2.2', '19 mai 2026', [
    (Icons.key_outlined, 'Tokens API : génère des tokens pour envoyer des projets Gantt depuis Claude ou un coach'),
    (Icons.account_tree_outlined, 'Web app : visualise tes projets Gantt sur productivitwo-app.web.app'),
  ]),
  _Entry('2.1', '18 mai 2026', [
    (Icons.show_chart, 'Pro : heatmap 12 semaines + graphe couleur domaine dans la liste des activités'),
    (Icons.bar_chart, 'Fiche activité : graphe moyenne mobile ajouté au-dessus de la heatmap'),
    (Icons.rocket_launch_outlined, 'Onboarding : packs prêts-à-l\'emploi (Sport & Santé, Entrepreneur, Développement personnel)'),
    (Icons.apple, 'Compte Apple accessible directement depuis le menu'),
    (Icons.flag_outlined, 'Création d\'objectif : nouveau sheet fluide (même style que les actions)'),
    (Icons.grid_view_outlined, 'Heatmap activité : référence adaptée au max de l\'activité (min 5h)'),
  ]),
  _Entry('2.0', '18 mai 2026', [
    (Icons.flag_outlined, 'Objectifs : carte colorée par domaine, barre de progression et % visibles'),
    (Icons.library_add_outlined, 'Catalogue post-onboarding : ajouter domaines, activités et routines à tout moment'),
    (Icons.mail_outline, '"Suggérer une feature" dans le menu'),
    (Icons.grid_view_outlined, 'Heatmap activité : bug corrigé les lundis, référence fixe 5h'),
    (Icons.apple, 'Connexion Apple : sauvegarde et restauration sur plusieurs appareils'),
  ]),
  _Entry('1.9', '15 mai 2026', [
    (Icons.color_lens_outlined, 'Couleur personnalisée par domaine'),
    (Icons.cloud_outlined, 'Sync Firestore : données sauvegardées et synchronisées automatiquement'),
  ]),
  _Entry('1.8', '15 mai 2026', [
    (Icons.bar_chart_outlined, 'Barres 24h colorées par domaine dans l\'AppBar'),
    (Icons.repeat_outlined, 'Dashboard : widget Routines avec 3 barres par fréquence'),
    (Icons.tune, 'Création de routine : choix de la fréquence et de la cible'),
    (Icons.history, 'Actions reportées tracées en vue Semaine + score historique plus juste'),
  ]),
  _Entry('1.7', '15 mai 2026', [
    (Icons.grid_view_outlined, 'Heatmap : référence fixe 5h, tous les domaines visibles'),
    (Icons.folder_outlined, 'Activités : déplacer vers un autre domaine'),
    (Icons.trending_up_outlined, 'Notification "Objectif ajusté : +Xmin" à l\'arrêt d\'une activité'),
    (Icons.more_vert, 'AppBar allégée : stats, filtres et nouveautés dans le menu ⋮'),
  ]),
  _Entry('1.6', '15 mai 2026', [
    (Icons.layers_outlined, 'Routines multi-blocs : une même routine peut apparaître dans plusieurs blocs'),
    (Icons.water_drop_outlined, '"Boire de l\'eau" pré-configurée dans tous les blocs à l\'installation'),
    (Icons.compress, 'Blocs repliés par défaut à l\'ouverture de À faire'),
    (Icons.circle, 'Couleur de domaine sur les routines dans les blocs'),
    (Icons.play_circle_outlined, 'Toggle "Tout afficher" sans arrêter la session en cours'),
    (Icons.calendar_view_week_outlined, 'Vue Semaine : tap pour sheet d\'action (renommer, déplacer, bloc, activité, supprimer)'),
    (Icons.arrow_forward_outlined, 'Suppression du bouton "À demain" sur les routines'),
  ]),
  _Entry('1.5', 'mai 2026', [
    (Icons.view_day_outlined, 'Blocs journaliers : organiser les routines et actions par moment de la journée'),
    (Icons.report_outlined, 'Rapport temps : donut, barres 12 semaines, heatmap par domaine'),
    (Icons.rocket_launch_outlined, 'FAB lancement rapide d\'activité'),
  ]),
];

void showChangelogSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ChangelogSheet(),
  );
}

class _ChangelogSheet extends StatelessWidget {
  const _ChangelogSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            'Nouveautés',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          for (final entry in _changelog) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v${entry.version}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  entry.date,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final (icon, text) in entry.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
