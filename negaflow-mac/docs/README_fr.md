<h1 align="center">negaflow-scanner-sane for macOS</h1>

<p align="center">Le module qui relie les scanners de film SANE à negaflow sous macOS</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 ou ultérieur"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0+"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <strong>Français</strong> ·
  <a href="README_de.md">Deutsch</a>
</p>

<p align="center">
  <a href="../../README_fr.md">Documentation commune</a> ·
  <a href="../../negaflow-windows/docs/README_fr.md">Windows</a>
</p>

---

## Ce qu'il faut

- macOS 14.0 ou plus récent
- negaflow 1.1.0 ou plus récent, installé au préalable
- Un scanner de film pris en charge par SANE
- Une connexion internet et un mot de passe administrateur pendant l'installation

Installez d'abord les Xcode Command Line Tools si vous ne les avez pas.

```bash
xcode-select --install
```

## Installation

Téléchargez un DMG depuis
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases). Il y en a quatre.
Prenez un `mac26` sauf si vous ne pouvez pas faire tourner macOS 26.

| DMG | SANE | Module |
|---|---|---|
| `negaflow-sane-1.1.0-mac26-arm64.dmg` | Corrigé, macOS 26 ou plus | `arm64` |
| `negaflow-sane-1.1.0-mac26-universal.dmg` | Corrigé, macOS 26 ou plus | `arm64` + `x86_64` |
| `negaflow-sane-1.1.0-mac14-arm64.dmg` | Pour OpticFilm, macOS 14 ou plus | `arm64` |
| `negaflow-sane-1.1.0-mac14-universal.dmg` | Pour OpticFilm, macOS 14 ou plus | `arm64` + `x86_64` |

Dans un DMG `mac26`, lancez `Install negaflow Scanner.pkg`. Dans un
`mac14`, lancez `Install negaflow Scanner for OpticFilm.pkg`.

Ensuite redémarrez negaflow, regardez les détails du module sous **Charger un scanner**, et
approuvez-le.

### Ce qui sépare les deux

La version `mac26` compile la source officielle SANE 1.4.0 sous le nom
`sane-backends-negaflow`. C'est elle qui fait fonctionner les Nikon Coolscan et le canal
infrarouge Epson. Trois correctifs entrent.

| Correctif | Ce qu'il change |
|---|---|
| Liste de profondeurs Coolscan | Corrige l'allocation amont de `coolscan2` et `coolscan3` |
| Hauteur de scan `epson2` | Corrige la hauteur que remontent les scanners à plat Epson |
| Infrarouge `epson2` | Lève le blocage `SANE_FRAME_IR` pour produire une passe infrarouge |

La version `mac14` installe le `sane-backends` standard de Homebrew, sans ces
correctifs. Elle existe pour macOS 14 et 15, où la version corrigée ne s'installe pas.

L'initialisation Coolscan3 load, eject et reset dont a besoin le micrologiciel 1.03 du
LS-5000 a été volontairement laissée de côté. Le chargement, l'éjection et la
réinitialisation du film sur un LS-5000 restent non vérifiés et peuvent échouer.

## Installation à la main

```bash
# Si vous n'avez pas Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install sane-backends
scanimage -L
```

Puis compilez le module depuis les sources, ou installez-le depuis le ZIP de la version.

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
swift build -c release
```

## Quand aucun scanner n'apparaît

1. **Avez-vous redémarré negaflow ?** L'application lit les modules au démarrage.
2. **L'avez-vous approuvé ?** Le module ne tourne qu'après approbation sur l'écran Charger
   un scanner.
3. **SANE voit-il l'appareil ?** Lancez `scanimage -L` dans le Terminal. Si rien n'apparaît
   là, le problème est au niveau de SANE.
4. **Un autre programme le tient-il ?** Fermez VueScan ou l'utilitaire du fabricant.

```bash
/usr/local/bin/negaflow-scanner-sane detect
```

## Appareils vérifiés

| Scanner | Ce qui a été vérifié |
|---|---|
| Plustek OpticFilm 8100 | Aperçu et numérisation, plusieurs résolutions, couleur et gris |
| Epson Perfection V700 | Aperçu et numérisation, plusieurs résolutions, canal infrarouge |

Un scanner absent de la liste peut très bien fonctionner, il n'a simplement pas été vérifié.

## Compilation et vérifications

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

Les tests à scanner virtuel utilisent une vraie exécution de processus et le contrat TIFF
pour vérifier l'aperçu, la numérisation, la zone de scan et le chemin infrarouge. Ils ne
reproduisent ni les moteurs, ni l'optique, ni le transfert USB, ni la qualité finale.

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

## Documents liés

- [Documentation commune](../../README_fr.md)
- [Documentation Windows](../../negaflow-windows/docs/README_fr.md)
- [Provenance](../../PROVENANCE.md)
- [Mentions tierces](../../THIRD_PARTY_NOTICES.md)
