<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">SANE-Filmscanner-Plug-in für negaflow unter macOS</p>

<p align="center">
  <a href="#voraussetzungen"><img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14 oder neuer"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9 oder neuer"></a>
  <a href="manifest.json"><img src="https://img.shields.io/badge/protocol-v2-4B5563" alt="negaflow-Scannerprotokoll v2"></a>
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

---

**negaflow-scanner-sane** verbindet [negaflow](https://github.com/habinsong/negaflow) mit Filmscannern, die über SANE erreichbar sind.<br>
Das Plug-in startet `scanimage`, liest die vom Scanner tatsächlich gemeldeten Optionen und gibt Geräteinformationen, Fähigkeiten, Fortschritt und TIFF-Pfade über das negaflow-Scannerprotokoll v2 zurück.

Es ist keine zweite Scan-Oberfläche, sondern ein installierbares Kommandozeilen-Plug-in.<br>
Nach Installation und Freigabe wird weiterhin in negaflow gescannt.

Plug-in und Hauptanwendung sind getrennte Programme.<br>
Der gesamte SANE-spezifische Code bleibt in diesem GPL-2.0-or-later-Repository.<br>
Das unter Apache-2.0 stehende negaflow kommuniziert damit nur über einen separaten Prozess, Kommandozeilenargumente, Pipes und JSON.

## Funktionen

- Scannererkennung mit `scanimage -L`
- Aufbau der Scan-Einstellungen aus der aktuellen Ausgabe von `scanimage -A`
- Vorschau und vollständiger Scan ohne stillen Ersatz durch einen ähnlichen Wert
- Prüfung von Auflösung, Farbmodus, Bittiefe, Abmessungen und TIFF-Format vor der Rückgabe
- Scanbereich in Millimetern nur dann, wenn das Backend die erforderlichen Bereiche meldet
- Separater Infrarotkanal nur dann, wenn das Backend ihn tatsächlich liefern kann
- Hardware-Mehrfachbelichtung nur, wenn `--scan-exposure-time` den benötigten Belichtungsplan abdeckt
- Beenden ausschließlich des `scanimage`-Prozesses der aktuellen Plug-in-Instanz

Der Modellname allein schaltet keine Funktion frei.<br>
negaflow zeigt nur Optionen an, die das angeschlossene Gerät und sein aktives SANE-Backend melden.

## Voraussetzungen

- macOS 14.0 oder neuer für den aktuellen Installationsweg mit negaflow und Homebrew
- negaflow
- [SANE backends](https://formulae.brew.sh/formula/sane-backends) zur Laufzeit
- Swift 5.9 oder neuer nur beim Bauen aus dem Quellcode

`Package.swift` behält für die eigenständige ausführbare Datei ein macOS-13-Deployment-Target.<br>
Der hier beschriebene vollständige Weg beginnt bei macOS 14, da er den aktuellen Anforderungen von negaflow und Homebrew folgt.

## Installation

### 1. Komplettinstaller

Falls die Xcode Command Line Tools noch fehlen, installieren Sie sie zuerst:

```bash
xcode-select --install
```

Es werden zwei Installationsprogramme veröffentlicht. Laden Sie eines davon unter [Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) herunter, öffnen Sie es und starten Sie `Install negaflow Scanner.pkg`.

| Installationsprogramm | Vorgesehen für | Plug-in-Binärdatei |
|---|---|---|
| `negaflow-scanner-sane-1.0.0-macos-arm64-installer.dmg` | Apple-Silicon-Macs (M1 oder neuer) | nur `arm64` |
| `negaflow-scanner-sane-1.0.0-macos-universal-installer.dmg` | Apple-Silicon- und Intel-Macs | `arm64` + `x86_64` |

Beide bieten denselben Funktionsumfang.<br>
Die Apple-Silicon-Variante ist kleiner und lässt sich auf Intel-Macs nicht installieren; die Universal-Variante läuft auf allen Macs.

Wenn Homebrew fehlt, installiert das Paket zuerst die offizielle Homebrew-Komponente, danach `sane-backends` für den angemeldeten Benutzer und schließlich das negaflow-Plug-in.<br>
Internetzugang und ein Administratorpasswort sind erforderlich.<br>
Eine vorhandene Homebrew-Installation wird weiterverwendet.

Starten Sie negaflow anschließend neu, öffnen Sie „Scanner laden“, prüfen Sie die Plug-in-Angaben und geben Sie es frei.

### 2. Homebrew und SANE manuell installieren

Falls Homebrew noch fehlt, verwenden Sie den aktuellen offiziellen Installationsbefehl:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Der Befehl lädt das Homebrew-Installationsprogramm herunter und führt es aus.<br>
Prüfen Sie vorher, dass die Adresse exakt `raw.githubusercontent.com/Homebrew/install/HEAD/install.sh` lautet.<br>
Alternativ verlinkt die [offizielle Homebrew-Website](https://brew.sh/) ein signiertes `.pkg`-Installationsprogramm.

Führen Sie anschließend die ausgegebenen **Next steps** aus, damit `brew` in die Shell-Umgebung aufgenommen wird.<br>
Öffnen Sie ein neues Terminal und prüfen Sie den Befehl:

```bash
brew --version
```

Installieren Sie die SANE-Backends.<br>
Falls sie bereits vorhanden sind, meldet derselbe Befehl den bestehenden Stand.

```bash
brew install sane-backends
```

Prüfen Sie den installierten Befehl und die Version:

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends
```

Auf Apple-Silicon-Macs liegt `scanimage` üblicherweise unter `/opt/homebrew/bin/scanimage`, auf Intel-Macs unter `/usr/local/bin/scanimage`.<br>
Das Plug-in prüft beide Orte, auch wenn eine GUI-Anwendung einen kürzeren `PATH` erhält.<br>
Die SANE-Konfiguration liegt normalerweise unter `/opt/homebrew/etc/sane.d` oder `/usr/local/etc/sane.d`.

### 3. Scanner anschließen und mit SANE prüfen

Schalten Sie den Scanner ein, verbinden Sie ihn nach Möglichkeit direkt per USB und führen Sie aus:

```bash
scanimage -L
```

Kopieren Sie die vollständige Geräte-ID einschließlich Backend und USB-Adresse.<br>
Prüfen Sie danach die Optionen, die genau dieses Gerät meldet:

```bash
scanimage -d '<device-id>' -A
```

Eine Geräte-ID kann wie `genesys:libusb:001:002` aussehen.<br>
Übernehmen Sie dieses Beispiel nicht wörtlich, sondern verwenden Sie den auf dem aktuellen Mac von `scanimage -L` ausgegebenen Wert.

`sane-find-scanner` beweist nur, dass ein USB- oder SCSI-Gerät gefunden wurde.<br>
Es kann auch Scanner auflisten, für die kein verwendbares SANE-Backend existiert.<br>
Erscheint das Gerät nicht in `scanimage -L`, kann dieses Plug-in es nicht verwenden.<br>
Prüfen Sie zuerst die USB-Verbindung, die [SANE-Geräteliste](https://www.sane-project.org/sane-supported-devices.html) und die Dokumentation des betreffenden Backends.

### 4A. Plug-in aus dem Quellcode bauen und installieren

```bash
git clone https://github.com/habinsong/negaflow-scanner-sane.git
cd negaflow-scanner-sane
./install.sh
```

Das Skript erzeugt einen Release-Build und installiert diese beiden Dateien:

```text
~/Library/Application Support/negaflow/Plugins/sane/
  ├── negaflow-scanner-sane
  └── manifest.json
```

### 4B. Veröffentlichte ZIP-Datei installieren

Entpacken Sie die Release-ZIP-Datei und starten Sie das enthaltene Installationsskript:

```bash
./install.sh
```

Für das vorgefertigte Paket ist keine Swift-Toolchain nötig.<br>
SANE muss trotzdem separat installiert sein.

### 5. In negaflow freigeben und prüfen

Starten Sie negaflow neu und öffnen Sie „Scanner laden“.<br>
Prüfen Sie Pfad, Version, Lizenz und Hashes des Plug-ins und geben Sie es frei.<br>
Ändert ein Update die ausführbare Datei oder das Manifest, ist eine erneute Freigabe erforderlich.

Die installierte ausführbare Datei lässt sich auch direkt prüfen:

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

Eine Antwort `{"devices":[...]}` zeigt, dass das Plug-in gestartet ist.<br>
Ein leeres `devices`-Array bedeutet, dass das Plug-in läuft, SANE aber keinen verwendbaren Scanner zurückgegeben hat.<br>
Eine erneute Plug-in-Installation ergänzt keine fehlende Backend-Unterstützung; prüfen Sie dann erneut ab `scanimage -L`.

## Scanner-Unterstützung

Die folgende Tabelle beschreibt bekannte SANE-1.4-Ziele und die zugehörigen Pfade dieses Plug-ins.<br>
Sie garantiert nicht, dass jedes Gerät mit demselben Produktnamen funktioniert.<br>
Prüfen Sie die [aktuelle SANE-Geräteliste](https://www.sane-project.org/sane-supported-devices.html) und danach das angeschlossene Gerät mit `scanimage -L` und `scanimage -A`.

| Scannerfamilie | SANE-Backend | SANE-1.4-Status | Plug-in-Pfad |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400, 7500i, 7600i, 8100 | `genesys` | Complete | Dedizierter Filmscanner |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | Dedizierter Filmscanner |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | `genesys` | Unsupported | Wird nicht als verwendbar behandelt |
| Epson Perfection V700/V750, V800/V850 | `epson2` | Good | Durchlichteinheit und positionierter Flachbettbereich, wenn gemeldet |
| Nikon Coolscan/LS-Reihe | `coolscan3`; alte SCSI-Modelle mit `coolscan` | Je nach Modell Complete bis Minimal | Dedizierter Filmscanner |
| Reflecta ProScan/CrystalScan/DigitDia und PIE PowerSlide | `pieusb`; alte SCSI-Modelle mit `pie` | Je nach Modell | Nur gemeldete Optionen |
| Weitere Flachbett- und Filmscanner für Durchlicht | Unterschiedlich | Je nach Modell | Fähigkeitsgesteuert, kein Rückgriff auf den Modellnamen |

Den OpticFilm 8200i gibt es unter derselben Produktbezeichnung in mindestens zwei USB-Varianten.<br>
`07b3:130d` und `07b3:1825` haben nicht denselben SANE-Unterstützungsstatus.<br>
Maßgeblich ist die tatsächliche USB product ID, nicht nur der Name auf dem Gehäuse.

## Infrarotkanal

„IR verfügbar“ bedeutet hier, dass ein separates Infrarotbild als `irPath` an negaflow zurückgegeben werden kann.<br>
Eine interne Staubkorrektur des Backends wird nicht als IR-Kanal gemeldet.

| Scanner- oder Backend-Pfad | IR-Status | Erfassung | Separate IR-TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Nicht verfügbar | Diese Modelle melden keine IR-Quelle | Nein |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Verfügbar, wenn `scanimage -A` die IR-Quelle meldet | Separater Durchlauf mit `Transparency Adapter Infrared` | Ja |
| OpticFilm 8200i `07b3:1825` | Nicht verfügbar | Variante wird von SANE 1.4 nicht unterstützt | Nein |
| Epson V700/V750/V800/V850 mit regulärem `epson2` | Nicht verfügbar | Reguläre Builds melden keinen separaten IR-Modus | Nein |
| Angepasster Epson-Pfad mit `SANE_FRAME_IR` | Bedingt | Separater `Infrared`-Durchlauf, nur wenn gemeldet | Ja |
| Nikon `coolscan3` mit `--infrared` | Mit regulärem `scanimage` nicht verfügbar | `coolscan3` liefert einen `SANE_FRAME_RGBI`-Frame; `scanimage` 1.4 trennt ihn nicht in RGB- und IR-TIFF | Nein |
| Reflecta/PIE nur mit `--clean-image` | Nicht als IR-Kanal verfügbar | Staubkorrektur erfolgt im Backend | Nein |
| Sonstige Scanner | Bedingt | Nur wenn `scanimage -A` eine aktive, separate IR-Quelle oder einen IR-Modus meldet | Ja, nach Format- und Größenprüfung |

Der IR-Durchlauf verwendet dieselbe angeforderte Auflösung und denselben Scanbereich wie RGB.<br>
Vor der Rückgabe prüft das Plug-in außerdem, ob beide Bilder dieselben Pixelabmessungen haben.<br>
negaflow kann das IR-Bild anschließend für GrainMend IR verwenden.

## Fehlersuche: kein Scanner gefunden

**Freigegeben** bedeutet in negaflow, dass die Plug-in-Programmdatei ausgeführt werden darf.<br>
Es bedeutet nicht, dass ein Scanner gefunden wurde. Die Erkennung ist genau das, was `scanimage -L`
zurückgibt. Ein Scanner, der dort fehlt, fehlt auch in negaflow, und eine Neuinstallation von App
oder Plug-in ändert daran nichts.

macOS kennt keine USB-Berechtigung, die pro App freigeschaltet wird. Weder negaflow noch dieses
Plug-in verwenden die App Sandbox, daher blockiert auch keine Einstellung unter
„Datenschutz & Sicherheit“ den Zugriff auf den Scanner.

### 1. Die fehlerhafte Ebene eingrenzen

Bei eingeschaltetem und angeschlossenem Scanner der Reihe nach ausführen.

```bash
system_profiler SPUSBDataType
```

```bash
scanimage -L
```

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

| USB-Liste | `scanimage -L` | `detect` | Wo das Problem liegt |
|---|---|---|---|
| Kein Scanner | Nichts | `{"devices":[]}` | Kabel, Anschluss oder Stromversorgung, noch vor SANE |
| Scanner gelistet | Nichts | `{"devices":[]}` | SANE-Backend oder ein anderer Prozess, der das Gerät belegt |
| Scanner gelistet | Gerät gelistet | `{"devices":[]}` | SANE an einem Ort installiert, den das Plug-in nicht durchsucht |
| Scanner gelistet | Gerät gelistet | Gerät gelistet | Auf negaflow-Seite: „Scanner laden“ erneut öffnen und erneut freigeben |

### 2. Häufige Ursachen

| Symptom | Ursache | Vorgehen |
|---|---|---|
| `scanimage: command not found` | `sane-backends` fehlt oder liegt unter dem anderen Homebrew-Präfix | `command -v scanimage` prüfen. Apple Silicon nutzt `/opt/homebrew/bin`, Intel `/usr/local/bin` |
| Der Scanner fehlt in der USB-Liste | Hub, Dock, Adapter, Kabel oder Stromversorgung | Direkt am Mac anschließen, einen anderen Anschluss probieren und Hubs vermeiden. USB-2.0-Filmscanner scheitern häufig an USB-C-Adaptern |
| `no SANE devices found`, obwohl `sane-find-scanner` das Gerät sieht | Kein aktives Backend ist für dieses Modell zuständig | Die [SANE-Geräteliste](https://www.sane-project.org/sane-supported-devices.html) prüfen und danach das Protokoll aus Schritt 3 lesen |
| `another process has device opened for exclusive access`, `device busy`, `is not configured` | Ein anderes Programm belegt bereits die USB-Schnittstelle | VueScan, SilverFast, Digitale Bilder und Herstellerwerkzeuge beenden, den Scanner neu anschließen und erneut versuchen |
| Nur `sudo scanimage -L` findet das Gerät | Die Schnittstelle ist belegt oder wurde nie freigegeben | Zuerst die Belegung oben lösen. negaflow startet das Plug-in nie als root, `sudo` ist daher keine Lösung |
| Terminal findet es, negaflow nicht | SANE liegt außerhalb der Standardpräfixe | Das Plug-in sucht nur unter `/opt/homebrew`, `/usr/local` und `/usr`. MacPorts (`/opt/local`) und selbst gebaute Präfixe werden nicht verwendet, daher `sane-backends` mit Homebrew installieren |
| `open of device ... failed: Invalid argument` | Die USB-Adresse hat sich nach dem ersten Öffnen geändert, oder das SANE-Konfigurationsverzeichnis fehlt | `detect` erneut ausführen und prüfen, ob `/opt/homebrew/etc/sane.d` oder `/usr/local/etc/sane.d` vorhanden ist |
| Vor einem `brew upgrade` funktionierte es | Backend-Regression in einer neueren `sane-backends`-Version | `brew list --versions sane-backends` mit der funktionierenden Version vergleichen |
| Leere Liste nach Installation eines älteren negaflow-Plug-ins | Eine alte Version hat Backends in `dll.conf` deaktiviert | `repair-sane-config` ausführen, beschrieben unter [SANE-Konfiguration](#sane-konfiguration) |

### 3. Backend-Protokoll lesen

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

Das zeigt, welche Backends geladen werden und welche scheitern.<br>
Um auf ein Backend einzugrenzen, dessen eigene Variable verwenden, etwa `SANE_DEBUG_GENESYS=128`
oder `SANE_DEBUG_EPSON2=128`.

Eine Meldung ist nur mit macOS-Version, Mac-Modell, `scanimage --version`,
`brew list --versions sane-backends`, Scannermodell und der Ausgabe der drei Schritte oben
verwertbar.

## Exakte Werte und Fehlerverhalten

- Die angeforderte DPI-Zahl muss exakt in der Liste oder im Bereich des Geräts liegen. Es wird nicht
  auf die nächste Auflösung gerundet.
- Eine 16-bit-Anforderung gelingt nur, wenn die SANE-Tiefe größer als 8 und die dekodierte Datei
  tatsächlich eine 16-bit-TIFF ist.
- Ein physischer Scanbereich wird nur bei nutzbaren Millimeterbereichen für `-x/-y` gemeldet.
  Positionierung benötigt zusätzlich `-l/-t`.
- Abhängige Optionen werden nach Anwendung von source, mode, depth, resolution, preview und geometry
  erneut geprüft.
- Eine Vorschau fügt nicht still IR oder Mehrfachbelichtung hinzu.
- Brightness, contrast und gamma ersetzen keine Hardware-Mehrfachbelichtung.
- Ein abweichendes oder ungeprüftes Ergebnis wird verworfen und als Fehler zurückgegeben.

## negaflow-Scannerprotokoll

Die ausführbare Datei wird mit Unterbefehlen aufgerufen und schreibt JSON auf die Standardausgabe.

| Befehl | Eingabe | Ausgabe |
|---|---|---|
| `detect` | Keine | Geräteliste als JSON |
| `capabilities <deviceId>` | Optionale Geräteidentität aus der Erkennung als JSON | Auflösung, Modus, Bittiefe, Bereich, Belichtung und IR als JSON |
| `scan` | Protocol-v2-Anfrage über stdin | NDJSON-Fortschritt und abschließendes Ergebnis oder Fehler |
| `repair-sane-config` | Keine | Aktiviert nur von älteren negaflow-Versionen deaktivierte Backends wieder |
| `tune-sane` | Keine | Kompatibilitätsalias für `repair-sane-config` |
| `restore-sane` | Keine | Stellt die vollständige alte Sicherung nur als letzte Möglichkeit wieder her |

Jedes Protocol-v2-Ereignis enthält `protocolVersion`, `requestID` und eine steigende `sequence`.<br>
`appliedOptions` wird erst zurückgegeben, nachdem Ausgabe-TIFF und tatsächlich angewandte Werte geprüft wurden.
negaflow gibt das undurchsichtige `capabilityToken` aus `capabilities` automatisch mit der folgenden
Scan-Anfrage zurück. Direkte CLI-Aufrufer sollten denselben Wert mitsenden; ohne ihn läuft die langsamere
Kompatibilitätsprüfung.

Beispiel für einen vollständigen Scan:

```json
{
  "protocolVersion": 2,
  "requestID": "7A91B43D-90F8-41E2-B71D-04D17CD9E03B",
  "deviceID": "sane-genesys:libusb:001:002",
  "capabilityToken": "<undurchsichtiges Token aus capabilities>",
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

## SANE-Konfiguration

Aktuelle Versionen filtern Homebrews gemeinsame `dll.conf` nicht.<br>
`detect` repariert automatisch nur Zeilen, die eine ältere Version des negaflow-Plugins deaktiviert hat, und bewahrt Kommentare der Distribution und des Benutzers. Dieselbe Reparatur kann manuell ausgeführt werden:

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

Falls noch eine alte `dll.conf.negaflow-backup` vorhanden ist, ersetzt der folgende Befehl die gesamte aktuelle Datei durch diese Sicherung. Dabei gehen auch spätere Änderungen zurück; verwenden Sie ihn nur, wenn die gezielte Reparatur nicht ausreicht:

```bash
.build/release/negaflow-scanner-sane restore-sane
```

## Repository

| Pfad | Aufgabe |
|---|---|
| `Sources/SANEPluginCore` | SANE-Erkennung, Fähigkeiten, Erfassung, TIFF-Prüfung, IR und Belichtungszusammenführung |
| `Sources/negaflow-scanner-sane` | Schlanker JSON/CLI-Adapter für das negaflow-Scannerprotokoll v2 |
| `Tests/SANEPluginCoreTests` | Tests für Protokoll, Prozesse, Optionen, TIFF und virtuelle Scanner |
| `Installer` | Komplett-PKG, Installationsskripte und Ressourcen für Installer.app |
| `scripts` | Universal-Build, Signatur, Paket, Installation, Notarisierung und Release-Prüfung |

## Entwicklungsprüfungen

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

Die modellspezifischen virtuellen Scannertests führen echte Unterprozesse aus und prüfen TIFF-Verträge für Vorschau, vollständigen Scan, Scanbereiche und IR.<br>
Scannermechanik, Optik, USB-Transport und endgültige Bildqualität werden nicht emuliert; die Tests gelten daher nicht als Nachweis an realer Hardware.

## Release-Build

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

Das Skript baut `arm64` und `x86_64`, verbindet beide zu einer Universal-Datei, erzeugt ein dSYM, signiert und verpackt das Plug-in, schreibt SHA-256-Prüfsummen und prüft das Archiv.<br>
Die Ausgabe liegt unter `.build/release-artifacts/`.

Für Distributionssignatur und Notarisierung werden zusätzlich `NEGAFLOW_CODESIGN_IDENTITY`, `NEGAFLOW_NOTARY_KEYCHAIN_PROFILE` und `NEGAFLOW_RELEASE_MODE=distribution` benötigt.

Das eigenständige PKG und DMG erstellen Sie mit:

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

Dieser Build prüft das festgelegte offizielle Homebrew-Paket vor der Übernahme seiner Installer-Komponente, erstellt anschließend die Apple-Silicon- und die Universal-Variante und kontrolliert jedes PKG und DMG ohne Installation.<br>
Mit `NEGAFLOW_INSTALLER_ARCHITECTURE` auf `arm64` oder `universal` wird nur eine Variante gebaut; der Standardwert `all` baut beide.<br>
Für den Distributionsmodus werden zusätzlich `NEGAFLOW_INSTALLER_MODE=distribution`, eine `NEGAFLOW_INSTALLER_IDENTITY` für das PKG sowie die bereits verwendete App-Signaturidentität und das Notarisierungsprofil benötigt.

## Lizenz

Dieses Projekt wird unter [GPL-2.0-or-later](LICENSE) veröffentlicht.<br>
Release-Archive enthalten den Lizenzhinweis und den vollständigen Text der GNU GPL v2 in [COPYING](COPYING).

Der Komplettinstaller enthält außerdem die [Hinweise zu Drittsoftware](THIRD_PARTY_NOTICES.md) für die enthaltene Homebrew-Komponente und die über das Netzwerk installierten SANE-Backends.<br>
Das vollständige Quellarchiv derselben Plug-in-Version wird neben dem Release-ZIP veröffentlicht und<br>
ist außerdem im ZIP, im PKG-Inhalt und im DMG enthalten.

negaflow ist ein getrenntes Apache-2.0-Projekt.<br>
Produkt- und Scannernamen dienen nur zur Bezeichnung kompatibler oder vermessener Ziele und bleiben Eigentum der jeweiligen Rechteinhaber.
