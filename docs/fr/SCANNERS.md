# Scanners pris en charge

[Accueil de la documentation](README.md)

Le tableau suivant décrit des cibles SANE 1.4 connues et les chemins gérés par ce module. Il ne
garantit pas que tous les appareils portant le même nom fonctionneront. Consultez la
[liste SANE actuelle](https://www.sane-project.org/sane-supported-devices.html), puis contrôlez
l'appareil connecté avec `scanimage -L` et `scanimage -A`.

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

## Le nom du produit ne dit rien du matériel

L'OpticFilm 8100 et le 8200i existent chacun sous au moins deux variantes USB portant le même nom.
`07b3:130c` et `07b3:130d` sont pilotés par `genesys` ; `07b3:1824` et `07b3:1825` ne le sont pas,
car ils utilisent une autre puce Genesys qu'aucun backend ne pilote. Une révision récente vendue sous
un ancien nom ne peut pas être corrigée côté SANE : vérifiez le véritable USB product ID, pas
seulement le nom inscrit sur le boîtier.

Deux autres pièges d'identification méritent d'être connus.

- `pieusb` compare l'identifiant USB **et** un numéro de modèle. Les appareils Reflecta et PIE
  partagent des identifiants comme `05e3:0145` : un appareil n'est utilisable que si son numéro de
  modèle figure dans `pieusb.conf`.
- `epson2` reconnaît les scanners Epson sous leur nom de modèle japonais. `scanimage -L` affiche un
  Perfection V800/V850 comme `GT-X980` et un V700/V750 comme `GT-X900`. C'est le même scanner.

## Canal infrarouge

Ici, « IR disponible » signifie qu'une image infrarouge distincte peut être renvoyée à negaflow dans
`irPath`. Une correction de poussière interne au backend n'est pas annoncée comme canal IR.

| Scanner ou chemin backend | État IR | Méthode d'acquisition | TIFF IR séparé |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Indisponible | Ces modèles n'exposent pas de source IR | Non |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Disponible si `scanimage -A` publie la source IR | Passage séparé `Transparency Adapter Infrared` | Oui |
| OpticFilm 8200i `07b3:1825` | Indisponible | Variante non prise en charge par SANE 1.4 | Non |
| Epson V700/V750/V800/V850 avec l'installeur `mac26` | Disponible quand `scanimage -A` signale le mode infrarouge | Passage séparé en mode `Infrared` de l'`epson2` corrigé | Oui |
| Epson V700/V750/V800/V850 avec `epson2` standard | Indisponible | Les versions standard laissent `SANE_FRAME_IR` hors compilation | Non |
| Nikon `coolscan3` publiant `--infrared` | Indisponible avec le `scanimage` standard | `coolscan3` renvoie une seule trame `SANE_FRAME_RGBI`, que `scanimage` 1.4 ne sépare pas en TIFF RGB et IR | Non |
| Reflecta/PIE ne publiant que `--clean-image` | Indisponible comme canal IR | La correction s'effectue dans le backend | Non |
| Tout autre scanner | Conditionnel | Seulement si `scanimage -A` publie une source ou un mode IR distinct et actif | Oui, après contrôle du format et des dimensions |

Le passage IR utilise la même résolution et la même zone demandées que le passage RGB, et les deux
images sont contrôlées aux mêmes dimensions en pixels avant d'être renvoyées. negaflow peut ensuite
utiliser l'image infrarouge avec GrainMend IR.
