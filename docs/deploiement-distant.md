# Déploiement distant — web + Cloud Functions

Pipeline GitHub Actions pour déployer **sans Mac**, depuis le téléphone.
Fichier : `.github/workflows/deploy-web-functions.yml`

## Déclencheurs

| Déclencheur | Effet |
|-------------|-------|
| **Manuel** (`workflow_dispatch`) | Déploie `main` à la demande (depuis l'app GitHub mobile) |
| **Tag `v*` poussé** | Déploie ce tag (flux release) |
| **Cron 3h** | Reprise idempotente : redéploie le dernier tag `v*` s'il n'a jamais été déployé. Sans tag = ne fait rien. |

Jamais déclenché sur un simple push de branche → rien ne part à chaque merge.

## Ce qui se déploie

- **web** → Firebase Hosting (`flutter build web` puis deploy)
- **functions** → Cloud Functions (`npm ci` → `tsc` → deploy)

Le mobile (iOS/Android) reste hors de ce pipeline : builds manuels via Codemagic / Xcode Cloud.

## Sécurité

- Auth via service account `gh-deployer` (secret `FIREBASE_SERVICE_ACCOUNT`).
- **Pas de `--force` sur le déploiement functions** : un déploiement qui supprimerait des
  fonctions présentes en prod mais absentes de la source **échoue** au lieu de les détruire.

## Notifications

Quand une PR est ouverte, la Cloud Function `githubWebhook` envoie une notif push
dans Productivitwo (vérif signature HMAC `GITHUB_WEBHOOK_SECRET` → FCM au dev).
But : valider les PR des agents depuis le téléphone.

## Leçon importante

`main` (git) et la prod (Firebase) sont deux choses distinctes. Les Cloud Functions et le web
doivent toujours être **commités** : tout déployer depuis un working tree non commité fait
diverger git de la prod et expose à une perte de code.
