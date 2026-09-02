# Entwicklung

[Dokumentationsstart](README.md)

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

Jedes Protocol-v2-Ereignis enthält `protocolVersion`, `requestID` und eine steigende `sequence`.
`appliedOptions` wird erst zurückgegeben, nachdem Ausgabe-TIFF und tatsächlich angewandte Werte
geprüft wurden. negaflow gibt das undurchsichtige `capabilityToken` aus `capabilities` automatisch
mit der folgenden Scan-Anfrage zurück. Direkte CLI-Aufrufer sollten denselben Wert mitsenden; ohne
ihn läuft die langsamere Kompatibilitätsprüfung.

Die Capabilities werden in dem Zustand gelesen, in dem der Scan tatsächlich läuft, denn SANE-Optionen
ändern die Aktivierung anderer Optionen. `epson2` deaktiviert die Tiefe in Lineart und die Helligkeit,
sobald ein lineares Gamma gewählt ist, ein Auslesen im Standardzustand beschreibt den Scan also
nicht. Das Plug-in setzt Durchlichtquelle, Scanmodus sowie die neutralen Farb- und Gammawerte, liest
die Optionen in diesem Zustand und hält ihn im Token fest; ein anderer angeforderter Modus wird in
diesem Modus neu gelesen.

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

## Angeforderte Werte und Fehlerverhalten

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

## Repository

| Pfad | Aufgabe |
|---|---|
| `Sources/SANEPluginCore` | SANE-Erkennung, Fähigkeiten, Erfassung, TIFF-Prüfung, IR und Belichtungszusammenführung |
| `Sources/negaflow-scanner-sane` | Schlanker JSON/CLI-Adapter für das negaflow-Scannerprotokoll v2 |
| `Tests/SANEPluginCoreTests` | Tests für Protokoll, Prozesse, Optionen, TIFF und virtuelle Scanner |
| `Installer` | Komplett-PKG, Installationsskripte und Ressourcen für Installer.app |
| `scripts` | Universal-Build, Signatur, Paket, Installation, Notarisierung und Release-Prüfung |

## Prüfungen

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
swift build -c release
.build/release/negaflow-scanner-sane detect
```

Die modellspezifischen virtuellen Scannertests führen echte Unterprozesse aus und prüfen
TIFF-Verträge für Vorschau, vollständigen Scan, Scanbereiche und IR. Scannermechanik, Optik,
USB-Transport und endgültige Bildqualität werden nicht emuliert, die Tests gelten daher nicht als
Nachweis an realer Hardware.

## Release-Build

```bash
NEGAFLOW_OVERWRITE_RELEASE=1 ./scripts/build-release.sh
```

Das Skript baut `arm64` und `x86_64`, verbindet beide zu einer Universal-Datei, erzeugt ein dSYM,
signiert und verpackt das Plug-in, schreibt SHA-256-Prüfsummen und prüft das Archiv. Die Ausgabe
liegt unter `.build/release-artifacts/`.

Für Distributionssignatur und Notarisierung werden zusätzlich `NEGAFLOW_CODESIGN_IDENTITY`,
`NEGAFLOW_NOTARY_KEYCHAIN_PROFILE` und `NEGAFLOW_RELEASE_MODE=distribution` benötigt.

Das eigenständige PKG und DMG erstellen Sie mit:

```bash
NEGAFLOW_OVERWRITE_INSTALLER=1 ./scripts/build-installer.sh
```

Dieser Build prüft das festgelegte offizielle Homebrew-Paket vor der Übernahme seiner
Installer-Komponente, erstellt anschließend die Apple-Silicon- und die Universal-Variante und
kontrolliert jedes PKG und DMG ohne Installation. Mit `NEGAFLOW_INSTALLER_ARCHITECTURE` auf `arm64`
oder `universal` wird nur eine Variante gebaut; der Standardwert `all` baut beide. Mit
`NEGAFLOW_INSTALLER_VARIANT=all` werden Standard- und Coolscan-Familie gebaut; standardmäßig wird nur
die Standardfamilie gebaut. Für den Distributionsmodus werden zusätzlich
`NEGAFLOW_INSTALLER_MODE=distribution`, eine `NEGAFLOW_INSTALLER_IDENTITY` für das PKG sowie die
bereits verwendete App-Signaturidentität und das Notarisierungsprofil benötigt.
