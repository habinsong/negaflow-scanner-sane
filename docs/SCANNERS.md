# Supported scanners

[Docs home](README.md)

The table below lists the known SANE 1.4 targets and the path this plugin takes for each one. It is
not a promise that every unit with the same product name works. Check the
[SANE device list](https://www.sane-project.org/sane-supported-devices.html), then confirm the
connected unit with `scanimage -L` and `scanimage -A`.

| Scanner family | SANE backend | SANE 1.4 status | Plugin path |
|---|---|---|---|
| Plustek OpticFilm 7200, 7200 v2, 7200i, 7300, 7400 v2, 7500i, 7600i | `genesys` | Complete | Dedicated film-scanner path |
| Plustek OpticFilm 7400 v1 | `genesys` | Listed as Complete, but its model-specific corrections landed after SANE 1.4.0 | Capability-driven path; stock 1.4.0 hardware result is unverified |
| Plustek OpticFilm 8100, USB `07b3:130c` | `genesys` | Complete | Dedicated film-scanner path |
| Plustek OpticFilm 8100, USB `07b3:1824` | None | Unsupported | Not treated as usable |
| Plustek OpticFilm 8200i, USB `07b3:130d` | `genesys` | Complete | Dedicated film-scanner path |
| Plustek OpticFilm 8200i, USB `07b3:1825` (GL128) | None | Unsupported | Not treated as usable |
| Plustek OpticFilm 120, 120 Pro, 135, 135i, 9000i Ai | None | Unsupported | Not treated as usable |
| Epson Perfection V700/V750 (GT-X900), V800/V850 (GT-X980) | `epson2` | Good | Transparency source and positioned flatbed area when reported |
| Nikon Coolscan LS-2000, LS-40 ED, LS-50 ED, LS-4000 ED, LS-8000 ED | `coolscan3` | Complete to Minimal, depending on the model | Dedicated film-scanner path |
| Nikon Coolscan LS-5000 ED | `coolscan3` | Untested; may work like the LS-50 according to SANE 1.4 | Dedicated film-scanner path |
| Nikon Coolscan LS-20, LS-30, LS-1000 | `coolscan` | Varies by model | SCSI only |
| Nikon Coolscan LS-9000 ED | None | Unsupported | Not treated as usable |
| Reflecta ProScan/CrystalScan/DigitDia and PIE PowerSlide | `pieusb`; old SCSI models use `pie` | Varies by model and model number | Only the options the device reports |
| Pacific Image PrimeFilm XA, XAs, XA Plus | None | Unsupported | Not treated as usable |
| Other transparency-capable flatbeds and film scanners | Varies | Varies by model | Capability-driven, with no model-name fallback |

## A product name does not identify the hardware

OpticFilm 8100 and 8200i each ship in at least two USB variants under one product name. `07b3:130c`
and `07b3:130d` are driven by `genesys`, while `07b3:1824` and `07b3:1825` use a different Genesys
chip that no backend drives. A newer revision sold under an older name cannot be fixed from the SANE
side, so check the USB product ID rather than the name on the case.

Two more identification traps are worth knowing.

- `pieusb` matches a USB ID **and** a model number. Reflecta and PIE units share IDs such as
  `05e3:0145`, so a unit is usable only when its model number is listed in `pieusb.conf`.
- `epson2` knows Epson scanners by their Japanese model names. `scanimage -L` reports a Perfection
  V800/V850 as `GT-X980` and a V700/V750 as `GT-X900`. That is the same scanner.

## Infrared channel

Here, "IR available" means a separate infrared image can be handed to negaflow as `irPath`. A dust
removal switch that runs inside the backend is not reported as an IR channel.

| Scanner or backend path | IR status | How it is acquired | Separate IR TIFF |
|---|---|---|---|
| OpticFilm 7200, 7200 v2, 7300, 7400, 8100 | Not available | These models do not expose an IR source | No |
| OpticFilm 7200i, 7500i, 7600i, 8200i `07b3:130d` | Available when `scanimage -A` reports the infrared source | Separate `Transparency Adapter Infrared` pass | Yes |
| OpticFilm 8200i `07b3:1825` | Not available | The device variant is unsupported by SANE 1.4 | No |
| Epson V700/V750/V800/V850 with the `mac26` installer | Available when `scanimage -A` reports the infrared mode | Separate `Infrared` mode pass from the patched `epson2` | Yes |
| Epson V700/V750/V800/V850 with stock `epson2` | Not available | Stock builds keep `SANE_FRAME_IR` compiled out | No |
| Nikon `coolscan3` with `--infrared` | Not available through stock `scanimage` | `coolscan3` returns one `SANE_FRAME_RGBI` frame, which `scanimage` 1.4 does not split into RGB and IR TIFF files | No |
| Reflecta/PIE with `--clean-image` only | Not available as an IR channel | Dust removal happens inside the backend | No |
| Any other scanner | Conditional | Only when `scanimage -A` reports an active, separate IR source or mode | Yes, after size and format checks |

The IR pass uses the same requested resolution and scan area as the RGB pass, and both images are
checked for the same pixel dimensions before they are returned. negaflow can then use the IR image
for GrainMend IR.
