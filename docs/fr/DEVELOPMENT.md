# Développement

[Accueil de la documentation](README.md)

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

Chaque événement protocol v2 contient `protocolVersion`, `requestID` et un `sequence` croissant.
`appliedOptions` n'est renvoyé qu'après contrôle du TIFF et des réglages réellement appliqués.
negaflow renvoie automatiquement dans la requête suivante le `capabilityToken` opaque reçu de
`capabilities`. Les appels directs en CLI doivent faire de même ; sans ce jeton, le contrôle de
compatibilité plus lent reste utilisé.

Les capacités sont lues dans l'état où la numérisation aura effectivement lieu, car les options SANE
modifient l'activation des autres. `epson2` désactive la profondeur en Lineart et la luminosité dès
qu'un gamma linéaire est choisi, et un relevé pris dans l'état par défaut de l'appareil ne décrit donc
pas la numérisation. Le module applique la source transparente, le mode de numérisation et les
réglages neutres de couleur et de gamma, lit les options dans cet état et le conserve dans le jeton ;
un autre mode demandé entraîne une relecture dans ce mode.

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

## Valeurs demandées et erreurs

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

## Dépôt

| Chemin | Rôle |
|---|---|
| `Sources/SANEPluginCore` | Détection SANE, capacités, acquisition, contrôle TIFF, IR et fusion d'expositions |
| `Sources/negaflow-scanner-sane` | Adaptateur JSON/CLI léger pour le protocole scanner negaflow v2 |
| `Tests/SANEPluginCoreTests` | Tests du protocole, des processus, des options, des TIFF et des scanners virtuels |
| `Installer` | Distribution PKG tout-en-un, scripts d'installation et ressources d'Installer.app |
| `scripts` | Build Universal, signature, paquet, installation, notarisation et contrôle de publication |

## Vérifications

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

Les tests de scanners virtuels par modèle exécutent de vrais sous-processus et valident les contrats
TIFF pour l'aperçu, la numérisation complète, les zones et l'IR. Ils ne reproduisent ni moteurs, ni
optique, ni transport USB, ni qualité d'image finale, et ne valent donc pas preuve sur matériel réel.

## Build de publication

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

Le script compile `arm64` et `x86_64`, produit un exécutable Universal, crée le dSYM, signe et
emballe le module, écrit les sommes SHA-256 et vérifie l'archive. Les fichiers sont placés dans
`.build/release-artifacts/`.

La signature de distribution et la notarisation demandent aussi `NEGAFLOW_CODESIGN_IDENTITY`,
`NEGAFLOW_NOTARY_KEYCHAIN_PROFILE` et `NEGAFLOW_RELEASE_MODE=distribution`.

Créez le PKG et le DMG tout-en-un avec :

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

Ce build vérifie le paquet officiel Homebrew épinglé avant d'intégrer son composant, produit ensuite
la variante Apple Silicon et la variante Universal, puis contrôle chaque PKG et DMG sans les
installer. Définissez `NEGAFLOW_INSTALLER_ARCHITECTURE` sur `arm64` ou `universal` pour ne produire
qu'une seule variante ; la valeur par défaut `all` les produit toutes les deux. Définissez
`NEGAFLOW_INSTALLER_VARIANT=all` pour produire les familles standard et Coolscan ; par défaut, seule
la famille standard est produite. Le mode de distribution demande aussi
`NEGAFLOW_INSTALLER_MODE=distribution`, un `NEGAFLOW_INSTALLER_IDENTITY` pour le PKG, ainsi que
l'identité de signature de l'application et le profil de notarisation déjà utilisés.
