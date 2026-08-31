<h1 align="center">negaflow-scanner-sane for Windows</h1>

<p align="center">Das Plug-in, das SANE-Filmscanner unter Windows mit negaflow verbindet</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.1-EF8B26" alt="1.1.1"></a>
  <a href="#"><img src="https://img.shields.io/badge/Windows-11-0078D4?logo=windows&logoColor=white" alt="Windows 11"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0--or--later-6E7781" alt="GPL 2.0+"></a>
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
  <a href="../../README_de.md">Gemeinsame Dokumentation</a> ·
  <a href="../../negaflow-mac/docs/README_de.md">macOS</a>
</p>

---

## Voraussetzungen

- Windows 11, 64 Bit
- negaflow 1.1.1 oder neuer, vorher installiert
- Ein Filmscanner, den SANE unterstützt

Die SANE-Programme stecken im Installationsprogramm. Sonst gibt es nichts herunterzuladen.

## Installation

Laden Sie `negaflow-sane-1.1.1-win-x64.exe` unter
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) herunter und
starten Sie es.

1. Sprache wählen und den Schritten folgen.
2. Gegen Ende wird gefragt, ob der Scannerpfad geöffnet werden soll. Nur dieser Schritt
   braucht eine Administratorbestätigung.
3. negaflow neu öffnen, dann erscheinen die Scanner-Bedienelemente.

## VueScan oder SilverFast parallel nutzen

Das geht.

Das Plug-in spricht mit dem Gerät über den Scanner-Treiberpfad, den Windows ohnehin
bereitstellt (`usbscan.sys`). Es tauscht den Treiber nicht aus und überschreibt ihn nicht,
also bleibt alles bestehen, was Ihre andere Scansoftware verwendet hat.

Eine Regel gilt: Nur ein Programm kann den Scanner gleichzeitig belegen. Schließen Sie
VueScan, während Sie in negaflow scannen, und umgekehrt.

## Entfernen

Nehmen Sie `negaflow Scanner-Plug-in deinstallieren` im Startmenü oder die App-Liste in den
Einstellungen.

Das Deinstallationsprogramm fragt einmal, ob der bei der Installation geöffnete Scannerpfad
zurückgenommen werden soll. Nehmen Sie ihn zurück, geht Windows auf den vorherigen Treiber
zurück. Überspringen Sie es, bleibt der Pfad. In beiden Fällen bleiben negaflow und Ihre
Fotos unberührt.

## Wenn kein Scanner auftaucht

Der Reihe nach.

1. **Haben Sie negaflow neu geöffnet?** Die App liest Plug-ins beim Start.
2. **Strom und USB.** Prüfen Sie, ob der Scanner im Geräte-Manager als Bildbearbeitungsgerät
   erscheint.
3. **Hält ihn ein anderes Programm?** Schließen Sie VueScan, SilverFast oder das
   Herstellerprogramm.
4. **Haben Sie das Öffnen des Scannerpfads bei der Installation übersprungen?** Dann starten
   Sie das Installationsprogramm erneut und antworten diesmal mit Ja.

Wenn er immer noch fehlt, können Sie dem Plug-in beim Suchen zusehen.

```powershell
& "$env:LOCALAPPDATA\Negaflow\Plugins\sane\negaflow-scanner-sane.exe" detect
```

Ein gefundenes Gerät kommt als JSON zurück. Eine leere Liste heißt, dass SANE es nicht
gesehen hat. Eine Fehlermeldung sagt Ihnen, woran es lag.

## Wenn ein Scan mittendrin stehen bleibt

- Hängt der Scanner an einem USB-Hub, stecken Sie ihn direkt an den Rechner. Filmscans
  bewegen viele Daten, und Hubs verlieren sie manchmal.
- Prüfen Sie, ob die Energieverwaltung den USB-Anschluss abschaltet.
- Gehen Sie eine Stufe in der Auflösung zurück. Klappt es dann, liegt es an der
  Übertragungsgeschwindigkeit.

## Geprüfte Geräte

| Scanner | Was geprüft wurde |
|---|---|
| Plustek OpticFilm 8100 | Vorschau und Scan, mehrere Auflösungen, Farbe und Grau, 8 und 16 Bit |
| Epson Perfection V700 | Vorschau und Scan, mehrere Auflösungen, Infrarotkanal, Farbe und Grau |

Das sind die tatsächlich gefahrenen Kombinationen. Ein Scanner, der hier fehlt, kann
durchaus laufen, er wurde nur nicht geprüft.

## Bauen

```powershell
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane\negaflow-windows

cmake --preset x64-release
cmake --build --preset x64-release
ctest --preset x64-release --output-on-failure
```

Sie brauchen Visual Studio 2022 und CMake 3.28 oder neuer.

Für das Installationsprogramm:

```powershell
.\scripts\build-installer.ps1 -Overwrite
```

## Verwandte Dokumente

- [Gemeinsame Dokumentation](../../README_de.md)
- [macOS-Dokumentation](../../negaflow-mac/docs/README_de.md)
- [Herkunft](../../PROVENANCE.md)
- [Hinweise Dritter](../../THIRD_PARTY_NOTICES.md)
