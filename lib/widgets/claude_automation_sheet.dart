import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/claude_link.dart';
import 'package:productivitwo_v1/widgets/gcal_settings_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

/// Paramètres → « Automatiser avec Claude » (maquette Réorganiser avec
/// Claude, cadre 3). Deux automatisations prêtes à créer dans LE Claude de
/// l'utilisateur + le texte brut à coller soi-même.
Future<void> showClaudeAutomationSheet(BuildContext context,
    {required FirestoreSync sync}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ClaudeAutomationSheet(sync: sync),
  );
}

class _ClaudeAutomationSheet extends StatefulWidget {
  final FirestoreSync sync;
  const _ClaudeAutomationSheet({required this.sync});

  @override
  State<_ClaudeAutomationSheet> createState() => _ClaudeAutomationSheetState();
}

class _ClaudeAutomationSheetState extends State<_ClaudeAutomationSheet> {
  // Agenda synchronisé par l'app → les prompts demandent à Claude de ne pas
  // écrire dans Google Agenda (un seul écrivain, pas de doublons).
  bool gcalNative = false;

  @override
  void initState() {
    super.initState();
    gcalNativeSyncActive(widget.sync).then((v) {
      if (mounted && v) setState(() => gcalNative = true);
    });
  }

  Future<void> _open(BuildContext context, ClaudeAutomation a) async {
    final ok = await launchUrl(claudeNewUri(a.prompt), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: a.prompt));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossible d\'ouvrir Claude — demande copiée, colle-la dans Claude.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = claudeAutomations(gcalNative: gcalNative);
    final muted = TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.65), height: 1.35);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome, size: 20),
              const SizedBox(width: 8),
              Text('Automatiser avec Claude',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            Text(
                'Les tâches planifiées tournent dans ton Claude, avec ton connecteur Productivitwo. '
                'L\'app ne fait qu\'ouvrir Claude avec la demande déjà écrite.',
                style: muted),
            const SizedBox(height: 16),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 24),
              Text(items[i].title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(items[i].subtitle, style: muted),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: i == 0
                    ? FilledButton.icon(
                        onPressed: () => _open(context, items[i]),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Créer la tâche dans Claude'))
                    : OutlinedButton.icon(
                        onPressed: () => _open(context, items[i]),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Créer la tâche dans Claude')),
              ),
            ],
            const Divider(height: 28),
            const Text('Le texte, si tu préfères le coller toi-même',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: a.prompt));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('« ${a.title} » copié'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(a.prompt,
                                style: const TextStyle(fontSize: 12.5, height: 1.4))),
                        const SizedBox(width: 8),
                        Icon(Icons.copy_rounded, size: 16, color: cs.onSurface.withOpacity(.5)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
