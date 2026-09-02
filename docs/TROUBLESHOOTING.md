# Troubleshooting

[Docs home](README.md)

## The installer fails

The failure screen only says the installation failed. macOS Installer judges a package script by its
exit code, so whatever the script printed is in the log instead. Press ⌘L while the installer is
open, or read it afterwards:

```bash
sudo grep -iE "negaflow|Error:" /var/log/install.log | tail -60
```

| Log line | Cause |
|---|---|
| `Your Command Line Tools are too outdated` | The `mac26` package compiles SANE, and Homebrew rejects Command Line Tools older than the running macOS |
| `Homebrew was not installed at the supported prefix` | No `brew` at `/opt/homebrew` or `/usr/local` |
| `no supported logged-in user was found` | No console user, for example over SSH or at the login window |
| `patched scanimage was not installed` | The SANE build failed; the Homebrew error is above this line |

For outdated Command Line Tools:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
```

```bash
xcode-select --install
```

An outdated installation keeps `git`, so a file check treats it as present. The installer looks for
the SDK of the running macOS instead and stops before installing anything.

Homebrew is not a prerequisite. The package carries the official signed Homebrew installer and runs
it only when `brew` is missing. An existing installation is used as it is.

The `mac26` package builds SANE 1.4.0 from source, so it takes a few minutes and the progress bar
cannot follow the build. The `mac14` package installs a prebuilt bottle and finishes quickly.

## No scanner found

**Approved** in negaflow means the plugin is allowed to run. It does not mean a scanner was found.
Detection is whatever `scanimage -L` returns, so a scanner missing there is missing in negaflow too,
and reinstalling the app or the plugin changes nothing.

macOS has no per-app USB permission to switch on. Neither negaflow nor this plugin uses the App
Sandbox, so no **Privacy & Security** setting gates scanner access.

### 1. Find the layer that fails

With the scanner powered on and connected, run these in order.

```bash
system_profiler SPUSBDataType
```

```bash
scanimage -L
```

```bash
"$HOME/Library/Application Support/negaflow/Plugins/sane/negaflow-scanner-sane" detect
```

| USB list | `scanimage -L` | `detect` | Where the problem is |
|---|---|---|---|
| No scanner | Nothing | `{"devices":[]}` | Cable, port, or power, before SANE is involved |
| Scanner listed | Nothing | `{"devices":[]}` | SANE backend, or another process holding the device |
| Scanner listed | Device listed | `{"devices":[]}` | SANE installed where the plugin does not look |
| Scanner listed | Device listed | Device listed | negaflow side: reopen **Load scanner** and approve again |

### 2. Common causes

| Symptom | Cause | What to do |
|---|---|---|
| `scanimage: command not found` | SANE is not installed or its `bin` is outside the current `PATH` | Install stock `sane-backends`; for the patched path use the helper and export shown above |
| The scanner is not in the USB list | Hub, dock, adapter, cable, or power | Connect it directly, try another port, and avoid hubs. USB 2.0 film scanners often fail through USB-C adapters |
| `no SANE devices found` while `sane-find-scanner` sees the device | No enabled backend claims this model | Check the [SANE device list](https://www.sane-project.org/sane-supported-devices.html), then read the log in step 3 |
| The scanner is in the USB list, `scanimage -L` is empty, and `repair-sane-config` reports `notNeeded` | The unit is a hardware revision SANE does not know | Compare the USB product ID against [supported scanners](SCANNERS.md). A newer revision sold under an older product name cannot be fixed from this side |
| A Coolscan LS-50 or LS-5000 vanishes from the USB list | A documented USB port failure on these units | Confirm with another cable and port. If the Mac never enumerates it, this is a hardware fault |
| `another process has device opened for exclusive access`, `device busy`, `is not configured` | Another program already claimed the USB interface | Quit VueScan, SilverFast, Image Capture, and vendor utilities, reconnect the scanner, then retry |
| Only `sudo scanimage -L` finds it | The interface is claimed or was never released | Solve the claim above. negaflow never runs the plugin as root, so `sudo` is not a workaround |
| Terminal finds it, negaflow does not | SANE lives outside the supported Homebrew keg paths | Re-run the included installer; MacPorts (`/opt/local`) and hand-built prefixes are not used |
| `open of device ... failed: Invalid argument` | The USB address changed after the first open, or the SANE config directory is missing | Run `detect` again, and confirm `/opt/homebrew/etc/sane.d` or `/usr/local/etc/sane.d` exists |
| It worked before an update | The selected SANE keg was removed or replaced | Re-run the matching installer and check `brew list --versions sane-backends sane-backends-negaflow` |
| Empty list after an older negaflow plugin was installed | A legacy build disabled backends in `dll.conf` | Run `repair-sane-config`, described in [SANE configuration](#sane-configuration) |

### 3. Read the backend log

```bash
SANE_DEBUG_DLL=3 scanimage -L 2>&1 | tail -40
```

This shows which backends load and which fail. To narrow it to one backend, use that backend's own
variable, such as `SANE_DEBUG_GENESYS=128` or `SANE_DEBUG_EPSON2=128`.

A report is only useful with the macOS version, the Mac model, `scanimage --version`,
`brew list --versions sane-backends sane-backends-negaflow`, the scanner model, and the output of
the three steps above.

## SANE configuration

The patched keg uses its own `etc/sane.d` and does not modify a stock Homebrew `dll.conf`. `detect`
repairs backend lines disabled by an older negaflow plugin on its own, while preserving distribution
and user comments. You can run the same repair manually:

```bash
.build/release/negaflow-scanner-sane repair-sane-config
```

If a legacy `dll.conf.negaflow-backup` exists, the following command replaces the whole current file
with that backup. Changes made after the backup are reverted too, so use it only when the repair
above is not enough:

```bash
.build/release/negaflow-scanner-sane restore-sane
```
