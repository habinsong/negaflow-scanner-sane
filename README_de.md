<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">SANE-Filmscanner-Plug-in für negaflow unter macOS</p>

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/de/"><img src="https://img.shields.io/badge/website-negaflow-1F6FEB" alt="Website"></a>
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

<p align="center">
  <a href="https://habinsong.github.io/negaflow-site/de/">Website</a> ·
  <a href="https://habinsong.github.io/negaflow-site/de/camera-scanning/">Anleitung zum Abfotografieren</a> ·
  <a href="https://habinsong.github.io/negaflow-site/de/faq/">FAQ</a>
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
- Standard-`sane-backends` von Homebrew für normale Scanner
- macOS 26 oder neuer nur für den separaten gepatchten Nikon-Coolscan-Weg
- Swift 5.9 oder neuer nur beim Bauen aus dem Quellcode

`Package.swift` behält für die eigenständige ausführbare Datei ein macOS-13-Deployment-Target.<br>
Der hier beschriebene vollständige Weg beginnt bei macOS 14, da er den aktuellen Anforderungen von negaflow und Homebrew folgt.

## Installation

### 1. Komplettinstaller

Falls die Xcode Command Line Tools noch fehlen, installieren Sie sie zuerst:

```bash
xcode-select --install
```

Es werden vier Installationsprogramme veröffentlicht. Verwenden Sie die Standardvariante für
normale SANE-Scanner und die separate Coolscan-Variante unter macOS 26 oder neuer.

| Installationsprogramm | SANE-Weg | Plug-in-Binärdatei |
|---|---|---|
| `negaflow-scanner-sane-1.0.3-macos-arm64-installer.dmg` | Standard, macOS 14+ | nur `arm64` |
| `negaflow-scanner-sane-1.0.3-macos-universal-installer.dmg` | Standard, macOS 14+ | `arm64` + `x86_64` |
| `negaflow-scanner-sane-1.0.3-coolscan-macos26-arm64-installer.dmg` | Gepatchter Coolscan, macOS 26+ | nur `arm64` |
| `negaflow-scanner-sane-1.0.3-coolscan-macos26-universal-installer.dmg` | Gepatchter Coolscan, macOS 26+ | `arm64` + `x86_64` |

Das Standard-DMG enthält `Install negaflow Scanner.pkg`; das Coolscan-DMG enthält
`Install negaflow Scanner for Coolscan.pkg`.

Die Standardvariante installiert Homebrews `sane-backends`. Die Coolscan-Variante baut
`sane-backends-negaflow` aus offiziellem SANE 1.4.0 und wendet nur den upstream
`coolscan2`/`coolscan3`-Allokationsfix sowie einen `epson2`-Scanhöhen-Fix an.<br>
Internetzugang und ein Administratorpasswort sind erforderlich.<br>
Eine vorhandene Homebrew-Installation wird weiterverwendet.

Standardvariante und macOS-Versionen unter 26 blockieren Coolscan nicht. Stock SANE kann auf
einzelnen Geräten funktionieren, enthält aber den Fix nicht; unterstützt gepatcht ist die
Coolscan-Variante für macOS 26.

Eine spätere Upstream-Änderung initialisiert zusätzlich die Coolscan3-Parameterblöcke für
Load/Eject/Reset, die mindestens bei LS-5000-Firmware 1.03 erforderlich sind. Sie bleibt bewusst
außerhalb dieses minimalen Patch-Satzes; Laden, Auswerfen und Zurücksetzen des LS-5000 sind daher
auch mit der gepatchten Variante ungetestet und können fehlschlagen.

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

Standardweg ab macOS 14:

```bash
brew install sane-backends
```

Gepatchter Coolscan-Weg ab macOS 26:

```bash
bash scripts/install-patched-sane.sh
export PATH="$(brew --prefix sane-backends-negaflow)/bin:$PATH"
```

Prüfen Sie den installierten Befehl und die Version:

```bash
command -v scanimage
scanimage --version
brew list --versions sane-backends sane-backends-negaflow
```

Wenn das gepatchte Keg vorhanden ist, verwendet das Plug-in dessen absoluten Pfad sowie die
zugehörigen Verzeichnisse `etc/sane.d` und `lib/sane`.

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

Für das vorgefertigte Paket ist keine Swift-Toolchain nötig. `install.sh` installiert nur das
Plug-in; installieren Sie vorher Standard-SANE oder die Coolscan-Variante für macOS 26.

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
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i | `genesys` | Complete | Dedizierter Filmscanner |
| Plustek OpticFilm 7400 v1 | `genesys` | Als Complete gelistet, modellspezifische Korrekturen kamen jedoch erst nach SANE 1.4.0 | Capability-gesteuerter Pfad; Hardwareergebnis mit stock 1.4.0 nicht verifiziert |
| Plustek OpticFilm 8100, USB `07b3:130c` | `genesys` | Complete | Dedizierter Filmscanner |
| Plustek OpticFilm 8100, USB `07b3:1824` | Keins | Unsupported | Wird nicht als verwendbar behandelt |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | Dedizierter Filmscanner |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | Keins | Unsupported | Wird nicht als verwendbar behandelt |
| Plustek OpticFilm 120, 120 Pro, 135, 135i, 9000i Ai | Keins | Unsupported | Wird nicht als verwendbar behandelt |
| Epson Perfection V700/V750 (GT-X900), V800/V850 (GT-X980) | `epson2` | Good | Durchlichteinheit und positionierter Flachbettbereich, wenn gemeldet |
| Nikon Coolscan LS-2000, LS-40 ED, LS-50 ED, LS-4000 ED, LS-8000 ED | `coolscan3` | Je nach Modell Complete bis Minimal | Dedizierter Filmscanner |
| Nikon Coolscan LS-5000 ED | `coolscan3` | In SANE 1.4 ungetestet; könnte wie der LS-50 funktionieren | Dedizierter Filmscanner |
| Nikon Coolscan LS-20, LS-30, LS-1000 | `coolscan` | Je nach Modell | Nur SCSI |
| Nikon Coolscan LS-9000 ED | Keins | Unsupported | Wird nicht als verwendbar behandelt |
| Reflecta ProScan/CrystalScan/DigitDia und PIE PowerSlide | `pieusb`; alte SCSI-Modelle mit `pie` | Je nach Modell und Modellnummer | Nur gemeldete Optionen |
| Pacific Image PrimeFilm XA, XAs, XA Plus | Keins | Unsupported | Wird nicht als verwendbar behandelt |
| Weitere Flachbett- und Filmscanner für Durchlicht | Unterschiedlich | Je nach Modell | Fähigkeitsgesteuert, kein Rückgriff auf den Modellnamen |

### Der Produktname sagt nichts über die Hardware

Den OpticFilm 8100 und den 8200i gibt es jeweils unter derselben Produktbezeichnung in mindestens
zwei USB-Varianten.<br>
`07b3:130c` und `07b3:130d` werden von `genesys` angesteuert, `07b3:1824` und `07b3:1825` dagegen
nicht, weil sie einen anderen Genesys-Chip verwenden, den kein Backend bedient.<br>
Eine neuere Revision unter altem Namen lässt sich auf SANE-Seite nicht beheben. Maßgeblich ist
daher die tatsächliche USB product ID, nicht der Name auf dem Gehäuse.

Zwei weitere Stolperfallen bei der Identifikation sind wichtig.

- `pieusb` vergleicht die USB-ID **und** eine Modellnummer. Reflecta- und PIE-Geräte teilen sich
  IDs wie `05e3:0145`, daher ist ein Gerät nur verwendbar, wenn seine Modellnummer in
  `pieusb.conf` steht.
- `epson2` kennt Epson-Scanner unter ihren japanischen Modellnamen. `scanimage -L` meldet einen
  Perfection V800/V850 als `GT-X980` und einen V700/V750 als `GT-X900`. Das ist derselbe Scanner
  und kein falsches Gerät.

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
| `scanimage: command not found` | SANE ist nicht installiert oder sein `bin` fehlt im aktuellen `PATH` | Standard-`sane-backends` installieren; für Coolscan den gepatchten Helfer und den obigen `export` verwenden |
| Der Scanner fehlt in der USB-Liste | Hub, Dock, Adapter, Kabel oder Stromversorgung | Direkt am Mac anschließen, einen anderen Anschluss probieren und Hubs vermeiden. USB-2.0-Filmscanner scheitern häufig an USB-C-Adaptern |
| `no SANE devices found`, obwohl `sane-find-scanner` das Gerät sieht | Kein aktives Backend ist für dieses Modell zuständig | Die [SANE-Geräteliste](https://www.sane-project.org/sane-supported-devices.html) prüfen und danach das Protokoll aus Schritt 3 lesen |
| Der Scanner steht in der USB-Liste, `scanimage -L` bleibt leer und `repair-sane-config` meldet `notNeeded` | Eine Hardware-Revision, die SANE nicht kennt | Die USB product ID mit der Tabelle [Scanner-Unterstützung](#scanner-unterstützung) vergleichen. Eine neuere Revision unter altem Produktnamen lässt sich von dieser Seite nicht beheben |
| Ein Coolscan LS-50 oder LS-5000 verschwindet aus der USB-Liste | Bekannter Defekt des USB-Anschlusses bei diesen Geräten | Mit anderem Kabel und Anschluss prüfen. Wenn der Mac das Gerät nie aufzählt, ist es ein Hardwaredefekt und kein Treiberproblem |
| `another process has device opened for exclusive access`, `device busy`, `is not configured` | Ein anderes Programm belegt bereits die USB-Schnittstelle | VueScan, SilverFast, Digitale Bilder und Herstellerwerkzeuge beenden, den Scanner neu anschließen und erneut versuchen |
| Nur `sudo scanimage -L` findet das Gerät | Die Schnittstelle ist belegt oder wurde nie freigegeben | Zuerst die Belegung oben lösen. negaflow startet das Plug-in nie als root, `sudo` ist daher keine Lösung |
| Terminal findet es, negaflow nicht | SANE liegt außerhalb der unterstützten Homebrew-Keg-Pfade | Den enthaltenen Installer erneut ausführen; MacPorts und andere manuelle Präfixe werden nicht verwendet |
| `open of device ... failed: Invalid argument` | Die USB-Adresse hat sich nach dem ersten Öffnen geändert, oder das SANE-Konfigurationsverzeichnis fehlt | `detect` erneut ausführen und prüfen, ob `/opt/homebrew/etc/sane.d` oder `/usr/local/etc/sane.d` vorhanden ist |
| Vor einer Aktualisierung funktionierte es | Das ausgewählte SANE-Keg wurde entfernt oder ersetzt | Den passenden Installer erneut ausführen und `brew list --versions sane-backends sane-backends-negaflow` prüfen |
| Leere Liste nach Installation eines älteren negaflow-Plug-ins | Eine alte Version hat Backends in `dll.conf` deaktiviert | `repair-sane-config` ausführen, beschrieben unter [SANE-Konfiguration](#sane-konfiguration) |

### 3. Backend-Protokoll lesen

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

Das zeigt, welche Backends geladen werden und welche scheitern.<br>
Um auf ein Backend einzugrenzen, dessen eigene Variable verwenden, etwa `SANE_DEBUG_GENESYS=128`
oder `SANE_DEBUG_EPSON2=128`.

Eine Meldung ist nur mit macOS-Version, Mac-Modell, `scanimage --version`,
`brew list --versions sane-backends sane-backends-negaflow`, Scannermodell und der Ausgabe der drei Schritte oben
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

Die Capabilities werden in dem Zustand gelesen, in dem der Scan tatsächlich läuft. SANE-Optionen ändern die Aktivierung anderer Optionen: `epson2` deaktiviert die Tiefe in Lineart und die Helligkeit, sobald ein lineares Gamma gewählt ist. Ein Auslesen im Standardzustand beschreibt den Scan daher nicht. Das Plug-in setzt Durchlichtquelle, Scanmodus sowie die neutralen Farb- und Gammawerte, liest die Optionen in diesem Zustand und hält ihn im Token fest; ein anderer angeforderter Modus wird in diesem Modus neu gelesen.

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

Das gepatchte Keg nutzt sein eigenes `etc/sane.d` und ändert die `dll.conf` einer normalen Homebrew-Installation nicht.<br>
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
Mit `NEGAFLOW_INSTALLER_VARIANT=all` werden Standard- und Coolscan-Familie gebaut; standardmäßig wird nur die Standardfamilie gebaut.<br>
Für den Distributionsmodus werden zusätzlich `NEGAFLOW_INSTALLER_MODE=distribution`, eine `NEGAFLOW_INSTALLER_IDENTITY` für das PKG sowie die bereits verwendete App-Signaturidentität und das Notarisierungsprofil benötigt.

## Lizenz

Dieses Projekt wird unter [GPL-2.0-or-later](LICENSE) veröffentlicht.<br>
Release-Archive enthalten den Lizenzhinweis und den vollständigen Text der GNU GPL v2 in [COPYING](COPYING).

Die Installer enthalten außerdem die [Hinweise zu Drittsoftware](THIRD_PARTY_NOTICES.md) für
die enthaltene Homebrew-Komponente und, bei der Coolscan-Variante, die auf dem Mac des Benutzers
gebauten gepatchten SANE-Quellen.<br>
Das vollständige Quellarchiv derselben Plug-in-Version wird neben dem Release-ZIP veröffentlicht und<br>
ist außerdem im ZIP, im PKG-Inhalt und im DMG enthalten.

negaflow ist ein getrenntes Apache-2.0-Projekt.<br>
Produkt- und Scannernamen dienen nur zur Bezeichnung kompatibler oder vermessener Ziele und bleiben Eigentum der jeweiligen Rechteinhaber.
