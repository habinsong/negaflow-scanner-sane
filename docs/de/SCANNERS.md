# Unterstützte Scanner

[Dokumentationsstart](README.md)

Die folgende Tabelle beschreibt bekannte SANE-Ziele und die zugehörigen Pfade dieses Plug-ins.
Sie garantiert nicht, dass jedes Gerät mit demselben Produktnamen funktioniert. Prüfen Sie die
[aktuelle SANE-Geräteliste](https://www.sane-project.org/sane-supported-devices.html) und danach das
angeschlossene Gerät mit `scanimage -L` und `scanimage -A`.

„Gepatchtes SANE“ meint das SANE, das der `mac26`-Installer baut, und die SANE-Laufzeit im
Windows-Installer: SANE 1.4.0 mit den Patches aus
[`sane-runtime/SOURCES.md`](../../negaflow-mac/sane-runtime/SOURCES.md). Der `mac14`-Installer
verwendet das reguläre SANE 1.4.0 von Homebrew ohne diese Patches.

| Scannerfamilie | SANE-Backend | Status | Plug-in-Pfad |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i v2 | `genesys` | Complete in SANE 1.4 | Dedizierter Filmscanner |
| Plustek OpticFilm 7400 v1, 7600i v1 | `genesys` | Upstream nach 1.4.0 korrigiert; die Korrekturen sind im gepatchten SANE | Dedizierter Filmscanner; nicht an Hardware geprüft |
| Plustek OpticFilm 8100, USB `07b3:130c` (GL845) | `genesys` | Complete in SANE 1.4 | Dedizierter Filmscanner, an Hardware geprüft |
| Plustek OpticFilm 8200i, USB `07b3:130d` (GL845) | `genesys` | Complete in SANE 1.4 | Dedizierter Filmscanner |
| Plustek OpticFilm 8200i, neuere Geräte, USB `07b3:1825` (GL128; SANE zeigt „8200i SE“) | `genesys`, nur im gepatchten SANE | Upstream Basic: 16 Bit, 150–7200 dpi, kein Infrarot | Dedizierter Filmscanner; nicht an Hardware geprüft |
| Plustek OpticFilm 8100 V2, USB `07b3:1824` (GL128) | Keines | Unsupported | Nicht als nutzbar behandelt |
| Plustek OpticFilm 8300i, USB `07b3:181f` (GL128, am SE gemessen) | Keines | Unsupported | Nicht als nutzbar behandelt |
| Plustek OpticFilm 9000i Ai, USB `07b3:182f` | Keines | Unsupported | Nicht als nutzbar behandelt |
| Plustek OpticFilm 120, 120 Pro, 135, 135i | Keines | Unsupported | Nicht als nutzbar behandelt |
| Epson Perfection V700/V750 (GT-X900), V800/V850 (GT-X980) | `epson2` | Good | Durchlichtquelle und positionierter Flachbettbereich, wenn gemeldet |
| Nikon Coolscan LS-40 ED, LS-50 ED, LS-5000 ED (USB) | `coolscan3`, `coolscan2` | Complete (LS-40), Minimal (LS-50), Untested (LS-5000) | Dedizierter Filmscanner mit den Einschränkungen unten; nicht an Hardware geprüft |
| Nikon Coolscan LS-4000 ED, LS-8000 ED (IEEE 1394 / FireWire) | `coolscan3`, `coolscan2` über SBP-2 | Good unter Linux | Unter macOS 26 nicht nutzbar; Windows und macOS 14/15 ungeprüft, siehe unten |
| Nikon Coolscan LS-30, LS-2000 (SCSI) | `coolscan3` | Complete (LS-30), Good (LS-2000) | Benötigt einen SCSI-Hostadapter |
| Nikon Coolscan LS-20, LS-1000 | `coolscan` | Je nach Modell | Nur SCSI |
| Nikon Coolscan LS-9000 ED | Keines | Unsupported | Nicht als nutzbar behandelt |
| Reflecta ProScan/CrystalScan/DigitDia und PIE PowerSlide | `pieusb`; alte SCSI-Modelle nutzen `pie` | Je nach Modell und Modellnummer | Nur vom Gerät gemeldete Optionen |
| Pacific Image PrimeFilm XA, XAs, XA Plus | Keines | Unsupported | Nicht als nutzbar behandelt |
| Weitere Flachbett- und Filmscanner mit Durchlicht | Unterschiedlich | Je nach Modell | Nach gemeldeten Fähigkeiten, ohne Rückfall auf den Modellnamen |

## Der Produktname sagt nichts über die Hardware

Plustek verkauft neuere Hardware unter älteren Produktnamen. Unterscheiden lassen sie sich über die
USB product ID, nicht über den Namen auf dem Gehäuse.

| Name auf dem Gehäuse | USB-ID | Controller | SANE |
|---|---|---|---|
| OpticFilm 8100, ältere Geräte | `07b3:130c` | GL845 | `genesys` in SANE 1.4.0 |
| OpticFilm 8100, neuere Geräte (V2) | `07b3:1824` | GL128 | Keines |
| OpticFilm 8200i, ältere Geräte | `07b3:130d` | GL845 | `genesys` in SANE 1.4.0 |
| OpticFilm 8200i, neuere Geräte | `07b3:1825` | GL128 | `genesys` im Upstream-Master seit 2026-09; nur im gepatchten SANE |
| OpticFilm 8300i SE (Ai nicht bestätigt) | `07b3:181f` | GL128 | Keines |
| OpticFilm 9000i Ai | `07b3:182f` | Nicht veröffentlicht | Keines |

SE und Ai bezeichnen die mitgelieferte SilverFast-Ausgabe, nicht die Hardware: Ein älterer
8200i SE oder Ai ist ein `130d`, ein neuerer ein `1825`.

Die drei GL128-Scanner haben dieselbe Registeranordnung, aber nicht dieselben Werte. Der GL128-Code
von SANE beruht großteils auf den USB-Mitschnitten, die der freie Treiber
[pyopticfilm](https://github.com/jboneng/pyopticfilm) dekodiert hat, und dieses Projekt hält die
Unterschiede fest: Der 8100 V2 startet mit einem anderen ASIC-Takt und einem anderen Register
`0x0B`, der 8300i SE hat eigene Belichtungs-, Sensortiming- und Motortabellen. Die Tabelle des
8200i SE auf einen der beiden anzuwenden, hieße Motor und Lampe nach Vermutung zu steuern.
pyopticfilm dokumentiert einen blockierten Motor an einem 8100 V2 direkt nach dem Setzen eines
einzigen Registerbits. Dieses Plug-in schaltet ein GL128-Modell deshalb erst frei, wenn ein
SANE-Build es ansteuert und jemand damit tatsächlich gescannt hat.

Die ID zeigt `system_profiler SPUSBDataType` auf dem Mac oder der Geräte-Manager unter Windows.

Zwei weitere Stolperfallen bei der Identifikation sind wichtig.

- `pieusb` vergleicht die USB-ID **und** eine Modellnummer. Reflecta- und PIE-Geräte teilen sich
  IDs wie `05e3:0145`, daher ist ein Gerät nur verwendbar, wenn seine Modellnummer in
  `pieusb.conf` steht.
- `epson2` kennt Epson-Scanner unter ihren japanischen Modellnamen. `scanimage -L` meldet einen
  Perfection V800/V850 als `GT-X980` und einen V700/V750 als `GT-X900`. Das ist derselbe Scanner.

## Nikon Coolscan

Mit diesem Plug-in wurde noch kein Coolscan an Hardware geprüft. Das Folgende stammt aus dem
Quellcode von `coolscan3` und dem Code des Plug-ins.

### Anschluss

LS-4000 ED und LS-8000 ED haben nur einen IEEE-1394-Anschluss (FireWire). SANE erreicht sie über
SBP-2 als SCSI-Geräte; sie erscheinen daher als `coolscan3:scsi:...`, nie als USB.

- **macOS 26 unterstützt FireWire überhaupt nicht mehr**, und Adapter ändern daran nichts. Der
  `mac26`-Installer, der einzige mit gepatchtem SANE, erreicht diese beiden Modelle daher nicht.
- macOS 14 und 15 unterstützen FireWire noch, und SANE hat eine SCSI-Schnittstelle für macOS, aber
  dieser Weg wurde mit dem `mac14`-Installer nie ausprobiert.
- Unter Windows müsste SANE einen SBP-2-Scanner über seinen SCSI-Pass-through-Pfad erreichen. Auch
  das wurde nicht ausprobiert.

Realistische Coolscan-Ziele sind die USB-Modelle LS-40 ED, LS-50 ED und LS-5000 ED.

### Was der Plug-in-Pfad tut

| Thema | Verhalten | Folge |
|---|---|---|
| Farbmodus | `coolscan2`/`coolscan3` haben kein `--mode` und liefern immer RGB | Nur `color` wird gemeldet. Schwarzweißfilm wird in Farbe gescannt und von negaflow entwickelt; die Anfrage gleicht bis auf den Filmtyp der eines Farbnegativs |
| Scanbereich | Die Geometrieoptionen sind Pixel in der Höchstauflösung des Scanners, keine Millimeter | negaflow kann keinen Bereich wählen; das Plug-in rechnet die vorgegebenen 36 x 24 mm in Pixel um. Ein Mittelformatbild auf einem LS-8000 wird auf seine oberen linken 36 x 24 mm beschnitten |
| Bild | `--frame` wird nie gesendet | Mit einem Filmstreifenhalter wird nur das erste Bild gescannt |
| Fokus | `coolscan3` fokussiert nur auf Anforderung automatisch, und negaflow fordert es nicht an | Gescannt wird mit der aktuellen Fokusposition des Scanners |
| Infrarot | `--infrared` liefert einen einzigen RGBI-Frame | Wird nicht als IR-Kanal angeboten |
| Filmtyp | `--negative` lässt den Scanner die Farben invertieren | Wird immer als `--negative=no` gesendet, damit negaflow das rohe Negativ erhält |

Die letzten beiden Zeilen sind beabsichtigt. Die ersten vier sind offene Arbeit, und jede muss an
einem echten Scanner geprüft werden.

## Infrarotkanal

„IR verfügbar“ bedeutet hier, dass ein separates Infrarotbild als `irPath` an negaflow zurückgegeben
werden kann. Eine interne Staubkorrektur des Backends wird nicht als IR-Kanal gemeldet.

| Scanner- oder Backend-Pfad | IR-Status | Erfassung | Separate IR-TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Nicht verfügbar | Diese Modelle melden keine IR-Quelle | Nein |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Verfügbar, wenn `scanimage -A` die IR-Quelle meldet | Separater Durchlauf mit `Transparency Adapter Infrared` | Ja |
| OpticFilm 8200i, neuere Geräte `07b3:1825` | Nicht verfügbar | Der GL128-Code von SANE hat noch keinen Infrarotdurchlauf | Nein |
| OpticFilm 8100 V2, 8300i, 9000i | Nicht verfügbar | Kein SANE-Backend | Nein |
| Epson V700/V750/V800/V850 mit dem `mac26`-Installer | Verfügbar, wenn `scanimage -A` den Infrarotmodus meldet | Separater `Infrared`-Durchlauf des gepatchten `epson2` | Ja |
| Epson V700/V750/V800/V850 mit regulärem `epson2` | Nicht verfügbar | Reguläre Builds lassen `SANE_FRAME_IR` auskompiliert | Nein |
| Nikon `coolscan3` mit `--infrared` | Über `scanimage` nicht verfügbar | `coolscan3` liefert einen `SANE_FRAME_RGBI`-Frame; `scanimage` 1.4 trennt ihn nicht in RGB- und IR-TIFF | Nein |
| Reflecta/PIE nur mit `--clean-image` | Nicht als IR-Kanal verfügbar | Staubkorrektur erfolgt im Backend | Nein |
| Sonstige Scanner | Bedingt | Nur wenn `scanimage -A` eine aktive, separate IR-Quelle oder einen IR-Modus meldet | Ja, nach Format- und Größenprüfung |

Der IR-Durchlauf verwendet dieselbe angeforderte Auflösung und denselben Scanbereich wie RGB, und vor
der Rückgabe werden beide Bilder auf dieselben Pixelabmessungen geprüft. negaflow kann das IR-Bild
anschließend für GrainMend IR verwenden.
