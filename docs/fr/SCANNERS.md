# Scanners pris en charge

[Accueil de la documentation](README.md)

Le tableau suivant décrit des cibles SANE connues et les chemins gérés par ce module. Il ne
garantit pas que tous les appareils portant le même nom fonctionneront. Consultez la
[liste SANE actuelle](https://www.sane-project.org/sane-supported-devices.html), puis contrôlez
l'appareil connecté avec `scanimage -L` et `scanimage -A`.

« SANE corrigé » désigne le SANE que compile l'installeur `mac26` et le runtime SANE livré dans
l'installeur Windows : SANE 1.4.0 plus les correctifs décrits dans
[`sane-runtime/SOURCES.md`](../../negaflow-mac/sane-runtime/SOURCES.md). L'installeur `mac14`
utilise le SANE 1.4.0 standard de Homebrew, sans ces correctifs.

| Famille de scanners | Backend SANE | État | Chemin du module |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i v2 | `genesys` | Complete dans SANE 1.4 | Scanner de film dédié |
| Plustek OpticFilm 7400 v1, 7600i v1 | `genesys` | Corrigés en amont après 1.4.0 ; corrections incluses dans le SANE corrigé | Scanner de film dédié ; non vérifié sur matériel |
| Plustek OpticFilm 8100, USB `07b3:130c` (GL845) | `genesys` | Complete dans SANE 1.4 | Scanner de film dédié, vérifié sur matériel |
| Plustek OpticFilm 8200i, USB `07b3:130d` (GL845) | `genesys` | Complete dans SANE 1.4 | Scanner de film dédié |
| Plustek OpticFilm 8200i récent, USB `07b3:1825` (GL128 ; SANE l'affiche comme « 8200i SE ») | `genesys`, SANE corrigé uniquement | Basic en amont : 16 bits, 150 à 7200 dpi, sans infrarouge | Scanner de film dédié ; non vérifié sur matériel |
| Plustek OpticFilm 8100 V2, USB `07b3:1824` (GL128) | Aucun | Unsupported | Non considéré comme utilisable |
| Plustek OpticFilm 8300i, USB `07b3:181f` (GL128, relevé sur le SE) | Aucun | Unsupported | Non considéré comme utilisable |
| Plustek OpticFilm 9000i Ai, USB `07b3:182f` | Aucun | Unsupported | Non considéré comme utilisable |
| Plustek OpticFilm 120, 120 Pro, 135, 135i | Aucun | Unsupported | Non considéré comme utilisable |
| Epson Perfection V700/V750 (GT-X900), V800/V850 (GT-X980) | `epson2` | Good | Source par transparence et zone positionnée du scanner à plat si elles sont signalées |
| Nikon Coolscan LS-40 ED, LS-50 ED, LS-5000 ED (USB) | `coolscan3`, `coolscan2` | Complete (LS-40), Minimal (LS-50), Untested (LS-5000) | Scanner de film dédié, avec les limites ci-dessous ; non vérifié sur matériel |
| Nikon Coolscan LS-4000 ED, LS-8000 ED (IEEE 1394 / FireWire) | `coolscan3`, `coolscan2` via SBP-2 | Good sous Linux | Inutilisable sous macOS 26 ; Windows et macOS 14/15 non vérifiés, voir plus bas |
| Nikon Coolscan LS-30, LS-2000 (SCSI) | `coolscan3` | Complete (LS-30), Good (LS-2000) | Nécessite un adaptateur hôte SCSI |
| Nikon Coolscan LS-20, LS-1000 | `coolscan` | Variable selon le modèle | SCSI uniquement |
| Nikon Coolscan LS-9000 ED | Aucun | Unsupported | Non considéré comme utilisable |
| Reflecta ProScan/CrystalScan/DigitDia et PIE PowerSlide | `pieusb` ; les anciens modèles SCSI utilisent `pie` | Variable selon le modèle et son numéro | Seules les options signalées par l'appareil |
| Pacific Image PrimeFilm XA, XAs, XA Plus | Aucun | Unsupported | Non considéré comme utilisable |
| Autres scanners à plat ou de film acceptant la transparence | Variable | Variable selon le modèle | Selon les capacités signalées, sans repli sur le nom du modèle |

## Le nom du produit ne dit rien du matériel

Plustek vend du matériel récent sous d'anciens noms de produit. C'est l'USB product ID qui les
distingue, pas le nom inscrit sur le boîtier.

| Nom sur le boîtier | ID USB | Contrôleur | SANE |
|---|---|---|---|
| OpticFilm 8100, anciens exemplaires | `07b3:130c` | GL845 | `genesys` dans SANE 1.4.0 |
| OpticFilm 8100, exemplaires récents (V2) | `07b3:1824` | GL128 | Aucun |
| OpticFilm 8200i, anciens exemplaires | `07b3:130d` | GL845 | `genesys` dans SANE 1.4.0 |
| OpticFilm 8200i, exemplaires récents | `07b3:1825` | GL128 | `genesys` dans la branche master amont depuis 2026-09 ; SANE corrigé uniquement |
| OpticFilm 8300i SE (Ai non confirmé) | `07b3:181f` | GL128 | Aucun |
| OpticFilm 9000i Ai | `07b3:182f` | Non publié | Aucun |

SE et Ai désignent l'édition de SilverFast fournie, pas le matériel : un ancien 8200i SE ou Ai
est un `130d`, un récent un `1825`.

Les trois scanners GL128 partagent la même disposition de registres, mais pas toutes les valeurs.
Le code GL128 de SANE s'appuie en grande partie sur les captures USB décodées par le pilote libre
[pyopticfilm](https://github.com/jboneng/pyopticfilm), qui en consigne les différences : le 8100 V2
démarre avec une autre horloge ASIC et un autre registre `0x0B`, et le 8300i SE a ses propres
tables d'exposition, de synchronisation du capteur et de moteur. Appliquer la table du 8200i SE à
l'un d'eux reviendrait à deviner la commande du moteur et de la lampe. pyopticfilm consigne un
blocage du moteur sur un 8100 V2 juste après l'activation d'un seul bit de registre. Ce module
n'active donc un modèle GL128 qu'une fois qu'une version de SANE le pilote et qu'il a réellement
servi à numériser.

Consultez l'ID avec `system_profiler SPUSBDataType` sur Mac, ou dans le Gestionnaire de
périphériques sous Windows.

Deux autres pièges d'identification méritent d'être connus.

- `pieusb` compare l'identifiant USB **et** un numéro de modèle. Les appareils Reflecta et PIE
  partagent des identifiants comme `05e3:0145` : un appareil n'est utilisable que si son numéro de
  modèle figure dans `pieusb.conf`.
- `epson2` reconnaît les scanners Epson sous leur nom de modèle japonais. `scanimage -L` affiche un
  Perfection V800/V850 comme `GT-X980` et un V700/V750 comme `GT-X900`. C'est le même scanner.

## Nikon Coolscan

Aucun Coolscan n'a encore été vérifié sur matériel avec ce module. Ce qui suit résulte de la
lecture du code source de `coolscan3` et du code du module.

### Connexion

Les LS-4000 ED et LS-8000 ED n'ont qu'un port IEEE 1394 (FireWire). SANE les atteint comme des
appareils SCSI via SBP-2 : ils apparaissent sous la forme `coolscan3:scsi:...`, jamais en USB.

- **macOS 26 ne prend plus du tout en charge FireWire**, et aucun adaptateur ne le rétablit.
  L'installeur `mac26`, le seul qui utilise le SANE corrigé, ne peut donc pas atteindre ces deux
  modèles.
- macOS 14 et 15 gèrent encore FireWire, et SANE dispose d'une interface SCSI pour macOS, mais ce
  chemin n'a jamais été essayé avec l'installeur `mac14`.
- Sous Windows, SANE devrait passer par son interface SCSI pass-through pour atteindre un scanner
  SBP-2. Cela n'a pas été essayé non plus.

Les cibles Coolscan réalistes sont les modèles USB : LS-40 ED, LS-50 ED et LS-5000 ED.

### Comportement du module

| Sujet | Comportement | Effet |
|---|---|---|
| Mode couleur | `coolscan2`/`coolscan3` n'ont pas de `--mode` et renvoient toujours du RGB | Seul `color` est annoncé. Le film noir et blanc est numérisé en couleur puis développé par negaflow ; la requête est celle d'un négatif couleur, au type de film près |
| Zone | Les options de géométrie sont en pixels à la résolution maximale du scanner, pas en millimètres | negaflow ne peut pas choisir de zone ; le module convertit ses 36 x 24 mm par défaut en pixels. Une vue moyen format sur un LS-8000 est réduite à ses 36 x 24 mm en haut à gauche |
| Vue | `--frame` n'est jamais envoyé | Avec un porte-bandes, seule la première vue est numérisée |
| Mise au point | `coolscan3` ne fait l'autofocus que sur demande, et negaflow ne le demande pas | La numérisation utilise la position de mise au point actuelle du scanner |
| Infrarouge | `--infrared` renvoie une seule trame RGBI | Non proposé comme canal IR |
| Type de film | `--negative` fait inverser les couleurs par le scanner | Toujours envoyé comme `--negative=no`, pour que negaflow reçoive le négatif brut |

Les deux dernières lignes du tableau sont voulues. Les quatre premières restent à faire, et chacune
doit être vérifiée sur un scanner réel.

## Canal infrarouge

Ici, « IR disponible » signifie qu'une image infrarouge distincte peut être renvoyée à negaflow dans
`irPath`. Une correction de poussière interne au backend n'est pas annoncée comme canal IR.

| Scanner ou chemin backend | État IR | Méthode d'acquisition | TIFF IR séparé |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Indisponible | Ces modèles n'exposent pas de source IR | Non |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Disponible si `scanimage -A` publie la source IR | Passage séparé `Transparency Adapter Infrared` | Oui |
| OpticFilm 8200i récent `07b3:1825` | Indisponible | Le code GL128 de SANE n'a pas encore de passage infrarouge | Non |
| OpticFilm 8100 V2, 8300i, 9000i | Indisponible | Aucun backend SANE | Non |
| Epson V700/V750/V800/V850 avec l'installeur `mac26` | Disponible quand `scanimage -A` signale le mode infrarouge | Passage séparé en mode `Infrared` de l'`epson2` corrigé | Oui |
| Epson V700/V750/V800/V850 avec `epson2` standard | Indisponible | Les versions standard laissent `SANE_FRAME_IR` hors compilation | Non |
| Nikon `coolscan3` publiant `--infrared` | Indisponible avec `scanimage` | `coolscan3` renvoie une seule trame `SANE_FRAME_RGBI`, que `scanimage` 1.4 ne sépare pas en TIFF RGB et IR | Non |
| Reflecta/PIE ne publiant que `--clean-image` | Indisponible comme canal IR | La correction s'effectue dans le backend | Non |
| Tout autre scanner | Conditionnel | Seulement si `scanimage -A` publie une source ou un mode IR distinct et actif | Oui, après contrôle du format et des dimensions |

Le passage IR utilise la même résolution et la même zone demandées que le passage RGB, et les deux
images sont contrôlées aux mêmes dimensions en pixels avant d'être renvoyées. negaflow peut ensuite
utiliser l'image infrarouge avec GrainMend IR.
