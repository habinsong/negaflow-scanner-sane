# Dépannage

[Accueil de la documentation](README.md)

## L'installation échoue

L'écran d'échec n'affiche que « L'installation a échoué ». macOS Installer juge un script de paquet
sur son seul code de sortie, et ce que le script a écrit se trouve dans le journal. Appuyez sur ⌘L
pendant que l'installateur est ouvert, ou lisez le journal ensuite :

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| Journal | Cause |
|---|---|
| `Your Command Line Tools are too outdated` | La version `mac26` compile SANE, et Homebrew refuse des Command Line Tools plus anciens que le macOS en cours |
| `Homebrew was not installed at the supported prefix` | Pas de `brew` dans `/opt/homebrew` ni `/usr/local` |
| `no supported logged-in user was found` | Aucun utilisateur en console, par exemple via SSH ou depuis la fenêtre de connexion |
| `patched scanimage was not installed` | Échec de la compilation de SANE ; l'erreur Homebrew se trouve au-dessus de cette ligne |

Si les Command Line Tools sont trop anciens :

```bash
sudo rm -rf /Library/Developer/CommandLineTools
```

```bash
xcode-select --install
```

Une installation obsolète conserve `git` : une simple vérification de fichier la considère donc
présente. L'installateur cherche à la place le SDK du macOS en cours et s'arrête avant d'installer
quoi que ce soit.

Homebrew n'est pas un prérequis. Le paquet embarque l'installateur Homebrew officiel signé et ne
l'exécute que si `brew` est absent. Une installation existante est utilisée telle quelle.

La version `mac26` compile SANE 1.4.0 depuis les sources : cela prend plusieurs minutes et la barre
de progression ne peut pas suivre la compilation. La version `mac14` installe un bottle précompilé et
se termine rapidement.

## Aucun scanner détecté

Dans negaflow, **approuvé** signifie que le module est autorisé à s'exécuter, pas qu'un scanner a été
trouvé. La détection correspond exactement à ce que renvoie `scanimage -L` : un scanner absent de
cette liste est aussi absent de negaflow, et réinstaller l'application ou le module n'y change rien.

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
| `scanimage: command not found` | SANE n'est pas installé ou son répertoire `bin` est absent du `PATH` courant | Installez `sane-backends` standard ; pour le parcours corrigé, utilisez l'assistant et l'`export` ci-dessus |
| Le scanner n'apparaît pas dans la liste USB | Hub, station d'accueil, adaptateur, câble ou alimentation | Branchez-le directement sur le Mac, essayez un autre port et évitez les hubs. Les scanners de film USB 2.0 échouent souvent via un adaptateur USB-C |
| `no SANE devices found` alors que `sane-find-scanner` voit l'appareil | Aucun backend actif ne prend en charge ce modèle | Consultez la [liste des appareils SANE](https://www.sane-project.org/sane-supported-devices.html), puis lisez le journal de l'étape 3 |
| Le scanner est dans la liste USB, `scanimage -L` reste vide et `repair-sane-config` renvoie `notNeeded` | Une révision matérielle que SANE ne connaît pas | Comparez l'USB product ID au tableau [scanners pris en charge](SCANNERS.md). Une révision récente vendue sous un ancien nom ne se corrige pas de ce côté |
| Un Coolscan LS-50 ou LS-5000 disparaît de la liste USB | Panne de port USB documentée sur ces appareils | Vérifiez avec un autre câble et un autre port. Si le Mac ne l'énumère jamais, c'est une panne matérielle |
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

Il indique quels backends sont chargés et lesquels échouent. Pour se limiter à un seul backend,
utilisez sa propre variable, par exemple `SANE_DEBUG_GENESYS=128` ou `SANE_DEBUG_EPSON2=128`.

Un signalement n'est exploitable qu'avec la version de macOS, le modèle de Mac,
`scanimage --version`, `brew list --versions sane-backends sane-backends-negaflow`, le modèle du
scanner et la sortie des trois étapes ci-dessus.

## Configuration SANE

Le keg corrigé utilise son propre `etc/sane.d` et ne modifie pas le `dll.conf` d'une installation
Homebrew standard. `detect` répare automatiquement les lignes désactivées par une ancienne version du
plugin negaflow, sans toucher aux commentaires de la distribution ou de l'utilisateur. La même
réparation peut être lancée manuellement :

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

Si un ancien `dll.conf.negaflow-backup` existe encore, la commande suivante remplace tout le fichier
actuel par cette sauvegarde. Elle annule aussi les modifications postérieures ; ne l'utilisez que si
la réparation ciblée ne suffit pas :

```bash
.build/release/negaflow-scanner-sane restore-sane
```
