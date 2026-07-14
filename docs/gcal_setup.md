# Google Agenda natif — mise en route (une fois)

Le programme du jour (blocs, défis 🔥, événements `add_event`) est synchronisé
dans le Google Agenda de l'utilisateur **sans passer par le connecteur
Claude** : OAuth côté serveur, refresh token stocké dans Firestore
(`gcal_tokens/{uid}`, admin uniquement), synchronisation automatique par
trigger Firestore sur `users/{uid}/daily_schedules/{date}`.

## 1. Console Google Cloud (projet Firebase Productivitwo)

1. **Activer l'API** : APIs & Services → Library → « Google Calendar API » → Enable.
2. **Écran de consentement OAuth** (s'il n'existe pas déjà) : External,
   nom « Productivitwo », scopes : `calendar.events`, `openid`, `email`.
   En mode *Testing*, ajouter les comptes Google des testeurs dans « Test users »
   (sinon Google refuse la connexion).
3. **Identifiants** : APIs & Services → Credentials → Create credentials →
   OAuth client ID → type **Web application** :
   - Authorized redirect URI (EXACTE) :
     `https://gcaloauthcallback-dzos75b65q-uc.a.run.app`
   - Noter le **Client ID** et le **Client secret**.

## 2. Secrets Cloud Functions

```bash
cd functions
firebase functions:secrets:set GCAL_CLIENT_ID      # coller le Client ID
firebase functions:secrets:set GCAL_CLIENT_SECRET  # coller le Client secret
npm run build
firebase deploy --only functions
```

Trois nouvelles functions : `gcalApi` (status/authUrl/syncDay/setAutoSync/
disconnect, Bearer), `gcalOauthCallback` (retour navigateur, publique),
`gcalOnScheduleWrite` (trigger Firestore → sync).

## 3. Côté utilisateur

Paramètres → **Google Agenda** → « Connecter mon Google Agenda » → consentement
dans le navigateur → retour dans l'app. C'est tout : chaque écriture du
programme (app, MCP `schedule_day`/`add_event`, défis ORION) met l'agenda à
jour — création, déplacement d'heure, suppression.

## Garanties

- Les événements sont taggés `pwo=1` / `pwoBlockId` / `pwoDate`
  (extendedProperties privées) : la sync ne touche **jamais** les événements
  personnels de l'agenda.
- Jours passés jamais resynchronisés (l'agenda n'est pas un journal).
- Blocs supprimés/sautés → événements retirés ; sync idempotente (diff).
- Tokens invisibles côté client : `gcal_tokens` et `gcal_oauth_states` sont
  des collections racine sans règle Firestore → accès client refusé par
  défaut, admin SDK uniquement.
- Déconnexion : révocation du token côté Google (best-effort) + suppression du
  doc ; les événements déjà créés restent.
