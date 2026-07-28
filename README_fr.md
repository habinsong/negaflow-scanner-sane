<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">Module SANE pour scanners de film, destiné à negaflow sur macOS</p>

<p align="center">
  <a href="#prérequis"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 ou version ultérieure"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 ou version ultérieure"></a>
  <a href="manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="Protocole scanner negaflow v2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0 ou ultérieure"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <strong>Français</strong> ·
  <a href="README_de.md">Deutsch</a>
</p>

---

**negaflow-scanner-sane** relie [negaflow](https://github.com/habinsong/negaflow) aux scanners de film utilisables avec SANE.<br>
Il lance `scanimage`, lit les options réellement publiées par le scanner, puis renvoie les informations de l'appareil, ses capacités, la progression et les chemins TIFF par le protocole scanner negaflow v2.

Ce n'est pas une seconde interface de numérisation, mais un module en ligne de commande à installer.<br>
Une fois installé et approuvé, il s'utilise depuis negaflow.

Le module et l'application principale sont deux programmes distincts.<br>
Tout le code propre à SANE reste dans ce dépôt sous GPL-2.0-or-later.<br>
negaflow, sous Apache-2.0, ne communique avec lui que par un processus séparé, des arguments de ligne de commande, des tubes et du JSON.

## Fonctions

- Détection des scanners avec `scanimage -L`
- Construction des commandes à partir du résultat actuel de `scanimage -A`
- Aperçu et numérisation complète sans remplacer une valeur demandée par une valeur voisine
- Contrôle de la résolution, du mode couleur, de la profondeur, des dimensions et du format TIFF
- Zone en millimètres uniquement lorsque le backend en fournit les plages nécessaires
- Acquisition d'un canal infrarouge séparé uniquement lorsque le backend peut réellement le produire
- Multi-exposition matérielle uniquement si `--scan-exposure-time` couvre le plan d'exposition requis
- Arrêt du seul processus `scanimage` lancé par l'instance courante du module

Le nom du scanner ne suffit jamais à activer une fonction.<br>
negaflow n'affiche que les options signalées par l'appareil connecté et son backend SANE actif.

## Prérequis

- macOS 14.0 ou version ultérieure pour l'installation actuelle de negaflow et Homebrew
- negaflow
- `sane-backends` standard de Homebrew pour les scanners ordinaires
- macOS 26 ou version ultérieure uniquement pour le parcours Nikon Coolscan corrigé
- Swift 5.9 ou version ultérieure uniquement pour compiler les sources

`Package.swift` conserve une cible de déploiement macOS 13 pour l'exécutable seul.<br>
Le parcours complet décrit ici commence à macOS 14 afin de suivre les prérequis actuels de negaflow et Homebrew.

## Installation

### 1. Installateur tout-en-un

Si les Xcode Command Line Tools ne sont pas encore présents, installez-les d'abord :

```bash
xcode-select --install
```

Quatre programmes d'installation sont publiés. Utilisez la version standard pour les scanners
SANE ordinaires et la version Coolscan séparée pour Nikon Coolscan sous macOS 26 ou ultérieur.

| Programme d'installation | Parcours SANE | Binaire du module |
|---|---|---|
| `negaflow-scanner-sane-1.0.1-macos-arm64-installer.dmg` | Standard, macOS 14+ | `arm64` uniquement |
| `negaflow-scanner-sane-1.0.1-macos-universal-installer.dmg` | Standard, macOS 14+ | `arm64` + `x86_64` |
| `negaflow-scanner-sane-1.0.1-coolscan-macos26-arm64-installer.dmg` | Coolscan corrigé, macOS 26+ | `arm64` uniquement |
| `negaflow-scanner-sane-1.0.1-coolscan-macos26-universal-installer.dmg` | Coolscan corrigé, macOS 26+ | `arm64` + `x86_64` |

Le DMG standard contient `Install negaflow Scanner.pkg`; le DMG Coolscan contient
`Install negaflow Scanner for Coolscan.pkg`.

La version standard installe `sane-backends` de Homebrew. La version Coolscan compile
`sane-backends-negaflow` depuis SANE 1.4.0 officiel avec uniquement le correctif upstream
d'allocation `coolscan2`/`coolscan3`.<br>
Une connexion Internet et un mot de passe d'administrateur sont nécessaires.<br>
Une installation Homebrew existante est réutilisée.

La version standard et macOS antérieur à 26 ne bloquent pas Coolscan. Stock SANE peut fonctionner
sur certains appareils, mais sans ce correctif ; la version Coolscan macOS 26 est le parcours
corrigé pris en charge.

Une modification upstream ultérieure initialise aussi les blocs de paramètres load/eject/reset
de Coolscan3, nécessaires au moins au firmware 1.03 du LS-5000. Elle est volontairement exclue
de ce correctif de deux lignes : le chargement, l'éjection et la réinitialisation du LS-5000
restent donc non vérifiés et peuvent échouer.

À la fin, redémarrez negaflow, ouvrez « Charger le scanner », vérifiez les informations du module et approuvez-le.

### 2. Installation manuelle de Homebrew et SANE

Si Homebrew n'est pas installé, utilisez la commande officielle actuelle :

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Cette commande télécharge et exécute l'installateur Homebrew.<br>
Avant de la lancer, vérifiez que l'URL est exactement `raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`.<br>
Un installateur `.pkg` signé est également proposé sur le [site officiel de Homebrew](https://brew.sh/).

Suivez ensuite les **Next steps** affichées pour ajouter `brew` à l'environnement du shell, ouvrez un nouveau Terminal, puis vérifiez que la commande est disponible :

```bash
brew --version
```

Parcours standard sous macOS 14 ou ultérieur :

```bash
brew install sane-backends
```

Parcours Coolscan corrigé sous macOS 26 ou ultérieur :

```bash
bash scripts/install-patched-sane.sh
export PATH="$(brew --prefix sane-backends-negaflow)/bin:$PATH"
```

Contrôlez la commande installée et sa version :

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends sane-backends-negaflow
```

Quand le keg corrigé existe, le module utilise son chemin absolu ainsi que ses propres dossiers
`etc/sane.d` et `lib/sane`.

### 3. Brancher et vérifier le scanner

Allumez le scanner, branchez-le directement en USB si possible, puis lancez :

```bash
scanimage -L
```

Copiez l'identifiant complet affiché, avec le backend et l'adresse USB, puis examinez les options réellement publiées par cet appareil :

```bash
scanimage -d '<device-id>' -A
```

Un identifiant peut ressembler à `genesys:libusb:001:002`.<br>
Ne recopiez pas cet exemple : utilisez la valeur renvoyée par `scanimage -L` sur le Mac concerné.

`sane-find-scanner` prouve seulement qu'un périphérique USB ou SCSI a été détecté.<br>
Il peut aussi afficher un scanner pour lequel aucun backend SANE utilisable n'existe.<br>
Si l'appareil n'apparaît pas dans `scanimage -L`, ce module ne peut pas l'utiliser.<br>
Vérifiez la liaison USB, la [liste des appareils SANE](https://www.sane-project.org/sane-supported-devices.html) et la documentation du backend avant de continuer.

### 4A. Compiler et installer le module depuis les sources

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

Le script produit une version Release et installe ces deux fichiers :

```text
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

### 4B. Installer une archive ZIP publiée

Décompressez l'archive ZIP, puis lancez l'installateur fourni :

```bash
./install.sh
```

L'installation de l'archive ne demande pas la chaîne d'outils Swift. `install.sh` installe
uniquement le module ; installez d'abord SANE standard ou la version Coolscan macOS 26.

### 5. Approuver et vérifier dans negaflow

Redémarrez negaflow et ouvrez « Charger le scanner ».<br>
Vérifiez le chemin, la version, la licence et les hash du module, puis approuvez-le.<br>
Si l'exécutable ou le manifest change après une mise à jour, negaflow demande une nouvelle approbation.

L'exécutable installé peut aussi être contrôlé directement :

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

Une réponse `{"devices":[...]}` signifie que le module a démarré.<br>
Si `devices` est un tableau vide, le module fonctionne mais SANE n'a renvoyé aucun scanner utilisable.<br>
Réinstaller le module n'ajoute pas la prise en charge absente d'un backend SANE : reprenez le diagnostic à `scanimage -L`.

## Scanners pris en charge

Le tableau suivant décrit des cibles SANE 1.4 connues et les chemins gérés par ce module.<br>
Il ne garantit pas que tous les appareils portant le même nom fonctionneront.<br>
Consultez la [liste SANE actuelle](https://www.sane-project.org/sane-supported-devices.html), puis contrôlez l'appareil connecté avec `scanimage -L` et `scanimage -A`.

| Famille de scanners | Backend SANE | État SANE 1.4 | Chemin du module |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i | `genesys` | Complete | Scanner de film dédié |
| Plustek OpticFilm 7400 v1 | `genesys` | Indiqué Complete, mais les corrections propres au modèle sont postérieures à SANE 1.4.0 | Chemin piloté par les capacités ; résultat matériel stock 1.4.0 non vérifié |
| Plustek OpticFilm 8100, USB `07b3:130c` | `genesys` | Complete | Scanner de film dédié |
| Plustek OpticFilm 8100, USB `07b3:1824` | Aucun | Unsupported | Non considéré comme utilisable |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | Scanner de film dédié |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | Aucun | Unsupported | Non considéré comme utilisable |
| Plustek OpticFilm 120, 120 Pro, 135, 135i, 9000i Ai | Aucun | Unsupported | Non considéré comme utilisable |
| Epson Perfection V700/V750 (GT-X900), V800/V850 (GT-X980) | `epson2` | Good | Source transparente et zone positionnée lorsqu'elles sont signalées |
| Nikon Coolscan LS-2000, LS-40 ED, LS-50 ED, LS-4000 ED, LS-8000 ED | `coolscan3` | Complete à Minimal selon le modèle | Scanner de film dédié |
| Nikon Coolscan LS-5000 ED | `coolscan3` | Non testé dans SANE 1.4 ; peut fonctionner comme le LS-50 | Scanner de film dédié |
| Nikon Coolscan LS-20, LS-30, LS-1000 | `coolscan` | Variable selon le modèle | SCSI uniquement |
| Nikon Coolscan LS-9000 ED | Aucun | Unsupported | Non considéré comme utilisable |
| Reflecta ProScan/CrystalScan/DigitDia et PIE PowerSlide | `pieusb`; anciens modèles SCSI avec `pie` | Variable selon le modèle et son numéro | Uniquement les options signalées |
| Pacific Image PrimeFilm XA, XAs, XA Plus | Aucun | Unsupported | Non considéré comme utilisable |
| Autres scanners de film ou à plat avec transparents | Variable | Variable selon le modèle | Piloté par les capacités, sans repli fondé sur le nom |

### Le nom du produit ne dit rien du matériel

L'OpticFilm 8100 et le 8200i existent chacun sous au moins deux variantes USB portant le même nom.<br>
`07b3:130c` et `07b3:130d` sont pilotés par `genesys` ; `07b3:1824` et `07b3:1825` ne le sont pas,
car ils utilisent une autre puce Genesys qu'aucun backend ne pilote.<br>
Une révision récente vendue sous un ancien nom ne peut pas être corrigée côté SANE : vérifiez le
véritable USB product ID, pas seulement le nom inscrit sur le boîtier.

Deux autres pièges d'identification méritent d'être connus.

- `pieusb` compare l'identifiant USB **et** un numéro de modèle. Les appareils Reflecta et PIE
  partagent des identifiants comme `05e3:0145` : un appareil n'est utilisable que si son numéro de
  modèle figure dans `pieusb.conf`.
- `epson2` reconnaît les scanners Epson sous leur nom de modèle japonais. `scanimage -L` affiche un
  Perfection V800/V850 comme `GT-X980` et un V700/V750 comme `GT-X900`. C'est le même scanner, pas
  un appareil erroné.

## Canal infrarouge

Ici, « IR disponible » signifie qu'une image infrarouge distincte peut être renvoyée à negaflow dans `irPath`.<br>
Une correction de poussière interne au backend n'est pas annoncée comme canal IR.

| Scanner ou chemin backend | État IR | Méthode d'acquisition | TIFF IR séparé |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Indisponible | Ces modèles n'exposent pas de source IR | Non |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Disponible si `scanimage -A` publie la source IR | Passage séparé `Transparency Adapter Infrared` | Oui |
| OpticFilm 8200i `07b3:1825` | Indisponible | Variante non prise en charge par SANE 1.4 | Non |
| Epson V700/V750/V800/V850 avec `epson2` standard | Indisponible | La version standard ne publie pas de mode IR séparé | Non |
| Chemin Epson personnalisé avec `SANE_FRAME_IR` | Conditionnel | Passage séparé en mode `Infrared`, uniquement s'il est signalé | Oui |
| Nikon `coolscan3` publiant `--infrared` | Indisponible avec le `scanimage` standard | `coolscan3` renvoie une seule trame `SANE_FRAME_RGBI`, que `scanimage` 1.4 ne sépare pas en TIFF RGB et IR | Non |
| Reflecta/PIE ne publiant que `--clean-image` | Indisponible comme canal IR | La correction s'effectue dans le backend | Non |
| Tout autre scanner | Conditionnel | Seulement si `scanimage -A` publie une source ou un mode IR distinct et actif | Oui, après contrôle du format et des dimensions |

Le passage IR utilise la même résolution et la même zone demandées que le passage RGB.<br>
Le module vérifie aussi que les deux images ont les mêmes dimensions en pixels.<br>
negaflow peut ensuite utiliser l'image infrarouge avec GrainMend IR.

## Dépannage : aucun scanner détecté

Dans negaflow, **approuvé** signifie que l'exécutable du module est autorisé à s'exécuter.<br>
Cela ne signifie pas qu'un scanner a été trouvé. La détection correspond exactement à ce que renvoie
`scanimage -L` : un scanner absent de cette liste est aussi absent de negaflow, et réinstaller
l'application ou le module n'y change rien.

macOS n'a pas d'autorisation USB à activer par application. Ni negaflow ni ce module n'utilisent
l'App Sandbox, donc aucun réglage de « Confidentialité et sécurité » ne bloque l'accès au scanner.

### 1. Identifier la couche qui échoue

Scanner allumé et connecté, exécutez ces commandes dans l'ordre.

```bash
system_profiler SPUSBDataType
```

```bash
scanimage -L
```

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

| Liste USB | `scanimage -L` | `detect` | Origine du problème |
|---|---|---|---|
| Aucun scanner | Rien | `{"devices":[]}` | Câble, port ou alimentation, avant même SANE |
| Scanner présent | Rien | `{"devices":[]}` | Backend SANE, ou autre processus qui retient l'appareil |
| Scanner présent | Appareil listé | `{"devices":[]}` | SANE installé là où le module ne regarde pas |
| Scanner présent | Appareil listé | Appareil listé | Côté negaflow : rouvrez « Charger le scanner » et approuvez à nouveau |

### 2. Causes fréquentes

| Symptôme | Cause | Que faire |
|---|---|---|
| `scanimage: command not found` | SANE n'est pas installé ou son répertoire `bin` est absent du `PATH` courant | Installez `sane-backends` standard ; pour Coolscan, utilisez l'assistant corrigé et l'`export` ci-dessus |
| Le scanner n'apparaît pas dans la liste USB | Hub, station d'accueil, adaptateur, câble ou alimentation | Branchez-le directement sur le Mac, essayez un autre port et évitez les hubs. Les scanners de film USB 2.0 échouent souvent via un adaptateur USB-C |
| `no SANE devices found` alors que `sane-find-scanner` voit l'appareil | Aucun backend actif ne prend en charge ce modèle | Consultez la [liste des appareils SANE](https://www.sane-project.org/sane-supported-devices.html), puis lisez le journal de l'étape 3 |
| Le scanner est dans la liste USB, `scanimage -L` reste vide et `repair-sane-config` renvoie `notNeeded` | Une révision matérielle que SANE ne connaît pas | Comparez l'USB product ID au tableau [Scanners pris en charge](#scanners-pris-en-charge). Une révision récente vendue sous un ancien nom ne se corrige pas de ce côté |
| Un Coolscan LS-50 ou LS-5000 disparaît de la liste USB | Panne de port USB documentée sur ces appareils | Vérifiez avec un autre câble et un autre port. Si le Mac ne l'énumère jamais, c'est une panne matérielle et non un problème de pilote |
| `another process has device opened for exclusive access`, `device busy`, `is not configured` | Un autre programme a déjà réservé l'interface USB | Quittez VueScan, SilverFast, Transfert d'images et les utilitaires du fabricant, rebranchez le scanner, puis réessayez |
| Seul `sudo scanimage -L` le trouve | L'interface est réservée ou n'a jamais été libérée | Réglez d'abord le point ci-dessus. negaflow n'exécute jamais le module en root : `sudo` n'est pas un contournement |
| Le terminal le trouve, pas negaflow | SANE est hors des chemins de keg Homebrew pris en charge | Relancez l'installateur fourni ; MacPorts et les autres préfixes compilés à la main ne sont pas utilisés |
| `open of device ... failed: Invalid argument` | L'adresse USB a changé après la première ouverture, ou le dossier de configuration SANE est absent | Relancez `detect` et vérifiez la présence de `/opt/homebrew/etc/sane.d` ou `/usr/local/etc/sane.d` |
| Cela fonctionnait avant une mise à jour | Le keg SANE sélectionné a été supprimé ou remplacé | Relancez l'installateur correspondant et vérifiez `brew list --versions sane-backends sane-backends-negaflow` |
| Liste vide après l'installation d'un ancien module negaflow | Une ancienne version a désactivé des backends dans `dll.conf` | Lancez `repair-sane-config`, décrit dans [Configuration SANE](#configuration-sane) |

### 3. Lire le journal du backend

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

Il indique quels backends sont chargés et lesquels échouent.<br>
Pour se limiter à un seul backend, utilisez sa propre variable, par exemple `SANE_DEBUG_GENESYS=128`
ou `SANE_DEBUG_EPSON2=128`.

Un signalement n'est exploitable qu'avec la version de macOS, le modèle de Mac,
`scanimage --version`, `brew list --versions sane-backends sane-backends-negaflow`, le modèle du scanner et la sortie des
trois étapes ci-dessus.

## Valeurs exactes et erreurs

- La résolution demandée doit exister exactement dans la liste ou la plage de l'appareil. Elle n'est
  pas remplacée par la valeur la plus proche.
- Une demande 16-bit réussit seulement si la profondeur SANE dépasse 8 et si le fichier décodé est
  réellement un TIFF 16-bit.
- Une zone physique n'est annoncée qu'avec des plages `-x/-y` utilisables en millimètres. Le
  positionnement demande aussi `-l/-t`.
- Les options dépendantes sont relues après application de source, mode, depth, resolution, preview
  et geometry.
- L'aperçu n'ajoute jamais discrètement l'IR ou la multi-exposition.
- Brightness, contrast et gamma ne servent pas à simuler une multi-exposition matérielle.
- Un résultat incohérent ou non vérifié est supprimé et renvoyé comme erreur.

## Protocole scanner negaflow

L'exécutable est appelé par sous-commandes et écrit du JSON sur la sortie standard.

| Commande | Entrée | Sortie |
|---|---|---|
| `detect` | Aucune | Liste des appareils en JSON |
| `capabilities <deviceId>` | Identité JSON facultative issue de la détection | Résolution, mode, profondeur, zone, exposition et IR en JSON |
| `scan` | Requête protocol v2 sur stdin | Progression NDJSON, puis résultat final ou erreur |
| `repair-sane-config` | Aucune | Réactive uniquement les backends désactivés par une ancienne version du plugin |
| `tune-sane` | Aucune | Alias de compatibilité de `repair-sane-config` |
| `restore-sane` | Aucune | Restaure la sauvegarde complète historique en dernier recours |

Chaque événement protocol v2 contient `protocolVersion`, `requestID` et un `sequence` croissant.<br>
`appliedOptions` n'est renvoyé qu'après contrôle du TIFF et des réglages réellement appliqués.
negaflow renvoie automatiquement dans la requête suivante le `capabilityToken` opaque reçu de
`capabilities`. Les appels directs en CLI doivent faire de même ; sans ce jeton, le contrôle de compatibilité
plus lent reste utilisé.

Les capacités sont lues dans l'état où la numérisation aura effectivement lieu. Les options SANE modifient l'activation des autres : `epson2` désactive la profondeur en Lineart et la luminosité dès qu'un gamma linéaire est choisi. Un relevé pris dans l'état par défaut de l'appareil ne décrit donc pas la numérisation. Le plug-in applique la source transparente, le mode de numérisation et les réglages neutres de couleur et de gamma, lit les options dans cet état et le conserve dans le jeton ; un autre mode demandé entraîne une relecture dans ce mode.

Exemple de requête de numérisation complète :

```json
{
  "protocolVersion": 2,
  "requestID": "7A91B43D-90F8-41E2-B71D-04D17CD9E03B",
  "deviceID": "sane-genesys:libusb:001:002",
  "capabilityToken": "<jeton opaque renvoyé par capabilities>",
  "resolutionDPI": 3600,
  "bitDepth": 16,
  "colorMode": "color",
  "filmType": "colorNegative",
  "preview": false,
  "multiExposure": false,
  "infrared": false,
  "scanArea": {
    "originXMM": 0,
    "originYMM": 0,
    "widthMM": 36,
    "heightMM": 24
  },
  "outputRawTIFF": true,
  "outputPath": "/tmp/scan.tiff"
}
```

## Configuration SANE

Le keg corrigé utilise son propre `etc/sane.d` et ne modifie pas le `dll.conf` d'une installation Homebrew standard.<br>
`detect` répare automatiquement les lignes désactivées par une ancienne version du plugin negaflow, sans modifier les commentaires de la distribution ou de l'utilisateur. La même réparation peut être lancée manuellement :

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

Si un ancien `dll.conf.negaflow-backup` existe encore, la commande suivante remplace tout le fichier actuel par cette sauvegarde. Elle annule aussi les modifications postérieures ; ne l'utilisez que si la réparation ciblée ne suffit pas :

```bash
.build/release/negaflow-scanner-sane restore-sane
```

## Dépôt

| Chemin | Rôle |
|---|---|
| `Sources/SANEPluginCore` | Détection SANE, capacités, acquisition, contrôle TIFF, IR et fusion d'expositions |
| `Sources/negaflow-scanner-sane` | Adaptateur JSON/CLI léger pour le protocole scanner negaflow v2 |
| `Tests/SANEPluginCoreTests` | Tests du protocole, des processus, des options, des TIFF et des scanners virtuels |
| `Installer` | Distribution PKG tout-en-un, scripts d'installation et ressources d'Installer.app |
| `scripts` | Build Universal, signature, paquet, installation, notarisation et contrôle de publication |

## Vérifications de développement

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

Les tests de scanners virtuels par modèle exécutent de vrais sous-processus et valident les contrats TIFF pour l'aperçu, la numérisation complète, les zones et l'IR.<br>
Ils ne reproduisent ni moteurs, ni optique, ni transport USB, ni qualité d'image finale, et ne sont pas présentés comme une preuve sur matériel réel.

## Build de publication

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

Le script compile `arm64` et `x86_64`, produit un exécutable Universal, crée le dSYM, signe et emballe le module, écrit les sommes SHA-256 et vérifie l'archive.<br>
Les fichiers sont placés dans `.build/release-artifacts/`.

La signature de distribution et la notarisation demandent aussi `NEGAFLOW_CODESIGN_IDENTITY`, `NEGAFLOW_NOTARY_KEYCHAIN_PROFILE` et `NEGAFLOW_RELEASE_MODE=distribution`.

Créez le PKG et le DMG tout-en-un avec :

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

Ce build vérifie le paquet officiel Homebrew épinglé avant d'intégrer son composant, produit ensuite la variante Apple Silicon et la variante Universal, puis contrôle chaque PKG et DMG sans les installer.<br>
Définissez `NEGAFLOW_INSTALLER_ARCHITECTURE` sur `arm64` ou `universal` pour ne produire qu'une seule variante ; la valeur par défaut `all` les produit toutes les deux.<br>
Définissez `NEGAFLOW_INSTALLER_VARIANT=all` pour produire les familles standard et Coolscan ; par défaut, seule la famille standard est produite.<br>
Le mode de distribution demande aussi `NEGAFLOW_INSTALLER_MODE=distribution`, un `NEGAFLOW_INSTALLER_IDENTITY` pour le PKG, ainsi que l'identité de signature de l'application et le profil de notarisation déjà utilisés.

## Licence

Ce projet est distribué sous [GPL-2.0-or-later](LICENSE).<br>
Les archives de publication contiennent l'avis de licence et le texte complet de la GNU GPL v2 dans [COPYING](COPYING).

Les installateurs contiennent également les [mentions tierces](THIRD_PARTY_NOTICES.md) relatives
au composant Homebrew inclus et, pour la version Coolscan, aux sources SANE corrigées compilées
sur le Mac de l'utilisateur.<br>
L'archive complète des sources du module, dans la même version, est publiée à côté de l'archive ZIP<br>
et incluse dans celle-ci, ainsi que dans le contenu du PKG et dans le DMG.

negaflow est un projet Apache-2.0 séparé.<br>
Les noms de produits et de scanners servent uniquement à identifier des cibles compatibles ou mesurées et restent la propriété de leurs détenteurs respectifs.
