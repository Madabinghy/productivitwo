import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.sync.signInWithApple();

      // ── À partir d'ici, la connexion Apple a RÉUSSI. ────────────────────────
      // La suite (entitlements + migration des données) ne doit jamais faire
      // ressembler un succès de connexion à un échec : on l'isole et on avale
      // les erreurs non bloquantes (sinon un échec d'écriture Firestore sur un
      // compte neuf affiche « une erreur est survenue » → rejet App Review).
      try {
        await ProManager.loginUser(result.uid);
        if (!result.isNew) {
          final remote = await widget.sync.pull();
          if (remote != null && mounted) {
            await FileStore().save(remote);
          }
        } else {
          await widget.sync.pushAll(widget.state);
        }
      } catch (e) {
        debugPrint('Sync post-connexion Apple échouée (non bloquant) : $e');
      }

      // Recharger l'app : la connexion est valide quoi qu'il arrive ensuite.
      if (mounted) widget.onDataChanged();
    } on SignInWithAppleAuthorizationException catch (e) {
      // Annulation par l'utilisateur → pas d'erreur affichée.
      if (e.code == AuthorizationErrorCode.canceled) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connexion Apple impossible. Réessaie.';
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.code == 'account-exists-with-different-credential'
              ? 'Un compte existe déjà avec cet email. Connecte-toi par lien email.'
              : 'Connexion impossible. Réessaie.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connexion impossible. Réessaie.';
        });
      }
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
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 18),
            ),
            title: const Text('Compte Apple connecté',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: email != null
                ? Text(email, style: const TextStyle(fontSize: 12))
                : const Text('Synchronisation active'),
            trailing: TextButton(
              onPressed: _signOut,
              child: Text('Déconnecter',
                  style: TextStyle(color: cs.onSurface.withOpacity(.45), fontSize: 13)),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(Icons.apple, color: cs.onSurface),
          title: const Text('Connecter avec Apple'),
          subtitle: const Text('Sauvegardez et restaurez vos données'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _signIn,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
              ),
            ),
          ),
      ],
    );
  }
}
