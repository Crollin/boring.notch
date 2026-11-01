# Activités autour de la notch — conception

Date : 2026-11-01 · Branche : `feature/live-activities` (depuis `feature/agents`, fork Crollin/boring.notch)

## Pourquoi

Inspiré des « Live Activities » de Droppy (getdroppy.app/features/live-activities) : de petites pastilles apparaissent
à côté de la notch fermée tant qu'une chose compte, puis s'effacent. Aujourd'hui seule la pastille des agents existe,
codée en dur dans `ContentView`. L'utilisateur veut surtout savoir **quand le micro ou la caméra sont utilisés**
(vie privée) **et depuis combien de temps** (durée d'appel), suivre ses **téléchargements**, et pouvoir empêcher la veille.

## Objectifs

1. **Socle** : deux emplacements, à gauche et à droite de la notch fermée. Les activités visibles sont triées par
   priorité ; les deux premières s'affichent (1re à gauche, 2e à droite), les autres attendent. La pastille agents
   existante devient une activité comme les autres, rendu inchangé.
2. **Micro / caméra** : point rouge (micro) / vert (caméra) + durée depuis l'activation. Info-bulle : app(s) qui utilisent le micro.
3. **Téléchargements** : anneau de progression (indéterminé si la taille finale est inconnue), puis ✓ quelques secondes.
   Le fichier terminé est ajouté à l'étagère. Clic : affiche le fichier dans le Finder.
4. **Rester éveillé** : empêche la veille (1 h, 2 h, 4 h, indéfiniment). Pastille ☕ + temps restant ; clic = arrêter.
   Déclenché depuis le menu de l'icône de barre des menus et par un raccourci clavier (sans défaut, réglable).
5. **Commande terminal terminée** : une commande zsh de plus de 30 s affiche ✓/✗ + nom + durée, 6 s, uniquement si
   le terminal n'est pas l'app au premier plan. Clic : ramène le terminal.
6. **Disque externe monté** : pastille nom du disque + bouton éjecter, 8 s.
7. **Casque Bluetooth connecté** (Nothing Ear (3), ou tout appareil audio Bluetooth) : nom, 5 s. Clic : en fait la
   sortie audio par défaut.

## Non-objectifs

- Batterie des Nothing Ear : macOS ne l'expose pas (vérifié : aucun champ batterie dans `system_profiler`).
- Home Assistant, CI GitHub, toute connexion réseau sortante (décidé : tout reste local).
- Time Machine, captures d'écran (CleanShot X a déjà sa vignette).
- Mode « Dynamic Island » pour écrans sans notch ; carte dépliée par activité ; réglage de priorité par l'utilisateur.
- Pomodoro / minuteur, prochaine réunion, VPN : non retenus (l'utilisateur a priorisé le reste).

## Anti-objectifs

- Une pastille masque le micro ou la caméra actifs : ils ont toujours la priorité la plus haute.
- Le hook zsh ralentit ou casse le terminal quand l'app est fermée (il doit échouer en silence, comme `agent-hook.sh`).
- Les pastilles restent affichées notch ouverte, ou traînent par-dessus la barre d'onglets à l'ouverture.
- Une nouvelle autorisation système (TCC) est demandée juste pour afficher une pastille.

## Décisions

### Socle (choix de Claude)

```swift
protocol NotchActivity {           // une source = un ObservableObject singleton
    var id: String { get }
    var priority: Int { get }      // plus grand = plus important
    var isVisible: Bool { get }
    @MainActor func pill(height: CGFloat) -> AnyView
}
```

- Un `ActivityCenter` (`ObservableObject`) agrège les sources, republie leurs changements, expose `visible` (triées,
  max 2). L'overlay existant de `ContentView` (aujourd'hui `AgentsPill`) affiche `visible[0]` à gauche, `visible[1]`
  à droite. Le clic est porté par la pastille elle-même (chaque source sait quoi faire).
- Priorités fixes : micro/caméra 100 · agents 80 (attention 95) · téléchargement 60 · éphémères (commande, disque,
  casque) 50 · rester éveillé 20.
- Les activités éphémères s'effacent seules après leur durée ; une nouvelle du même type remplace l'ancienne.
- Réglages : une section « Activités » avec un interrupteur par activité (toutes actives par défaut, agents inclus)
  et l'option « Ajouter les téléchargements à l'étagère » (activée).

### Micro / caméra

- Micro : CoreAudio, `kAudioDevicePropertyDeviceIsRunningSomewhere` sur les périphériques d'entrée, écouté par
  listener. Apps : `kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput` +
  `kAudioProcessPropertyBundleID` (vérifié hors sandbox ; si la sandbox bloque, l'info-bulle n'a simplement pas d'app).
- Caméra : CoreMediaIO, `kCMIODevicePropertyDeviceIsRunningSomewhere` sur chaque caméra, interrogé toutes les 2 s
  (ponytail : polling, listener CMIO si besoin). L'app sait déjà ouvrir la caméra (miroir) : on exclut ce cas en
  ignorant la caméra quand le miroir de l'app est actif.
- Durée : depuis le passage à « utilisé » (micro ou caméra) ; remise à zéro quand plus rien n'est utilisé.

### Téléchargements

- Surveillance de `~/Downloads` (droit sandbox déjà présent) : `DispatchSource` sur le dossier + interrogation 1 s
  tant qu'un téléchargement est en cours.
- Safari : paquet `*.download`, progression lue dans son `Info.plist` (`DownloadEntryProgressBytesSoFar` /
  `DownloadEntryProgressTotalToLoad`). Chrome/Arc/Brave : `*.crdownload`, Firefox : `*.part` → anneau indéterminé.
- Fin = le fichier temporaire disparaît et le fichier final existe → ✓ 4 s, ajout à l'étagère (bookmark, comme le
  glisser-déposer).

### Rester éveillé

- `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep)` — l'écran peut s'éteindre, le Mac ne
  dort pas (choix de Claude ; c'est l'usage « laisser tourner une tâche »).

### Commande terminal

- `scripts/cmd-hook.zsh`, à sourcer depuis `~/.zshrc` : `preexec` note l'heure et la commande, `precmd` envoie
  `{"kind":"command","payload":{"command":…,"exit_code":…,"duration":…},"app":$__CFBundleIdentifier}` sur
  `~/.bn.sock` via `nc -U` en arrière-plan, si durée ≥ 30 s. Le serveur socket des agents route `kind == "command"`.

### Disque externe

- `NSWorkspace.didMountNotification` / `didUnmountNotification`, volumes `volumeIsRemovable || volumeIsEjectable`
  hors images disque internes. Éjecter : `NSWorkspace.unmountAndEjectDevice(at:)`.

### Casque Bluetooth

- CoreAudio : un nouveau périphérique de sortie au transport Bluetooth apparaît dans `kAudioHardwarePropertyDevices`
  → pastille. Clic : `kAudioHardwarePropertyDefaultOutputDevice` = ce périphérique. Aucune autorisation Bluetooth.

## Laissé au constructeur

Rendu exact des pastilles (dans l'esprit `AgentBubble` : fond noir, hauteur de la notch fermée), animations
d'apparition, découpage des fichiers sous `boringNotch/modules/Activities/`.
