# Contrôle Sonos depuis la notch — conception

Date : 2026-10-31 · Branche de départ : `feature/agents` (fork Crollin/boring.notch)

## Pourquoi

Quand Spotify joue sur une Sonos, les touches volume du Mac ne font rien, et changer de pièce oblige à ouvrir l'app Sonos ou Home Assistant. C'est, selon l'utilisateur, le plus gros frein des Sonos. Cas typique : la musique joue dans la cuisine, il part au bureau et veut qu'elle le suive, puis régler le volume — sans quitter ce qu'il fait.

La notch devient l'endroit pour : régler le volume de la Sonos qui joue, changer de pièce, grouper des pièces.

## Objectifs

1. **Volume** de la Sonos active depuis la notch et depuis les **touches volume du Mac**.
2. **Changer de pièce** : par défaut on *déplace* la musique (elle quitte la pièce actuelle). Au choix, on *ajoute* une pièce pour jouer à plusieurs.
3. **Volume par pièce** quand plusieurs pièces jouent.
4. **Favoris** : combinaisons de pièces nommées (ex. « Rez-de-chaussée » = Cuisine + Salon), un tap y envoie la musique.
5. **Dernier groupe** : entrée « Revenir à : Cuisine + Bureau » pour restaurer le groupe précédent en un tap.
6. Zéro configuration : les Sonos sont découvertes automatiquement.

## Non-objectifs

- Passer par Home Assistant, l'API cloud Sonos ou un compte (décidé : local uniquement).
- Contrôle hors du réseau de la maison.
- Autres sources que Spotify (Apple Music/AirPlay vers Sonos, radio Sonos…) comme *déclencheur* de la ligne Sonos.
- Lecture/pause/titre via Sonos : le lecteur existant (Spotify) le fait déjà.
- Onglet Sonos dédié (option écartée en maquette).

## Anti-objectifs (raté même si ça « marche »)

- Les touches volume ne règlent plus le Mac quand Spotify joue en local.
- Déplacer la musique relance le morceau au début ou arrête la lecture (une courte coupure d'une ou deux secondes est acceptée, voir plus bas).
- Messages d'erreur / alertes quand on est hors de la maison ou que les Sonos sont injoignables : dans ce cas, la ligne Sonos est simplement absente.
- Configuration manuelle (IP, noms) nécessaire pour démarrer.

## Ce qui a été décidé avec l'utilisateur

### Interface (maquettes validées : placement A, sélecteur B)

- **Dans le lecteur musique** de la vue d'accueil (pas un onglet), sous les contrôles : une ligne
  `[Cuisine ▾]  🔈 ───●─── 🔊`
  - la pastille affiche la pièce active, ou « Cuisine + Bureau » si groupe ;
  - le curseur règle le volume principal.
- **Tap sur la pastille → liste déroulante** :
  - en haut : favoris, puis « Revenir à : … » (si un groupe précédent existe et diffère de l'actuel) ;
  - puis chaque pièce : `☑ Cuisine   ───●── 45`
    - **tap sur le nom** = déplacer : la musique ne joue plus que là ;
    - **tap sur la case** = ajouter/retirer la pièce du groupe ;
    - le **mini-curseur par pièce** n'apparaît que pour les pièces qui jouent, quand il y en a plusieurs.
- La ligne n'apparaît **que quand Spotify joue sur une Sonos**. Sinon le lecteur reste identique à aujourd'hui.

### Touches volume du Mac

Quand Spotify joue sur une Sonos : les touches volume (et mute) règlent la Sonos, et l'indicateur volume de la notch (sneak peek) l'affiche avec le nom de la pièce. Sinon : comportement actuel inchangé (volume du Mac).

### Technique

- Parler **directement aux Sonos sur le réseau local** (validé par l'utilisateur).
- **Volume principal (curseur + touches) via l'API Sonos** : `GroupRenderingControl#SetGroupVolume` sur le coordinateur, qui marche pour une pièce seule comme pour un groupe et reste cohérent avec les curseurs par pièce. *(Choix de Claude, révisé après relecture : le test utilisateur `set sound volume` via Spotify a fonctionné sur une seule pièce, mais son effet sur un groupe est incertain ; l'API Sonos étant de toute façon nécessaire, on n'utilise qu'une source de vérité.)*
- L'API locale Sonos sert aussi à : détecter la pièce active, lister les pièces, grouper/dégrouper/déplacer, volume par pièce.
- **Indépendant de la source musique choisie dans les Paramètres** : `MusicManager` n'instancie qu'un contrôleur (`Defaults[.mediaController]`, `nowPlaying` par défaut). Le module Sonos lit lui-même l'état de Spotify (AppleScript : en cours de lecture, titre, artiste) si Spotify est lancé, sans dépendre de `SpotifyController`. *(Choix de Claude.)*
- **« Revenir à »** = le dernier groupe *différent* du groupe actuel observé pendant que Spotify jouait sur Sonos, que le changement vienne de la notch ou de l'app Sonos. *(Choix de Claude.)*
- Un **réglage on/off** dans les Paramètres. *(Choix de Claude.)*

## Contraintes et faits du code existant

- App macOS SwiftUI, **sandboxée** (`boringNotch.entitlements` : `network.client` et `network.server` déjà présents).
- macOS demandera l'autorisation **Réseau local** : ajouter `NSLocalNetworkUsageDescription` et `NSBonjourServices` (`_sonos._tcp`) dans `Info.plist`.
- `boringNotch/observers/MediaKeyInterceptor.swift` intercepte déjà les touches son (`handleKeyPress` → `VolumeManager`), uniquement si `Defaults[.hudReplacement]` est actif et l'Accessibilité accordée. C'est le point d'aiguillage Mac ↔ Sonos. Si le remplacement HUD est désactivé, les touches ne peuvent pas être redirigées : à signaler dans le réglage Sonos.
- `MusicManager` / `SpotifyController` donnent déjà titre, état de lecture et volume Spotify. Spotify **n'indique pas** sur quel appareil il joue.
- Le lecteur a déjà un bouton volume (`VolumeControlView` dans `components/Notch/NotchHomeView.swift`).
- `NotchModule` = un onglet ; la fonction Sonos n'est **pas** un onglet. Ranger le code dans `boringNotch/modules/Sonos/` (même style que `modules/Agents/`), démarré au lancement, et injecter la ligne dans le lecteur.

## Pistes techniques (recherche, à confirmer en implémentant)

- **Découverte** : Bonjour `_sonos._tcp` (via `NWBrowser`) plutôt que SSDP multicast.
- **Contrôle** : SOAP UPnP sur `http://<ip>:1400` :
  - `ZoneGroupTopology#GetZoneGroupState` : groupes, coordinateurs, noms de pièces ;
  - `AVTransport#GetTransportInfo` / `GetPositionInfo` : état de lecture et morceau en cours ;
  - `RenderingControl#Get/SetVolume` : volume par pièce ;
  - `GroupRenderingControl#SetGroupVolume` : volume principal (pièce seule ou groupe) ;
  - ajouter une pièce : `AVTransport#SetAVTransportURI` avec `x-rincon:<UUID coordinateur>` ;
  - retirer une pièce : `AVTransport#BecomeCoordinatorOfStandaloneGroup` ;
  - déplacer : ajouter la cible → `AVTransport#DelegateGroupCoordinationTo` (cible) → retirer l'ancienne pièce. À vérifier sur l'installation réelle. **Décidé avec l'utilisateur** : si Spotify Connect se coupe pendant le déplacement, une courte coupure (1–2 s) est acceptée, à condition que la lecture reprenne seule dans la nouvelle pièce, au même endroit du morceau. Pas de repli « ajouter puis muter l'ancienne pièce ».
- **Détection de la pièce active** : groupe Sonos en lecture dont le morceau correspond au titre/artiste de Spotify. Rafraîchissement par polling léger tant que Spotify joue (les abonnements UPnP GENA sont une amélioration possible, non requise).

## Laissé au constructeur

- Fréquence de polling, timeouts, cache de la topologie.
- Stockage des favoris et du dernier groupe (`Defaults`, identifiés par UUID de pièce plutôt que par nom).
- Création/édition des favoris : depuis la liste (« Enregistrer ce groupe… ») et/ou les Paramètres.
- Pas du volume au clavier (reprendre le pas actuel de `VolumeManager`, y compris Option+Shift).
- Comportement de mute sur Sonos (mute Sonos du groupe vs volume 0).
- Animations et détails visuels, dans le style du lecteur existant.
