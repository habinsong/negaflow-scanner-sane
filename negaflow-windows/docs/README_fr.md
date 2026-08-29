<h1 align="center">negaflow-scanner-sane for Windows</h1>

<p align="center">Le module qui relie les scanners de film SANE à negaflow sous Windows</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.0-EF8B26" alt="1.1.0"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
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
  <a href="../../negaflow-mac/docs/README_fr.md">macOS</a>
</p>

---

## Ce qu'il faut

- Windows 11, 64 bits
- negaflow 1.1.0 ou plus récent, installé au préalable
- Un scanner de film pris en charge par SANE

Les binaires SANE sont dans l'installateur. Il n'y a rien d'autre à télécharger.

## Installation

Téléchargez `negaflow-scanner-sane-1.1.0-x64-setup.exe` depuis
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) et lancez-le.

1. Choisissez une langue et suivez les indications.
2. Vers la fin, il demande s'il faut ouvrir le chemin scanner. C'est la seule étape qui
   demande une confirmation administrateur.
3. Redémarrez negaflow et les contrôles scanner apparaissent.

## Utiliser VueScan ou SilverFast en même temps

C'est possible.

Ce module parle à l'appareil par le chemin de pilote scanner que Windows fournit déjà
(`usbscan.sys`). Il ne remplace pas le pilote et ne l'écrase pas, donc ce qu'utilisaient vos
autres logiciels de numérisation reste en place.

La seule règle : un seul programme peut tenir le scanner à la fois. Fermez VueScan pendant
que vous numérisez dans negaflow, et inversement.

## Désinstallation

Prenez `Désinstaller le module scanner negaflow` dans le menu Démarrer, ou la liste des
applications dans les Paramètres.

Le désinstallateur demande une fois s'il faut annuler le chemin scanner ouvert à
l'installation. Si vous acceptez, Windows revient au pilote précédent. Si vous refusez, le
chemin reste. Dans les deux cas negaflow et vos photos ne sont pas touchés.

## Quand aucun scanner n'apparaît

Dans l'ordre.

1. **Avez-vous redémarré negaflow ?** L'application lit les modules au démarrage.
2. **Alimentation et USB.** Vérifiez que le scanner apparaît dans le Gestionnaire de
   périphériques comme périphérique d'imagerie.
3. **Un autre programme le tient-il ?** Fermez VueScan, SilverFast ou l'utilitaire du
   fabricant.
4. **Avez-vous refusé l'ouverture du chemin scanner à l'installation ?** Dans ce cas,
   relancez l'installateur et répondez oui cette fois.

Si rien n'y fait, vous pouvez regarder le module chercher lui-même.

```powershell
& "$env:LOCALAPPDATA\Negaflow\Plugins\sane\negaflow-scanner-sane.exe" detect
```

Un appareil trouvé revient en JSON. Une liste vide veut dire que SANE ne l'a pas vu. Un
message d'erreur vous dit ce qui a échoué.

## Quand une numérisation s'arrête en route

- Si le scanner est sur un concentrateur USB, branchez-le directement sur l'ordinateur.
  Les numérisations de film déplacent beaucoup de données et les concentrateurs en perdent
  parfois.
- Vérifiez que l'économie d'énergie ne coupe pas le port USB.
- Descendez d'un cran en résolution. Si ça passe, c'est la vitesse de transfert.

## Appareils vérifiés

| Scanner | Ce qui a été vérifié |
|---|---|
| Plustek OpticFilm 8100 | Aperçu et numérisation, plusieurs résolutions, couleur et gris, 8 et 16 bits |
| Epson Perfection V700 | Aperçu et numérisation, plusieurs résolutions, canal infrarouge, couleur et gris |

Ce sont les combinaisons réellement essayées. Un scanner absent de la liste peut très bien
fonctionner, il n'a simplement pas été vérifié.

## Compilation

```powershell
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane\negaflow-windows

cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure
```

Il faut Visual Studio 2022 et CMake 3.28 ou plus récent.

Pour construire l'installateur :

```powershell
.\scripts\build-installer.ps1 -Overwrite
```

## Documents liés

- [Documentation commune](../../README_fr.md)
- [Documentation macOS](../../negaflow-mac/docs/README_fr.md)
- [Provenance](../../PROVENANCE.md)
- [Mentions tierces](../../THIRD_PARTY_NOTICES.md)
