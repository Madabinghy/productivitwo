# LocaDemo — Gestion de locations saisonnières (démo)

Application de démonstration **autonome** pour gérer 2 appartements en location courte durée.
Un seul fichier `index.html`, aucune dépendance, aucun build. Les données sont sauvegardées
dans le `localStorage` du navigateur.

> ⚠️ Sans rapport avec l'app Productivitwo — c'est une démo isolée placée dans `demo/`.

## Lancer

Ouvrir `index.html` dans un navigateur (double-clic), ou servir le dossier :

```bash
cd demo/locations-saisonnieres
python3 -m http.server 8000   # puis http://localhost:8000
```

## Fonctionnalités

- **Tableau de bord** : revenu net du mois, taux d'occupation, paiements à venir, prochaines arrivées.
- **Calendrier** : vue mensuelle des séjours, couleur par logement.
- **Réservations** : ajout / édition / suppression, avec **heure d'arrivée**, nombre de voyageurs,
  plateforme, statut, détection de conflit de dates.
- **Paiements** : liste des paiements à venir et encaissés. **Calcul automatique du montant net
  à recevoir** = prix total − commission plateforme (Airbnb ≈ 3 %, Booking.com ≈ 15 %, modifiable).
- **Récap mensuel** : synthèse **par logement et par mois** (réservations, nuitées, occupation,
  brut, commissions, net, prix moyen/nuit) + total consolidé.

## Connexion aux plateformes (Airbnb / Booking.com) — ce qui est réellement possible

Airbnb et Booking **ne fournissent pas d'API publique de réservations aux hôtes particuliers**.
L'accès API direct (récupérer réservations, prix, messages) est réservé aux **channel managers
agréés** (Beds24, Smoobu, Lodgify, Hostaway…). Pour un hôte individuel, deux voies réalistes :

### 1. Synchronisation iCal (la plus simple)
Chaque plateforme expose une URL d'export `.ics` :
- Airbnb : *Calendrier → Disponibilité → Synchroniser les calendriers → Exporter le calendrier*
- Booking : *Extranet → Tarifs et disponibilité → Synchroniser les calendriers*

L'iCal donne **les dates de séjour** (et parfois un nom/identifiant voyageur). Il **ne contient
ni le prix, ni le montant net, ni l'heure d'arrivée**. Un import iCal nécessite un petit
service serveur (les `.ics` ne sont pas accessibles directement en JavaScript navigateur à cause
du CORS).

### 2. Lecture des emails de réservation
Airbnb et Booking envoient un email à chaque réservation (voyageur, dates, prix, parfois heure
d'arrivée). Les parser permet de récupérer **prix + heure d'arrivée + montant**, que l'iCal n'a pas.
Plus complet, mais plus fragile (format des emails variable).

### Pour passer cette démo en production
Recommandation : **iCal pour les dates/occupation** + **parsing email (ou saisie manuelle) pour
les montants et heures d'arrivée**, le tout côté serveur. C'est l'approche utilisée par la plupart
des outils du marché pour les hôtes indépendants. Dis-le-moi si tu veux que je branche cette partie.
