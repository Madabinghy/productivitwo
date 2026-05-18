import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/pro_manager.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/storage.dart';

/// Bouton "Connecter avec Apple" / état connecté.
/// À placer dans les settings. Callback [onSignedIn] appelé avec le nouvel uid
/// si c'est un compte existant (pour télécharger les données Firestore).
class AppleSignInTile extends StatefulWidget {
  final FirestoreSync sync;
  final AppState state;
  final VoidCallback onDataChanged;

  const AppleSignInTile({
    super.key,
    required this.sync,
    required this.state,
    required this.onDataChanged,
  });

  @override
  State<AppleSignInTile> createState() => _AppleSignInTileState();
}

class _AppleSignInTileState extends State<AppleSignInTile> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final result = await widget.sync.signInWithApple();

      // Lier RevenueCat au compte
      await ProManager.loginUser(result.uid);

      if (!result.isNew) {
        // Compte existant → télécharger les données Firestore
        final remote = await widget.sync.pull();
        if (remote != null && mounted) {
          // Remplace les données locales par celles du compte
          await FileStore().save(remote);
          widget.onDataChanged();
        }
      } else {
        // Nouveau compte → uploader les données locales vers Firestore
        await widget.sync.pushAll(widget.state);
      }

      if (mounted) setState(() => _loading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte connecté ✓')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
            'Vos données restent sur cet appareil. '
            'Reconnectez-vous pour les synchroniser.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    await widget.sync.signOut();
    await ProManager.logoutUser();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAnon = widget.sync.isAnonymous;
    final email = widget.sync.appleEmail;

    if (_loading) {
      return const ListTile(
        leading: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Connexion en cours…'),
      );
    }

    if (!isAnon) {
      return ListTile(
        leading: Icon(Icons.apple, color: cs.onSurface),
        title: const Text('Compte Apple connecté'),
        subtitle: email != null ? Text(email) : null,
        trailing: TextButton(
          onPressed: _signOut,
          child: Text('Déconnecter',
              style: TextStyle(color: cs.onSurface.withOpacity(.5))),
        ),
      );
    }

    return ListTile(
      leading: Icon(Icons.apple, color: cs.onSurface),
      title: const Text('Connecter avec Apple'),
      subtitle: const Text('Sauvegardez et restaurez vos données'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _signIn,
    );
  }
}
