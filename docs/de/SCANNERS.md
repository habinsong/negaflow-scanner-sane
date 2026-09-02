# Unterstützte Scanner

[Dokumentationsstart](README.md)

Die folgende Tabelle beschreibt bekannte SANE-1.4-Ziele und die zugehörigen Pfade dieses Plug-ins.
Sie garantiert nicht, dass jedes Gerät mit demselben Produktnamen funktioniert. Prüfen Sie die
[aktuelle SANE-Geräteliste](https://www.sane-project.org/sane-supported-devices.html) und danach das
angeschlossene Gerät mit `scanimage -L` und `scanimage -A`.

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

## Der Produktname sagt nichts über die Hardware

Den OpticFilm 8100 und den 8200i gibt es jeweils unter derselben Produktbezeichnung in mindestens
zwei USB-Varianten. `07b3:130c` und `07b3:130d` werden von `genesys` angesteuert, `07b3:1824` und
`07b3:1825` dagegen nicht, weil sie einen anderen Genesys-Chip verwenden, den kein Backend bedient.
Eine neuere Revision unter altem Namen lässt sich auf SANE-Seite nicht beheben. Maßgeblich ist daher
die tatsächliche USB product ID, nicht der Name auf dem Gehäuse.

Zwei weitere Stolperfallen bei der Identifikation sind wichtig.

- `pieusb` vergleicht die USB-ID **und** eine Modellnummer. Reflecta- und PIE-Geräte teilen sich
  IDs wie `05e3:0145`, daher ist ein Gerät nur verwendbar, wenn seine Modellnummer in
  `pieusb.conf` steht.
- `epson2` kennt Epson-Scanner unter ihren japanischen Modellnamen. `scanimage -L` meldet einen
  Perfection V800/V850 als `GT-X980` und einen V700/V750 als `GT-X900`. Das ist derselbe Scanner.

## Infrarotkanal

„IR verfügbar“ bedeutet hier, dass ein separates Infrarotbild als `irPath` an negaflow zurückgegeben
werden kann. Eine interne Staubkorrektur des Backends wird nicht als IR-Kanal gemeldet.

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

Der IR-Durchlauf verwendet dieselbe angeforderte Auflösung und denselben Scanbereich wie RGB, und vor
der Rückgabe werden beide Bilder auf dieselben Pixelabmessungen geprüft. negaflow kann das IR-Bild
anschließend für GrainMend IR verwenden.
