<h1 align="center">negaflow-scanner-sane for macOS</h1>

<p align="center">Das Plug-in, das SANE-Filmscanner unter macOS mit negaflow verbindet</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/version-1.1.2-EF8B26" alt="1.1.2"></a>
  <a href="#"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer"></a>
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
  <a href="../../negaflow-windows/docs/README_de.md">Windows</a>
</p>

---

## Voraussetzungen

- macOS 14.0 oder neuer
- negaflow 1.1.1 oder neuer, vorher installiert
- Ein Filmscanner, den SANE unterstützt
- Internetverbindung und Administratorkennwort während der Installation

Installieren Sie zuerst die Xcode Command Line Tools, falls Sie sie nicht haben.

```bash
xcode-select --install
```

## Installation

Laden Sie unter [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) ein
DMG herunter. Es gibt vier. Nehmen Sie ein `mac26`, sofern Sie macOS 26 nutzen können.

| DMG | SANE | Plug-in |
|---|---|---|
| `negaflow-sane-1.1.2-mac26-arm64.dmg` | Gepatcht, macOS 26 oder neuer | `arm64` |
| `negaflow-sane-1.1.2-mac26-universal.dmg` | Gepatcht, macOS 26 oder neuer | `arm64` + `x86_64` |
| `negaflow-sane-1.1.2-mac14-arm64.dmg` | Für OpticFilm, macOS 14 oder neuer | `arm64` |
| `negaflow-sane-1.1.2-mac14-universal.dmg` | Für OpticFilm, macOS 14 oder neuer | `arm64` + `x86_64` |

In einem `mac26`-DMG starten Sie `Install negaflow Scanner.pkg`. In einem
`mac14`-DMG starten Sie `Install negaflow Scanner for OpticFilm.pkg`.

Danach öffnen Sie negaflow neu, sehen sich die Angaben unter **Scanner laden** an und
bestätigen das Plug-in.

### Was die beiden trennt

Die `mac26`-Fassung baut die offizielle SANE-1.4.0-Quelle als `sane-backends-negaflow`.
Diese Fassung bringt Nikon Coolscan, den Epson-Infrarotkanal, Schwarzweißscans mit OpticFilm
und den OpticFilm 8200i SE zum Laufen. Diese Patches kommen hinzu.

| Patch | Was sich ändert |
|---|---|
| Coolscan-Tiefenliste | Korrigiert die Zuteilung in `coolscan2` und `coolscan3` |
| `epson2` Scanhöhe | Korrigiert die von Epson-Flachbettgeräten gemeldete Höhe |
| `epson2` Infrarot | Hebt die `SANE_FRAME_IR`-Sperre auf, sodass ein Infrarotdurchlauf entsteht |
| OpticFilm Gray | Lässt einen OpticFilm 8100 oder 7400 v2 einen Gray-Scan abschließen |
| OpticFilm-Upstream-Backport | Übernimmt die `genesys`-Arbeit von SANE nach 1.4.0: den OpticFilm 8200i SE (`07b3:1825`, GL128) und Korrekturen für 7400 v1 und 7600i v1 |

Die `mac14`-Fassung installiert das normale `sane-backends` aus Homebrew, ohne
diese Patches. Sie ist für macOS 14 und 15 gedacht, wo sich die gepatchte Fassung nicht
installieren lässt. Sie hat weder die OpticFilm-Gray-Korrektur noch den 8200i SE.

Keine der beiden sperrt Coolscan unter macOS 14 oder 15. Mit dem regulären SANE kann es
funktionieren, aber ohne die Zuteilungskorrektur; der unterstützte Weg für die USB-Modelle ist
daher der `mac26`-Installer. LS-4000 ED und LS-8000 ED lassen sich nur per FireWire anschließen,
das macOS 26 nicht mehr unterstützt. Auf dem Mac lassen sie sich nur unter macOS 14 oder 15 mit
dem `mac14`-Installer ausprobieren, was noch niemand getan hat. Siehe
[unterstützte Scanner](../../docs/de/SCANNERS.md#nikon-coolscan).

Die Coolscan3-Initialisierung für Laden, Auswerfen und Zurücksetzen, die Firmware 1.03 des
LS-5000 braucht, blieb bewusst außerhalb der Patches. Laden, Auswerfen und Zurücksetzen von
Film auf einem LS-5000 ist ungeprüft und kann fehlschlagen.

## Von Hand installieren

```bash
# Falls Sie kein Homebrew haben
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install sane-backends
scanimage -L
```

Danach bauen Sie das Plug-in aus dem Quellcode oder installieren es aus dem Release-ZIP.

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
swift build -c release
```

## Wenn kein Scanner auftaucht

1. **Haben Sie negaflow neu geöffnet?** Die App liest Plug-ins beim Start.
2. **Haben Sie es bestätigt?** Das Plug-in läuft erst nach der Bestätigung im Bildschirm
   Scanner laden.
3. **Sieht SANE das Gerät?** Führen Sie `scanimage -L` im Terminal aus. Erscheint dort
   nichts, liegt es an SANE und nicht am Plug-in.
4. **Hält es ein anderes Programm?** Schließen Sie VueScan oder das Herstellerprogramm.

```bash
/usr/local/bin/negaflow-scanner-sane detect
```

## Geprüfte Geräte

| Scanner | Was geprüft wurde |
|---|---|
| Plustek OpticFilm 8100 | Vorschau und Scan, mehrere Auflösungen, Farbe und Grau |
| Epson Perfection V700 | Vorschau und Scan, mehrere Auflösungen, Infrarotkanal |

Ein Scanner, der hier fehlt, kann durchaus laufen, er wurde nur nicht geprüft.

## Bauen und prüfen

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

Die Tests mit virtuellem Scanner nutzen echte Prozessaufrufe und den TIFF-Vertrag, um
Vorschau, Scan, Scanbereich und Infrarotpfad zu prüfen. Motoren, Optik, USB-Übertragung und
die endgültige Bildqualität bilden sie nicht ab.

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

## Verwandte Dokumente

- [Gemeinsame Dokumentation](../../README_de.md)
- [Windows-Dokumentation](../../negaflow-windows/docs/README_de.md)
- [Herkunft](../../PROVENANCE.md)
- [Hinweise Dritter](../../THIRD_PARTY_NOTICES.md)
