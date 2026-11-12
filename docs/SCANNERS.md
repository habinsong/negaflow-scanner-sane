# Supported scanners

[Docs home](README.md)

The table below lists the known SANE targets and the path this plugin takes for each one. It is not
a promise that every unit with the same product name works. Check the
[SANE device list](https://www.sane-project.org/sane-supported-devices.html), then confirm the
connected unit with `scanimage -L` and `scanimage -A`.

"Patched SANE" means the SANE the `mac26` installer builds and the SANE runtime inside the Windows
installer: SANE 1.4.0 plus the patches listed in
[`sane-runtime/SOURCES.md`](../negaflow-mac/sane-runtime/SOURCES.md). The `mac14` installer uses
Homebrew's stock SANE 1.4.0 without them.

| Scanner family | SANE backend | Status | Plugin path |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i v2 | `genesys` | Complete in SANE 1.4 | Dedicated film-scanner path |
| Plustek OpticFilm 7400 v1, 7600i v1 | `genesys` | Corrected upstream after 1.4.0; the corrections are in patched SANE | Dedicated film-scanner path; not checked on hardware |
| Plustek OpticFilm 8100, USB `07b3:130c` (GL845) | `genesys` | Complete in SANE 1.4 | Dedicated film-scanner path, checked on hardware |
| Plustek OpticFilm 8200i, USB `07b3:130d` (GL845) | `genesys` | Complete in SANE 1.4 | Dedicated film-scanner path |
| Plustek OpticFilm 8200i, newer units, USB `07b3:1825` (GL128; SANE names it "8200i SE") | `genesys`, patched SANE only | Basic upstream: 16-bit, 150-7200 dpi, no infrared | Dedicated film-scanner path; not checked on hardware |
| Plustek OpticFilm 8100 V2, USB `07b3:1824` (GL128) | None | Unsupported | Not treated as usable |
| Plustek OpticFilm 8300i, USB `07b3:181f` (GL128, measured on the SE) | None | Unsupported | Not treated as usable |
| Plustek OpticFilm 9000i Ai, USB `07b3:182f` | None | Unsupported | Not treated as usable |
| Plustek OpticFilm 120, 120 Pro, 135, 135i | None | Unsupported | Not treated as usable |
| Epson Perfection V700/V750 (GT-X900), V800/V850 (GT-X980) | `epson2` | Good | Transparency source and positioned flatbed area when reported |
| Epson Perfection V500 Photo (GT-X770, USB `04b8:0130`) | `epson2`, patched SANE only | Checked on hardware: flatbed, transparency, 16-bit, infrared | Needs Epson's ICA driver on the Mac, see below |
| Nikon Coolscan LS-40 ED, LS-50 ED, LS-5000 ED (USB) | `coolscan3`, `coolscan2` | Complete (LS-40), Minimal (LS-50), Untested (LS-5000) | Dedicated film-scanner path with the limits below; not checked on hardware |
| Nikon Coolscan LS-4000 ED, LS-8000 ED (IEEE 1394 / FireWire) | `coolscan3`, `coolscan2` through SBP-2 | Good on Linux | Not usable on macOS 26; Windows and macOS 14/15 unverified, see below |
| Nikon Coolscan LS-30, LS-2000 (SCSI) | `coolscan3` | Complete (LS-30), Good (LS-2000) | Needs a SCSI host adapter |
| Nikon Coolscan LS-20, LS-1000 | `coolscan` | Varies by model | SCSI only |
| Nikon Coolscan LS-9000 ED | None | Unsupported | Not treated as usable |
| Reflecta ProScan/CrystalScan/DigitDia and PIE PowerSlide | `pieusb`; old SCSI models use `pie` | Varies by model and model number | Only the options the device reports |
| Pacific Image PrimeFilm XA, XAs, XA Plus | None | Unsupported | Not treated as usable |
| Other transparency-capable flatbeds and film scanners | Varies | Varies by model | Capability-driven, with no model-name fallback |

## A product name does not identify the hardware

Plustek sells newer hardware under older product names. The USB product ID tells them apart, the
name on the case does not.

| Name on the case | USB ID | Controller | SANE |
|---|---|---|---|
| OpticFilm 8100, older units | `07b3:130c` | GL845 | `genesys` in SANE 1.4.0 |
| OpticFilm 8100, newer units (V2) | `07b3:1824` | GL128 | None |
| OpticFilm 8200i, older units | `07b3:130d` | GL845 | `genesys` in SANE 1.4.0 |
| OpticFilm 8200i, newer units | `07b3:1825` | GL128 | `genesys` in upstream master since 2026-09; patched SANE only |
| OpticFilm 8300i SE (Ai not confirmed) | `07b3:181f` | GL128 | None |
| OpticFilm 9000i Ai | `07b3:182f` | Not published | None |

SE and Ai name the bundled SilverFast edition, not the hardware: an older 8200i SE or Ai is a
`130d`, a newer one a `1825`.

The three GL128 scanners share one register map, but they do not share every value. The open
[pyopticfilm](https://github.com/jboneng/pyopticfilm) driver, whose decoded USB captures SANE's
GL128 code is largely based on, records the differences: the 8100 V2 boots with a different ASIC
clock and register `0x0B`, and the 8300i SE uses its own exposure, sensor timing and motor tables.
Running the 8200i SE table on either of them would be a guess about motor and lamp control.
pyopticfilm records a motor jam on an 8100 V2 right after one register bit was set, so this plugin
does not enable a GL128 model until a SANE build drives it and someone has scanned with it.

Check the ID with `system_profiler SPUSBDataType` on a Mac or in Device Manager on Windows.

Two more identification traps are worth knowing.

- `pieusb` matches a USB ID **and** a model number. Reflecta and PIE units share IDs such as
  `05e3:0145`, so a unit is usable only when its model number is listed in `pieusb.conf`.
- `epson2` knows Epson scanners by their Japanese model names. `scanimage -L` reports a Perfection
  V800/V850 as `GT-X980` and a V700/V750 as `GT-X900`. That is the same scanner.

## Epson Perfection V500 Photo

The V500 Photo does not speak plain ESC/I on the USB bus, so stock `epson2` cannot open it. SANE's
documented route is the `epkowa` backend with Epson's `iscan-plugin-gt-x770`, which exists only for
Linux on i386 and amd64. Patched SANE instead loads the interpreter that Epson's macOS ICA driver
already contains.

- Install Epson's scanner driver (the ICA driver for the V500 from Epson's website, which VueScan
  also asks for). The patched `epson2` loads `Interpreter 7C` from
  `/Library/Image Capture/Devices/EPSON Scanner.app`. The file belongs to Epson and is not part of
  this repository or the installers. `EPSON2_INTERPRETER` overrides the path.
- `scanimage -L` lists the scanner as `GT-X770`. Plain `epson2.conf` is enough, because the patch adds
  the USB ID to the backend's list.
- The transparency area is 68.58 x 236.98 mm. A position and size that leave it are rejected with
  `Invalid argument`.
- The scanner reports 200, 400, 800, 1600 and 6400 dpi, at 8 or 16 bit. In `Negative Film` the scanner compensates the
  orange mask and does not invert the image.
- The infrared pass runs at 800, 1600 or 3200 dpi, as an 8 or 16-bit gray image. At 3200 dpi the
  scanner reads 2400 lines per inch, so the pixels are not square. While the mode is `Infrared`,
  `scanimage -A` lists just those three resolutions. For a color scan at another resolution (for
  example 6400 dpi) the plugin reads infrared at the closest lower resolution and resamples it to the
  pixel size of the color scan, and reports that in the scan warnings.
- The infrared pass is offset from the color pass by a few pixels, and the offset changes between
  scans. After each infrared pass the plugin measures it from the dust (infrared dust map against dark
  specks in the color image, in eight bands along the frame, fitted with a line), shifts the infrared,
  and reports the shift in the scan warnings. With too little dust to measure, it leaves the infrared
  unshifted and says so.
- Close VueScan and Image Capture before scanning, because either holds the scanner exclusively. An
  aborted scan can leave the scanner unresponsive until its power is cycled.

## Nikon Coolscan

No Coolscan has been checked on hardware with this plugin. What follows is read from the
`coolscan3` source and the plugin code.

### Connection

The LS-4000 ED and LS-8000 ED have only an IEEE 1394 (FireWire) port. SANE reaches them as SCSI
devices over SBP-2, so they appear as `coolscan3:scsi:...`, never as USB.

- **macOS 26 has no FireWire at all**, and adapters do not bring it back. The `mac26` installer, the
  only one with the patched SANE, therefore cannot reach these two models.
- macOS 14 and 15 still have FireWire, and SANE has a macOS SCSI interface, but this path has not
  been tried with the `mac14` installer.
- On Windows, SANE would need its SCSI pass-through path to reach an SBP-2 scanner. That has not
  been tried either.

The LS-40 ED, LS-50 ED and LS-5000 ED use USB and are the realistic Coolscan targets.

### What the plugin path does

| Topic | Behaviour | Effect |
|---|---|---|
| Colour mode | `coolscan2`/`coolscan3` have no `--mode` and always return RGB | Only `color` is reported. Black-and-white film is scanned in colour and developed by negaflow, the same request as colour negative apart from the film type |
| Scan area | The geometry options are pixels at the scanner's maximum resolution, not millimetres | negaflow cannot pick an area, so the plugin converts its default 36 x 24 mm into pixels. A medium-format frame on an LS-8000 is cropped to its top-left 36 x 24 mm |
| Frame | `--frame` is never sent | With a strip holder only the first frame is scanned |
| Focus | `coolscan3` autofocuses only when asked, and negaflow does not ask | Scans use the scanner's current focus position |
| Infrared | `--infrared` returns one RGBI frame | Not offered as an IR channel |
| Film type | `--negative` makes the scanner invert colours | Always sent as `--negative=no`, so negaflow gets the raw negative |

The last two rows are deliberate. The first four are open work and each needs a scanner to verify.

## Infrared channel

Here, "IR available" means a separate infrared image can be handed to negaflow as `irPath`. A dust
removal switch that runs inside the backend is not reported as an IR channel.

| Scanner or backend path | IR status | How it is acquired | Separate IR TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Not available | These models do not expose an IR source | No |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Available when `scanimage -A` reports the infrared source | Separate `Transparency Adapter Infrared` pass | Yes |
| OpticFilm 8200i, newer units `07b3:1825` | Not available | SANE's GL128 code has no infrared pass yet | No |
| OpticFilm 8100 V2, 8300i, 9000i | Not available | No SANE backend | No |
| Epson V700/V750/V800/V850 with the `mac26` installer | Available when `scanimage -A` reports the infrared mode | Separate `Infrared` mode pass from the patched `epson2` | Yes |
| Epson V500 Photo with the `mac26` installer and Epson's ICA driver | Available | Separate `Infrared` mode pass through Epson's interpreter at 800, 1600 or 3200 x 2400 dpi, resampled to the size of the color scan | Yes |
| Epson V700/V750/V800/V850 with stock `epson2` | Not available | Stock builds keep `SANE_FRAME_IR` compiled out | No |
| Nikon `coolscan3` with `--infrared` | Not available through `scanimage` | `coolscan3` returns one `SANE_FRAME_RGBI` frame, which `scanimage` 1.4 does not split into RGB and IR TIFF files | No |
| Reflecta/PIE with `--clean-image` only | Not available as an IR channel | Dust removal happens inside the backend | No |
| Any other scanner | Conditional | Only when `scanimage -A` reports an active, separate IR source or mode | Yes, after size and format checks |

The IR pass uses the same requested resolution and scan area as the RGB pass, and both images are
checked for the same pixel dimensions before they are returned. negaflow can then use the IR image
for GrainMend IR.
