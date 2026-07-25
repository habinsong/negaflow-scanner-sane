<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">Module SANE pour scanners de film, destiné à Negaflow sur macOS</p>

<p align="center">
  <a href="#prérequis"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 ou version ultérieure"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 ou version ultérieure"></a>
  <a href="manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="Protocole scanner Negaflow v2"></a>
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

**negaflow-scanner-sane** relie [Negaflow](https://github.com/habinsong/negaflow) aux scanners de film utilisables avec SANE.<br>
Il lance `scanimage`, lit les options réellement publiées par le scanner, puis renvoie les informations de l'appareil, ses capacités, la progression et les chemins TIFF par le protocole scanner Negaflow v2.

Ce n'est pas une seconde interface de numérisation, mais un module en ligne de commande à installer.<br>
Une fois installé et approuvé, il s'utilise depuis Negaflow.

Le module et l'application principale sont deux programmes distincts.<br>
Tout le code propre à SANE reste dans ce dépôt sous GPL-2.0-or-later.<br>
Negaflow, sous Apache-2.0, ne communique avec lui que par un processus séparé, des arguments de ligne de commande, des tubes et du JSON.

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
Negaflow n'affiche que les options signalées par l'appareil connecté et son backend SANE actif.

## Prérequis

- macOS 14.0 ou version ultérieure pour l'installation actuelle de Negaflow et Homebrew
- Negaflow
- [SANE backends](https://formulae.brew.sh/formula/sane-backends) à l'exécution
- Swift 5.9 ou version ultérieure uniquement pour compiler les sources

`Package.swift` conserve une cible de déploiement macOS 13 pour l'exécutable seul.<br>
Le parcours complet décrit ici commence à macOS 14 afin de suivre les prérequis actuels de Negaflow et Homebrew.

## Installation

### 1. Installateur tout-en-un

Si les Xcode Command Line Tools ne sont pas encore présents, installez-les d'abord :

```bash
xcode-select --install
```

Téléchargez `negaflow-scanner-sane-1.0.0-macos-universal-installer.dmg` depuis les [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases), ouvrez-le, puis lancez `Install Negaflow Scanner.pkg`.

Si Homebrew est absent, le paquet installe d'abord le composant officiel Homebrew, puis `sane-backends` pour l'utilisateur connecté et enfin le module Universal de Negaflow.<br>
Il fonctionne sur les Mac Apple Silicon et Intel.<br>
Une connexion Internet et un mot de passe d'administrateur sont nécessaires.<br>
Une installation Homebrew existante est réutilisée.

À la fin, redémarrez Negaflow, ouvrez « Charger le scanner », vérifiez les informations du module et approuvez-le.

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

Installez les backends SANE.<br>
Si le paquet est déjà présent, la même commande l'indique.

```bash
brew install sane-backends
```

Contrôlez la commande installée et sa version :

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends
```

`scanimage` se trouve habituellement dans `/opt/homebrew/bin/scanimage` sur les Mac Apple Silicon, et dans `/usr/local/bin/scanimage` sur les Mac Intel.<br>
Le module vérifie ces deux chemins, même si une application graphique reçoit un `PATH` plus court.<br>
La configuration SANE se trouve normalement dans `/opt/homebrew/etc/sane.d` ou `/usr/local/etc/sane.d`.

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

L'installation de l'archive ne demande pas la chaîne d'outils Swift.<br>
SANE doit toujours être installé séparément.

### 5. Approuver et vérifier dans Negaflow

Redémarrez Negaflow et ouvrez « Charger le scanner ».<br>
Vérifiez le chemin, la version, la licence et les hash du module, puis approuvez-le.<br>
Si l'exécutable ou le manifest change après une mise à jour, Negaflow demande une nouvelle approbation.

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
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400, 7500i, 7600i, 8100 | `genesys` | Complete | Scanner de film dédié |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | Scanner de film dédié |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | `genesys` | Unsupported | Non considéré comme utilisable |
| Epson Perfection V700/V750, V800/V850 | `epson2` | Good | Source transparente et zone positionnée lorsqu'elles sont signalées |
| Gamme Nikon Coolscan/LS | `coolscan3`; anciens modèles SCSI avec `coolscan` | Complete à Minimal selon le modèle | Scanner de film dédié |
| Reflecta ProScan/CrystalScan/DigitDia et PIE PowerSlide | `pieusb`; anciens modèles SCSI avec `pie` | Variable selon le modèle | Uniquement les options signalées |
| Autres scanners de film ou à plat avec transparents | Variable | Variable selon le modèle | Piloté par les capacités, sans repli fondé sur le nom |

L'OpticFilm 8200i existe sous au moins deux variantes USB portant le même nom.<br>
`07b3:130d` et `07b3:1825` n'ont pas le même état de prise en charge SANE.<br>
Vérifiez le véritable USB product ID, pas seulement le nom inscrit sur le boîtier.

## Canal infrarouge

Ici, « IR disponible » signifie qu'une image infrarouge distincte peut être renvoyée à Negaflow dans `irPath`.<br>
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
Negaflow peut ensuite utiliser l'image infrarouge avec GrainMend IR.

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

## Protocole scanner Negaflow

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
Negaflow renvoie automatiquement dans la requête suivante le `capabilityToken` opaque reçu de
`capabilities`. Les appels directs en CLI doivent faire de même ; sans ce jeton, le contrôle de compatibilité
plus lent reste utilisé.

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

Les versions actuelles ne filtrent pas le `dll.conf` partagé de Homebrew.<br>
`detect` répare automatiquement les lignes désactivées par une ancienne version du plugin Negaflow, sans modifier les commentaires de la distribution ou de l'utilisateur. La même réparation peut être lancée manuellement :

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
| `Sources/negaflow-scanner-sane` | Adaptateur JSON/CLI léger pour le protocole scanner Negaflow v2 |
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

Ce build vérifie le paquet officiel Homebrew épinglé avant d'intégrer son composant, compile le module Universal, puis contrôle le PKG et le DMG sans les installer.<br>
Le mode de distribution demande aussi `NEGAFLOW_INSTALLER_MODE=distribution`, un `NEGAFLOW_INSTALLER_IDENTITY` pour le PKG, ainsi que l'identité de signature de l'application et le profil de notarisation déjà utilisés.

## Licence

Ce projet est distribué sous [GPL-2.0-or-later](LICENSE).<br>
Les archives de publication contiennent l'avis de licence et le texte complet de la GNU GPL v2 dans [COPYING](COPYING).

L'installateur tout-en-un contient également les [mentions tierces](THIRD_PARTY_NOTICES.md) relatives au composant Homebrew inclus et aux backends SANE installés par le réseau.<br>
L'archive complète des sources du module, dans la même version, est publiée à côté de l'archive ZIP<br>
et incluse dans celle-ci, ainsi que dans le contenu du PKG et dans le DMG.

Negaflow est un projet Apache-2.0 séparé.<br>
Les noms de produits et de scanners servent uniquement à identifier des cibles compatibles ou mesurées et restent la propriété de leurs détenteurs respectifs.
