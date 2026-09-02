<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">Das Plug-in, das Filmscanner mit negaflow verbindet</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/de/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="Website"></a>
  <a href="negaflow-mac/docs/README_de.md"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer"></a>
  <a href="negaflow-windows/docs/README_de.md"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="negaflow-mac/manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow-Scannerprotokoll v2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0 oder neuer"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_ko.md">한국어</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_zh-Hans.md">简体中文</a> ·
  <a href="README_fr.md">Français</a> ·
  <strong>Deutsch</strong>
</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/de/">Website</a> ·
  <a href="https://habinsong.github.io/negaflow-site/de/supported-scanners/">Unterstützte Scanner</a> ·
  <a href="https://habinsong.github.io/negaflow-site/de/faq/">FAQ</a>
</p>

---

**negaflow-scanner-sane** verbindet Filmscanner, die SANE ansteuern kann, mit
[negaflow](https://github.com/habinsong/negaflow).

Gescannt wird weiterhin in negaflow. Das Plug-in steuert den Scanner und arbeitet, ohne separat
gestartet zu werden. Installieren, in negaflow einmal freigeben, und der Scanner erscheint unter
„Scanner laden“.

Plug-in und Anwendung sind getrennte Programme. Der gesamte SANE-Code bleibt in diesem
GPL-2.0-or-later-Repository, und das unter Apache-2.0 stehende negaflow tauscht mit ihm nur JSON
über eine Prozessgrenze aus.

## Voraussetzungen

- negaflow, vorher installiert
- Ein Filmscanner, den SANE unterstützt
- macOS 14.0 oder neuer, oder Windows 11

## Installation

Laden Sie unter [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) das
Installationsprogramm für Ihr System herunter, starten Sie es, öffnen Sie negaflow neu und bestätigen
Sie das Plug-in. Unter macOS richtet das Installationsprogramm SANE über Homebrew mit ein. Unter
Windows stecken die SANE-Programme bereits im Installationsprogramm.

| Plattform | Seite |
|---|---|
| macOS | [Unter macOS installieren](negaflow-mac/docs/README_de.md) |
| Windows | [Unter Windows installieren](negaflow-windows/docs/README_de.md) |

## Scanner

Die meisten Filmscanner, die SANE unterstützt, funktionieren. Die Tücke liegt darin, dass zwei Geräte
mit demselben Produktnamen unterschiedliche Chips enthalten können und nur für einen davon ein
Backend existiert. Der Infrarotkanal wird nur genutzt, wenn das Gerät ihn wirklich liefert. Was
welches Modell kann, steht unter [unterstützte Scanner](docs/de/SCANNERS.md).

Ein Modellname schaltet für sich genommen keine Funktion frei. negaflow bekommt die Optionen, die das
angeschlossene Gerät und sein Backend melden.

## Dokumentation

- [Unterstützte Scanner](docs/de/SCANNERS.md) | Modell für Modell, Fallstricke der Produktnamen, Infrarotkanal
- [Fehlersuche](docs/de/TROUBLESHOOTING.md) | fehlgeschlagene Installation, kein Scanner gefunden, SANE-Konfiguration
- [Entwicklung](docs/de/DEVELOPMENT.md) | Scannerprotokoll, Repository-Aufbau, Builds
- Installationsseiten | [macOS](negaflow-mac/docs/README_de.md) · [Windows](negaflow-windows/docs/README_de.md)

## Lizenz

Dieses Projekt wird unter [GPL-2.0-or-later](LICENSE) veröffentlicht. Release-Archive enthalten den
Lizenzhinweis und den vollständigen Text der GNU GPL v2 in [COPYING](COPYING).

Die Installer enthalten außerdem die [Hinweise zu Drittsoftware](THIRD_PARTY_NOTICES.md) für die
enthaltene Homebrew-Komponente und, bei der Coolscan-Variante, die auf dem Mac des Benutzers gebauten
gepatchten SANE-Quellen. Das vollständige Quellarchiv derselben Plug-in-Version wird neben dem
Release-ZIP veröffentlicht und ist außerdem im ZIP, im PKG-Inhalt und im DMG enthalten.

negaflow ist ein getrenntes Apache-2.0-Projekt. Produkt- und Scannernamen dienen nur zur Bezeichnung
kompatibler oder vermessener Ziele und bleiben Eigentum der jeweiligen Rechteinhaber.
