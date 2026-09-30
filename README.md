# AIO Antenna Control

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar
plugin for the ClockworkPi uConsole running with a
[Hackergadgets AIO v2](https://hackergadgets.com/products/uconsole-aio-v2)
expansion board. Adds a DankBar pill with a popout to enable/disable the
board's GPS, LoRa, SDR, and internal-USB power rails, plus the wifi and
Bluetooth radios on a [Hackergadgets AC1200 USB-C module](https://hackergadgets.com/)
plugged into that internal USB header.

## How it works

The AIO v2 gates GPS/LoRa/SDR/internal-USB power behind GPIO lines that are
off by default. They're driven directly with `pinctrl` (BCM numbering,
active-high — pull the pin high to enable):

| Feature      | GPIO |
|--------------|------|
| GPS          | 27   |
| LoRa         | 16   |
| SDR          | 7    |
| Internal USB | 23   |

```sh
pinctrl 27 op   # set as output
pinctrl 27 dh   # drive high -> on
pinctrl 27 dl   # drive low  -> off
pinctrl 27 get  # read current level
```

These pins/commands come from the
[Hackergadgets uConsole AIO V1/V2 setup guide](https://hackergadgets.com/pages/hackergadgets-uconsole-rtl-sdr-lora-gps-rtc-usb-hub-all-in-one-extension-board-setup-guide)
and the [ClockworkPi forum thread](https://forum.clockworkpi.com/t/uconsole-aio-v2-rtl-sdr-lora-gps-rtc-usb-hub-usb-3-0-rj45-ethernet/20800) —
**verify them against your own board revision before relying on this**, since
they weren't confirmed against the physical hardware.

Hackergadgets also publish an official control tool,
[`aiov2_ctl`](https://github.com/hackergadgets/aiov2_ctl), which wraps the
same `pinctrl` calls plus persistent boot-rail state and power monitoring.
This widget talks to `pinctrl` directly to keep the dependency surface small
and the status parsing predictable; swapping the backend to shell out to
`aiov2_ctl` instead (for its boot-persistence and power-draw readouts) would
be a reasonable follow-up.

### Permissions

`pinctrl` needs access to `/dev/gpiomem`. On Raspberry Pi OS the default user
is already in the `gpio` group, which is normally enough — no `sudo`
required. If toggles silently fail, check `groups $USER` and that
`pinctrl <pin> get` works from a plain terminal first.

### Wifi radios (AC1200)

The AC1200 module exposes **two** wifi interfaces rather than one, so the
widget doesn't assume a single interface — it enumerates everything under
`/sys/class/net/*/wireless` on every poll and shows one toggle row per
interface it finds, with live up/down and SSID state parsed from `iw dev
<iface> link`. Toggling brings the interface up/down via `ip link set
<iface> up|down`; it does not manage NetworkManager connections/SSIDs, only
the radio's link state.

If your system also has an onboard wifi radio unrelated to the AC1200,
exclude its interface name (e.g. `wlan0`) via the "Wifi interfaces to
ignore" plugin setting so it doesn't show up as a third row.

### Bluetooth (AC1200)

The module also exposes **two** Bluetooth adapters. These are enumerated via
`rfkill list bluetooth` (parsing `Soft blocked`/`Hard blocked` per `hciN`
entry) and toggled with `rfkill block <index>` / `rfkill unblock <index>` —
the standard software radio kill-switch, same mechanism as airplane mode.
This only flips the radio on/off; it doesn't manage pairing or connections.
A `Hard blocked` adapter (a physical kill switch, not applicable on this
board) can't be re-enabled from software, so its row is shown but disabled.

## Install

```sh
git clone <this-repo> ~/.config/DankMaterialShell/plugins/aioAntennaControl
dms restart
```

Then in DankMaterialShell: **Settings → Plugins → Scan for Plugins** → enable
"AIO Antenna Control" → **Settings → DankBar → Add widget** → pick it.

## Usage

The bar pill shows a single antenna icon plus an "N/6" count of currently
active features (GPS, LoRa, SDR, internal USB, any wifi radio, any Bluetooth
adapter) — it doesn't break each one out individually to avoid crowding the
bar; open the popout for that.

- Left-click the pill to open the popout and toggle GPS/LoRa/SDR/USB/wifi/
  Bluetooth individually.
- Right-click the pill for an instant kill-switch (everything off, including
  bringing down wifi interfaces and blocking Bluetooth adapters).
- "All Off" button in the popout does the same.

Toggling "Internal USB" on powers the internal USB header — plug the AC1200
USB-C wifi module in there and flip this on. Once it powers up and enumerates
(may take a couple seconds), its wifi interfaces should appear as separate
rows below; flipping "Internal USB" off cuts power to the whole module.

## Files

- `plugin.json` — plugin manifest
- `AioAntennaWidget.qml` — bar pill + GPIO/wifi/Bluetooth control and polling logic
- `AioAntennaPanel.qml` — popout contents
- `AioAntennaRow.qml` — reusable toggle row
- `AioAntennaSettings.qml` — refresh interval / pinctrl path / ignored-wifi settings
