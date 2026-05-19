import 'package:flutter/material.dart';

class _Entry {
  final String version;
  final String date;
  final List<(IconData, String)> changes;
  const _Entry(this.version, this.date, this.changes);
}

const _changelog = [
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
