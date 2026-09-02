<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">Le module qui relie les scanners de film à negaflow</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/fr/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="site web"></a>
  <a href="negaflow-mac/docs/README_fr.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 ou version ultérieure"></a>
  <a href="negaflow-windows/docs/README_fr.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="negaflow-mac/manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="Protocole scanner negaflow v2"></a>
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

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/fr/">Site web</a> ·
  <a href="https://habinsong.github.io/negaflow-site/fr/supported-scanners/">Scanners pris en charge</a> ·
  <a href="https://habinsong.github.io/negaflow-site/fr/faq/">FAQ</a>
</p>

---

**negaflow-scanner-sane** relie [negaflow](https://github.com/habinsong/negaflow) aux scanners de
film que SANE sait piloter.

La numérisation se fait toujours dans negaflow. Le module travaille derrière et dialogue avec le
scanner, il n'y a donc rien à lancer soi-même. Installez-le, approuvez-le une fois dans negaflow et
le scanner apparaît dans « Charger le scanner ».

Le module et l'application sont deux programmes distincts. Tout le code SANE reste dans ce dépôt
sous GPL-2.0-or-later, et negaflow, sous Apache-2.0, se contente d'échanger du JSON avec lui d'un
processus à l'autre.

## Prérequis

- negaflow, installé au préalable
- Un scanner de film pris en charge par SANE
- macOS 14.0 ou plus récent, ou Windows 11

## Installation

Téléchargez l'installateur correspondant à votre système depuis
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases), lancez-le, redémarrez
negaflow et approuvez le module. Sur macOS l'installateur met aussi SANE en place via Homebrew. Sur
Windows les binaires SANE sont déjà dans l'installateur.

| Plateforme | Page |
|---|---|
| macOS | [Installer sur macOS](negaflow-mac/docs/README_fr.md) |
| Windows | [Installer sur Windows](negaflow-windows/docs/README_fr.md) |

## Scanners

La plupart des scanners de film pris en charge par SANE fonctionnent. Le piège, c'est que deux
appareils vendus sous le même nom peuvent embarquer des puces différentes, et une seule d'entre
elles a un backend. Le canal infrarouge n'est utilisé que si l'appareil le fournit réellement. Le
détail modèle par modèle est dans [scanners pris en charge](docs/fr/SCANNERS.md).

Un nom de modèle n'active jamais une fonction à lui seul. negaflow reçoit les options que l'appareil
connecté et son backend signalent.

## Documentation

- [Scanners pris en charge](docs/fr/SCANNERS.md) | modèle par modèle, pièges des noms de produit, canal infrarouge
- [Dépannage](docs/fr/TROUBLESHOOTING.md) | installation en échec, aucun scanner détecté, configuration SANE
- [Développement](docs/fr/DEVELOPMENT.md) | protocole scanner, structure du dépôt, builds
- Pages d'installation | [macOS](negaflow-mac/docs/README_fr.md) · [Windows](negaflow-windows/docs/README_fr.md)

## Licence

Ce projet est distribué sous [GPL-2.0-or-later](LICENSE). Les archives de publication contiennent
l'avis de licence et le texte complet de la GNU GPL v2 dans [COPYING](COPYING).

Les installateurs contiennent également les [mentions tierces](THIRD_PARTY_NOTICES.md) relatives au
composant Homebrew inclus et, pour la version Coolscan, aux sources SANE corrigées compilées sur le
Mac de l'utilisateur. L'archive complète des sources du module, dans la même version, est publiée à
côté de l'archive ZIP et incluse dans celle-ci, ainsi que dans le contenu du PKG et dans le DMG.

negaflow est un projet Apache-2.0 séparé. Les noms de produits et de scanners servent uniquement à
identifier des cibles compatibles ou mesurées et restent la propriété de leurs détenteurs respectifs.
