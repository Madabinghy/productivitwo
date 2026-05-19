import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bouton d'aide accessible depuis la barre de navigation web.
class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline, size: 18),
      tooltip: 'Astuces et exemples',
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const _HelpSheet(),
      ),
    );
  }
}

// ── Sheet principal ───────────────────────────────────────────────────────────

class _HelpSheet extends StatefulWidget {
  const _HelpSheet();

  @override
  State<_HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends State<_HelpSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                const Text('Astuces & exemples',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: const [
              Tab(text: 'Débuter'),
              Tab(text: 'Exemples Claude'),
              Tab(text: 'Fonctionnalités'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _StartTab(scroll: scroll),
                _ExamplesTab(scroll: scroll),
                _FeaturesTab(scroll: scroll),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Onglet Débuter ────────────────────────────────────────────────────────────

class _StartTab extends StatelessWidget {
  final ScrollController scroll;
  const _StartTab({required this.scroll});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(20),
      children: const [
        _Step(
          number: '1',
          icon: Icons.smartphone_outlined,
          title: 'Connecte ton compte iOS',
          body:
              'Menu ⋮ → Tokens API dans l\'app iPhone.\n'
              'Copie ton UID (en haut) et génère un token.\n'
              'Puis sur cette page → "Connecter Claude" → "Compte iOS".',
        ),
        SizedBox(height: 16),
        _Step(
          number: '2',
          icon: Icons.auto_awesome_outlined,
          title: 'Connecte Claude.ai',
          body:
              'Dans cette page → "Connecter Claude" → copie l\'URL MCP.\n'
              'Claude.ai → Paramètres → Intégrations → Ajouter → colle l\'URL.\n'
              'Reconnecte-toi si Claude ne voit pas les nouveaux outils.',
        ),
        SizedBox(height: 16),
        _Step(
          number: '3',
          icon: Icons.chat_outlined,
          title: 'Parle à Claude',
          body:
              'Claude connaît maintenant tes objectifs, routines, activités '
              'et tout ce que tu as fait cette semaine.\n'
              'Utilise les exemples de l\'onglet suivant pour démarrer.',
        ),
        SizedBox(height: 16),
        _InfoBox(
          icon: Icons.lightbulb_outline,
          text:
              'Astuce : dans Claude.ai, cherche l\'icône ⚡ dans la barre de '
              'message pour accéder aux prompts Productivitwo préconçus '
              '(programme du jour, bilan semaine, etc.).',
        ),
      ],
    );
  }
}

// ── Onglet Exemples ───────────────────────────────────────────────────────────

class _ExamplesTab extends StatelessWidget {
  final ScrollController scroll;
  const _ExamplesTab({required this.scroll});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(20),
      children: const [
        _SectionTitle('Planning du jour'),
        _ExampleCard(
          prompt: 'Planifie ma journée de demain',
          result:
              'Claude regarde ton calendrier Google, tes blocs de journée, '
              'tes objectifs en cours et ce que tu n\'as pas fait cette semaine. '
              'Il crée un programme optimisé directement dans Productivitwo.',
        ),
        _ExampleCard(
          prompt: 'Je n\'ai que 2h ce matin, qu\'est-ce que je devrais faire en priorité ?',
          result:
              'Claude analyse tes tâches urgentes, les jalons Gantt proches '
              'et ton historique récent pour te proposer le meilleur usage de ces 2h.',
        ),
        SizedBox(height: 16),
        _SectionTitle('Projets Gantt'),
        _ExampleCard(
          prompt: 'Crée un plan de lancement produit sur 3 mois',
          result:
              'Claude génère un Gantt complet avec phases, tâches et jalons, '
              'et le pousse directement dans Productivitwo.',
        ),
        _ExampleCard(
          prompt: 'Ajoute une tâche "Newsletter hebdo" en juin dans mon Gantt Marketing',
          result:
              'Claude lit ton Gantt existant, ajoute la tâche dans la bonne '
              'phase et met à jour le projet.',
        ),
        SizedBox(height: 16),
        _SectionTitle('Coaching & ajustements'),
        _ExampleCard(
          prompt: 'Fais mon bilan de la semaine',
          result:
              'Claude compare ce que tu avais prévu avec ce que tu as '
              'vraiment fait, identifie les blocages récurrents et '
              'propose 3 actions prioritaires pour la semaine prochaine.',
        ),
        _ExampleCard(
          prompt: 'Mon objectif de sport est trop ambitieux, adapte-le',
          result:
              'Claude regarde ton historique de temps loggué, compare à '
              'ton objectif et ajuste à un niveau réaliste basé sur tes '
              '7 derniers jours.',
        ),
        _ExampleCard(
          prompt:
              'Crée une routine muscu 4x/semaine pour ma phase Intensification du Gantt',
          result:
              'Claude crée la routine avec les dates de début/fin de la '
              'phase Gantt — elle expirera automatiquement à la fin de la phase.',
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

// ── Onglet Fonctionnalités ────────────────────────────────────────────────────

class _FeaturesTab extends StatelessWidget {
  final ScrollController scroll;
  const _FeaturesTab({required this.scroll});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(20),
      children: const [
        _SectionTitle('Ce que Claude peut faire'),
        _FeatureRow(
          icon: Icons.visibility_outlined,
          title: 'Lire ton contexte',
          body:
              'Domaines, activités + objectifs, routines actives, goals GTD, '
              'et tout le réalisé des 7 derniers jours (actions faites, '
              'temps loggué, taux de complétion des habitudes).',
        ),
        _FeatureRow(
          icon: Icons.calendar_today_outlined,
          title: 'Planifier ta journée',
          body:
              'Crée un programme personnalisé en tenant compte de ton '
              'calendrier Google, de tes blocs et de tes objectifs. '
              'Ajoute aussi les créneaux dans Google Calendar.',
        ),
        _FeatureRow(
          icon: Icons.account_tree_outlined,
          title: 'Gérer les Gantts',
          body:
              'Crée, modifie et supprime des projets Gantt. '
              'Lit tes projets existants pour les faire évoluer. '
              'Aligne ton planning quotidien sur les phases et jalons.',
        ),
        _FeatureRow(
          icon: Icons.repeat_outlined,
          title: 'Créer des routines temporelles',
          body:
              'Crée des routines liées à une période ou à une phase Gantt. '
              'Elles apparaissent dans ton plan quotidien iOS et '
              'expirent automatiquement à la date de fin.',
        ),
        _FeatureRow(
          icon: Icons.tune_outlined,
          title: 'Ajuster les objectifs',
          body:
              'Modifie les objectifs quotidiens de tes activités '
              '(temps ou fréquence) basé sur ta réalité récente.',
        ),
        SizedBox(height: 16),
        _SectionTitle('Limites actuelles'),
        _InfoBox(
          icon: Icons.info_outline,
          text:
              '• Claude voit les 7 derniers jours d\'activité (pas l\'historique complet)\n'
              '• La sync iOS nécessite la connexion Apple Sign In pour fonctionner entre plusieurs appareils\n'
              '• Les modifications de Claude apparaissent dans Productivitwo iOS à la prochaine ouverture de l\'app',
        ),
        SizedBox(height: 24),
      ],
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _Step extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String body;
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(number,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(body,
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.65),
                      height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  final String prompt;
  final String result;
  const _ExampleCard({required this.prompt, required this.result});

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Prompt copié'),
          duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prompt (copiable)
          InkWell(
            onTap: () => _copy(context, prompt),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 14, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$prompt"',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(Icons.copy_outlined,
                      size: 14,
                      color: cs.onSurface.withOpacity(0.3)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
          // Résultat
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_forward,
                    size: 13,
                    color: cs.onSurface.withOpacity(0.35)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.6),
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _FeatureRow(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.6),
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.7),
                    height: 1.5)),
          ),
        ],
      ),
    );
  }
}
