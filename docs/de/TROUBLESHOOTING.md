# Fehlersuche

[Dokumentationsstart](README.md)

## Installation schlägt fehl

Der Fehlerbildschirm zeigt nur „Die Installation ist fehlgeschlagen“. macOS Installer bewertet ein
Paketskript allein anhand des Exit-Codes, die Ausgabe des Skripts steht im Protokoll. Drücken Sie ⌘L,
solange der Installer offen ist, oder lesen Sie danach das Protokoll:

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

Eine veraltete Installation behält `git`, eine reine Dateiprüfung hält sie deshalb für vorhanden. Der
Installer sucht stattdessen das SDK des laufenden macOS und bricht ab, bevor irgendetwas installiert
wird.

Homebrew ist keine Voraussetzung. Das Paket enthält den offiziellen signierten Homebrew-Installer und
führt ihn nur aus, wenn `brew` fehlt. Eine vorhandene Installation wird unverändert genutzt.

Die `mac26`-Variante baut SANE 1.4.0 aus den Quellen, das dauert Minuten, und der Fortschrittsbalken
kann den Build-Fortschritt nicht anzeigen. Die `mac14`-Variante installiert ein vorgebautes Bottle
und ist schnell fertig.

## Kein Scanner gefunden

**Freigegeben** bedeutet in negaflow, dass das Plug-in ausgeführt werden darf, nicht dass ein Scanner
gefunden wurde. Die Erkennung ist genau das, was `scanimage -L` zurückgibt. Ein Scanner, der dort
fehlt, fehlt auch in negaflow, und eine Neuinstallation von App oder Plug-in ändert daran nichts.

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
| Der Scanner steht in der USB-Liste, `scanimage -L` bleibt leer und `repair-sane-config` meldet `notNeeded` | Eine Hardware-Revision, die SANE nicht kennt | Die USB product ID mit [unterstützte Scanner](SCANNERS.md) vergleichen. Eine neuere Revision unter altem Produktnamen lässt sich von dieser Seite nicht beheben |
| Ein Coolscan LS-50 oder LS-5000 verschwindet aus der USB-Liste | Bekannter Defekt des USB-Anschlusses bei diesen Geräten | Mit anderem Kabel und Anschluss prüfen. Wenn der Mac das Gerät nie aufzählt, ist es ein Hardwaredefekt |
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

Das zeigt, welche Backends geladen werden und welche scheitern. Um auf ein Backend einzugrenzen,
dessen eigene Variable verwenden, etwa `SANE_DEBUG_GENESYS=128` oder `SANE_DEBUG_EPSON2=128`.

Eine Meldung ist nur mit macOS-Version, Mac-Modell, `scanimage --version`,
`brew list --versions sane-backends sane-backends-negaflow`, Scannermodell und der Ausgabe der drei
Schritte oben verwertbar.

## SANE-Konfiguration

Das gepatchte Keg nutzt sein eigenes `etc/sane.d` und ändert die `dll.conf` einer normalen
Homebrew-Installation nicht. `detect` repariert automatisch nur Zeilen, die eine ältere Version des
negaflow-Plugins deaktiviert hat, und bewahrt Kommentare der Distribution und des Benutzers. Dieselbe
Reparatur kann manuell ausgeführt werden:

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

Falls noch eine alte `dll.conf.negaflow-backup` vorhanden ist, ersetzt der folgende Befehl die
gesamte aktuelle Datei durch diese Sicherung. Dabei gehen auch spätere Änderungen zurück; verwenden
Sie ihn nur, wenn die gezielte Reparatur nicht ausreicht:

```bash
.build/release/negaflow-scanner-sane restore-sane
```
