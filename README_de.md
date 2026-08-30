<h1 align="center">negaflow-scanner-sane</h1>

<p align="center">Das negaflow SANE Filmscanner-Plug-in, für macOS und für Windows</p>

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
- Der Infrarotdurchgang erhält dieselbe Gammatabelle und denselben Fokus wie der Hauptscan, so bleibt die Filmbasis unbeschnitten und beide Durchgänge teilen eine Schärfeebene
- Hardware-Mehrfachbelichtung nur, wenn `--scan-exposure-time` den benötigten Belichtungsplan abdeckt
- Beenden ausschließlich des `scanimage`-Prozesses der aktuellen Plug-in-Instanz

Der Modellname allein schaltet keine Funktion frei.<br>
negaflow zeigt nur Optionen an, die das angeschlossene Gerät und sein aktives SANE-Backend melden.

## Voraussetzungen

- negaflow, vorher installiert
- Ein Filmscanner, den SANE unterstützt
- macOS 14.0 oder neuer, oder Windows 11

## Installation

Die beiden Systeme unterscheiden sich genug, dass jedes eine eigene Seite hat.

| Plattform | Seite |
|---|---|
| macOS | [Unter macOS installieren](negaflow-mac/docs/README_de.md) |
| Windows | [Unter Windows installieren](negaflow-windows/docs/README_de.md) |

Kurz gefasst: Laden Sie unter
[Releases](https://github.com/habinsong/negaflow-scanner-sane/releases) das
Installationsprogramm für Ihr System herunter, starten Sie es, öffnen Sie negaflow neu und
bestätigen Sie das Plug-in. Unter macOS richtet das Installationsprogramm SANE über
Homebrew mit ein. Unter Windows stecken die SANE-Programme bereits im Installationsprogramm.

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
| Epson V700/V750/V800/V850 mit dem `mac26`-Installer | Verfügbar, wenn `scanimage -A` den Infrarotmodus meldet | Separater `Infrared`-Durchlauf des gepatchten `epson2` | Ja |
| Epson V700/V750/V800/V850 mit regulärem `epson2` | Nicht verfügbar | Reguläre Builds lassen `SANE_FRAME_IR` auskompiliert | Nein |
| Nikon `coolscan3` mit `--infrared` | Mit regulärem `scanimage` nicht verfügbar | `coolscan3` liefert einen `SANE_FRAME_RGBI`-Frame; `scanimage` 1.4 trennt ihn nicht in RGB- und IR-TIFF | Nein |
| Reflecta/PIE nur mit `--clean-image` | Nicht als IR-Kanal verfügbar | Staubkorrektur erfolgt im Backend | Nein |
| Sonstige Scanner | Bedingt | Nur wenn `scanimage -A` eine aktive, separate IR-Quelle oder einen IR-Modus meldet | Ja, nach Format- und Größenprüfung |

Der IR-Durchlauf verwendet dieselbe angeforderte Auflösung und denselben Scanbereich wie RGB.<br>
Vor der Rückgabe prüft das Plug-in außerdem, ob beide Bilder dieselben Pixelabmessungen haben.<br>
negaflow kann das IR-Bild anschließend für GrainMend IR verwenden.

## Fehlersuche: Installation schlägt fehl

Der Fehlerbildschirm zeigt nur „Die Installation ist fehlgeschlagen". macOS Installer bewertet ein
Paketskript allein anhand des Exit-Codes und zeigt nie, was das Skript ausgegeben hat. Drücken Sie
⌘L, solange der Installer offen ist, oder lesen Sie danach das Protokoll:

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| Protokoll | Ursache |
|---|---|
| `Your Command Line Tools are too outdated` | Die `mac26`-Variante kompiliert SANE, und Homebrew lehnt Command Line Tools ab, die älter als das laufende macOS sind |
| `Homebrew was not installed at the supported prefix` | Kein `brew` unter `/opt/homebrew` oder `/usr/local` |
| `no supported logged-in user was found` | Kein Konsolenbenutzer, etwa über SSH oder im Anmeldefenster |
| `patched scanimage was not installed` | SANE-Build fehlgeschlagen; der Homebrew-Fehler steht oberhalb dieser Zeile |

Bei veralteten Command Line Tools:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
```

```bash
xcode-select --install
```

Eine veraltete Installation behält `git`, eine reine Dateiprüfung hält sie deshalb für vorhanden.
Der Installer sucht stattdessen das SDK des laufenden macOS und bricht ab, bevor irgendetwas
installiert wird.

Homebrew ist keine Voraussetzung. Das Paket enthält den offiziellen signierten Homebrew-Installer
und führt ihn nur aus, wenn `brew` fehlt. Eine vorhandene Installation wird unverändert genutzt,
nie ersetzt oder aktualisiert.

Die `mac26`-Variante baut SANE 1.4.0 aus den Quellen, das dauert Minuten, und der Fortschrittsbalken
kann den Build-Fortschritt nicht anzeigen. Die `mac14`-Variante installiert ein
vorgebautes Bottle und ist schnell fertig.

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
| `scanimage: command not found` | SANE ist nicht installiert oder sein `bin` fehlt im aktuellen `PATH` | Standard-`sane-backends` installieren; für den gepatchten Weg den Helfer und den obigen `export` verwenden |
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
