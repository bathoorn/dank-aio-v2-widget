import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "."

// Controls the GPIO-gated power rails on the Hackergadgets AIO v2 board
// (uConsole CM4/CM5 expansion board). Pins per the vendor setup guide and
// forum thread (BCM numbering, active-high, driven with `pinctrl`):
//   GPS          = GPIO27
//   LoRa         = GPIO16
//   SDR          = GPIO7
//   Internal USB = GPIO23 (powers the internal USB header, e.g. an
//                  AC1200 USB-C wifi module plugged into it)
// Verify against your board revision if these don't behave as expected.
PluginComponent {
    id: root

    readonly property int gpsPin: 27
    readonly property int loraPin: 16
    readonly property int sdrPin: 7
    readonly property int usbPin: 23

    readonly property int refreshInterval: pluginData?.refreshInterval ?? 5
    readonly property string pinctrlPath: pluginData?.pinctrlPath ?? "pinctrl"
    readonly property string ignoredWifiInterfaces: pluginData?.ignoredWifiInterfaces ?? ""

    property bool pinctrlAvailable: true
    property bool gpsOn: false
    property bool loraOn: false
    property bool sdrOn: false
    property bool usbOn: false
    property bool statusKnown: false

    // The AC1200 module exposes two wifi interfaces and two Bluetooth
    // adapters rather than one of each, so both are lists, not a single
    // on/off. Wifi entry: {name, up, connected, ssid}
    property var wifiInterfaces: []
    readonly property bool anyWifiUp: root.wifiInterfaces.some(function(w) { return w.up; })
    readonly property bool anyWifiConnected: root.wifiInterfaces.some(function(w) { return w.connected; })

    // Bluetooth entry: {index, name, softBlocked, hardBlocked}
    property var btAdapters: []
    readonly property bool anyBtUp: root.btAdapters.some(function(a) { return !a.softBlocked && !a.hardBlocked; })

    readonly property int activeFeatureCount: (gpsOn ? 1 : 0) + (loraOn ? 1 : 0) + (sdrOn ? 1 : 0) + (usbOn ? 1 : 0) + (anyWifiUp ? 1 : 0) + (anyBtUp ? 1 : 0)
    readonly property int totalFeatureCount: 6

    // The AIO v2 also carries a hardware RTC. Syncing it is a one-shot
    // action (like aiov2_ctl's --sync-rtc), not a persistent toggle.
    property string rtcSyncStatus: ""

    function pinLine(output, pin) {
        var re = new RegExp("^\\s*" + pin + ":.*$", "m");
        var match = re.exec(output);
        return match ? match[0] : "";
    }

    function isLineOn(line) {
        return /\bhi\b/i.test(line) || /\bdh\b/i.test(line);
    }

    Process {
        id: whichProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            root.pinctrlAvailable = (exitCode === 0);
            if (root.pinctrlAvailable) {
                refreshStatus();
            }
        }
    }

    Process {
        id: statusProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            var out = String(statusProcess.stdout.text || "");
            root.statusKnown = exitCode === 0 && out.length > 0;
            if (!root.statusKnown) return;

            root.gpsOn = isLineOn(pinLine(out, root.gpsPin));
            root.loraOn = isLineOn(pinLine(out, root.loraPin));
            root.sdrOn = isLineOn(pinLine(out, root.sdrPin));
            root.usbOn = isLineOn(pinLine(out, root.usbPin));
        }
    }

    Process {
        id: setProcess
        onExited: function(exitCode, exitStatus) {
            refreshStatus();
        }
    }

    Process {
        id: wifiStatusProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            var out = String(wifiStatusProcess.stdout.text || "");
            root.wifiInterfaces = parseWifiInterfaces(out);
        }
    }

    Process {
        id: wifiToggleProcess
        onExited: function(exitCode, exitStatus) {
            refreshWifiStatus();
        }
    }

    Process {
        id: btStatusProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            var out = String(btStatusProcess.stdout.text || "");
            root.btAdapters = parseBluetoothAdapters(out);
        }
    }

    Process {
        id: btToggleProcess
        onExited: function(exitCode, exitStatus) {
            refreshBluetoothStatus();
        }
    }

    Process {
        id: rtcSyncProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.rtcSyncStatus = "Synced just now";
                ToastService.showInfo("RTC synced", "Hardware clock updated to system time");
            } else {
                var err = String(rtcSyncProcess.stderr.text || "").trim();
                root.rtcSyncStatus = "Sync failed";
                ToastService.showError("RTC sync failed", err !== "" ? err : "pkexec/hwclock unavailable or permission denied");
            }
        }
    }

    function sanitizeToken(value) {
        return String(value || "").replace(/[^A-Za-z0-9_.:-]/g, "");
    }

    function parseWifiInterfaces(output) {
        var blocks = output.split(/^### /m).filter(function(b) { return b.trim() !== ""; });
        return blocks.map(function(block) {
            var lines = block.split("\n");
            var header = lines[0].trim().split(/\s+/);
            var name = header[0] || "";
            var state = header[1] || "";
            var rest = lines.slice(1).join("\n");
            var connected = /Connected to/i.test(rest);
            var ssidMatch = /SSID:\s*(.+)/i.exec(rest);
            return {
                name: name,
                up: state === "up",
                connected: connected,
                ssid: connected && ssidMatch ? ssidMatch[1].trim() : ""
            };
        });
    }

    function refreshWifiStatus() {
        var ignore = root.ignoredWifiInterfaces.split(/[\s,]+/).map(sanitizeToken).filter(function(s) { return s !== ""; });
        var lines = [];
        lines.push("for i in /sys/class/net/*/wireless; do");
        lines.push("  [ -e \"$i\" ] || continue");
        lines.push("  IFACE=$(basename $(dirname \"$i\"))");
        ignore.forEach(function(name) {
            lines.push("  [ \"$IFACE\" = \"" + name + "\" ] && continue");
        });
        lines.push("  STATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)");
        lines.push("  echo \"### $IFACE $STATE\"");
        lines.push("  iw dev \"$IFACE\" link 2>/dev/null");
        lines.push("done");
        wifiStatusProcess.command = ["sh", "-c", lines.join("\n")];
        wifiStatusProcess.running = true;
    }

    function setWifiInterfaceState(name, up) {
        var iface = sanitizeToken(name);
        if (iface === "") return;
        wifiToggleProcess.command = ["sh", "-c", "ip link set " + iface + " " + (up ? "up" : "down")];
        wifiToggleProcess.running = true;
    }

    function toggleWifiInterface(name, currentlyUp) {
        setWifiInterfaceState(name, !currentlyUp);
    }

    function parseBluetoothAdapters(output) {
        var blocks = output.split(/\n(?=\d+: )/).filter(function(b) { return b.trim() !== ""; });
        return blocks.map(function(block) {
            var header = /^(\d+):\s*(\S+):/.exec(block);
            if (!header) return null;
            var soft = /Soft blocked:\s*(yes|no)/i.exec(block);
            var hard = /Hard blocked:\s*(yes|no)/i.exec(block);
            return {
                index: header[1],
                name: header[2],
                softBlocked: soft ? soft[1].toLowerCase() === "yes" : false,
                hardBlocked: hard ? hard[1].toLowerCase() === "yes" : false
            };
        }).filter(function(a) { return a !== null; });
    }

    function refreshBluetoothStatus() {
        btStatusProcess.command = ["sh", "-c", "rfkill list bluetooth 2>/dev/null"];
        btStatusProcess.running = true;
    }

    function setBluetoothAdapterState(index, up) {
        var idx = parseInt(index, 10);
        if (isNaN(idx)) return;
        btToggleProcess.command = ["rfkill", up ? "unblock" : "block", String(idx)];
        btToggleProcess.running = true;
    }

    function toggleBluetoothAdapter(index, currentlyUp) {
        setBluetoothAdapterState(index, !currentlyUp);
    }

    function syncRtc() {
        var lines = [];
        lines.push("if command -v pkexec >/dev/null 2>&1; then");
        lines.push("  pkexec hwclock -w");
        lines.push("else");
        lines.push("  hwclock -w");
        lines.push("fi");
        rtcSyncProcess.command = ["sh", "-c", lines.join("\n")];
        rtcSyncProcess.running = true;
    }

    function checkPinctrl() {
        whichProcess.command = ["sh", "-c", "command -v " + root.pinctrlPath];
        whichProcess.running = true;
    }

    function refreshStatus() {
        if (!root.pinctrlAvailable) return;
        var cmd = [root.pinctrlPath, "get", root.gpsPin, root.loraPin, root.sdrPin, root.usbPin].join(" ");
        statusProcess.command = ["sh", "-c", cmd];
        statusProcess.running = true;
    }

    function setFeature(pin, on) {
        var level = on ? "dh" : "dl";
        var cmd = root.pinctrlPath + " " + pin + " op && " + root.pinctrlPath + " " + pin + " " + level;
        setProcess.command = ["sh", "-c", cmd];
        setProcess.running = true;
    }

    function toggleGps() { setFeature(root.gpsPin, !root.gpsOn); }
    function toggleLora() { setFeature(root.loraPin, !root.loraOn); }
    function toggleSdr() { setFeature(root.sdrPin, !root.sdrOn); }
    function toggleUsb() { setFeature(root.usbPin, !root.usbOn); }

    function allOff() {
        setFeature(root.gpsPin, false);
        setFeature(root.loraPin, false);
        setFeature(root.sdrPin, false);
        setFeature(root.usbPin, false);
        root.wifiInterfaces.forEach(function(w) {
            if (w.up) setWifiInterfaceState(w.name, false);
        });
        root.btAdapters.forEach(function(a) {
            if (!a.softBlocked && !a.hardBlocked) setBluetoothAdapterState(a.index, false);
        });
    }

    Timer {
        id: updateTimer
        interval: root.refreshInterval * 1000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: {
            if (!root.pinctrlAvailable) {
                checkPinctrl();
            } else {
                refreshStatus();
            }
            refreshWifiStatus();
            refreshBluetoothStatus();
        }
    }

    Component.onCompleted: {
        checkPinctrl();
        refreshWifiStatus();
        refreshBluetoothStatus();
    }

    pillRightClickAction: () => {
        if (root.pinctrlAvailable) {
            root.allOff();
        }
    }

    popoutWidth: 320
    popoutHeight: 620

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot
            headerText: "AIO v2 Antennas"
            detailsText: !root.pinctrlAvailable
                ? "pinctrl not found"
                : (root.gpsOn || root.loraOn || root.sdrOn || root.usbOn || root.anyWifiUp || root.anyBtUp ? "Active" : "All off")
            showCloseButton: true

            AioAntennaPanel {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                daemon: root
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "settings_input_antenna"
                size: root.iconSize
                color: !root.pinctrlAvailable
                    ? Theme.error
                    : (root.activeFeatureCount > 0 ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.pinctrlAvailable && root.activeFeatureCount > 0
                text: root.activeFeatureCount + "/" + root.totalFeatureCount
                font.pixelSize: Theme.fontSizeSmall
                isMonospace: true
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: "warning"
                size: root.iconSize - 4
                visible: !root.pinctrlAvailable
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "settings_input_antenna"
                size: root.iconSize
                color: !root.pinctrlAvailable
                    ? Theme.error
                    : (root.activeFeatureCount > 0 ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
