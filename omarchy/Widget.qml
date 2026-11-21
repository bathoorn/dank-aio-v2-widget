import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Controls the GPIO-gated power rails on the Hackergadgets AIO v2 board
// (uConsole CM4/CM5 expansion board). Pins per the vendor setup guide and
// forum thread (BCM numbering, active-high, driven with `pinctrl`):
//   GPS          = GPIO27
//   LoRa         = GPIO16
//   SDR          = GPIO7
//   Internal USB = GPIO23 (powers the internal USB header, e.g. an
//                  AC1200 USB-C wifi module plugged into it)
// Verify against your board revision if these don't behave as expected.
//
// Mouse-only: unlike the first-party panels this is modeled on, there is no
// PanelKeyCatcher/arrow-key row navigation here.
Panel {
  id: root

  moduleName: "aioAntennaControl"
  ipcTarget: "aioAntennaControl"

  readonly property int gpsPin: 27
  readonly property int loraPin: 16
  readonly property int sdrPin: 7
  readonly property int usbPin: 23

  readonly property int refreshInterval: Number(root.setting("refreshInterval", 5)) || 5
  readonly property string pinctrlPath: String(root.setting("pinctrlPath", "pinctrl"))
  readonly property string ignoredWifiInterfaces: String(root.setting("ignoredWifiInterfaces", ""))

  property bool pinctrlAvailable: true
  property bool gpsOn: false
  property bool loraOn: false
  property bool sdrOn: false
  property bool usbOn: false

  // The AC1200 module exposes two wifi interfaces and two Bluetooth
  // adapters rather than one of each, so both are lists, not a single
  // on/off. Wifi entry: {name, up, connected, ssid}
  property var wifiInterfaces: []
  readonly property bool anyWifiUp: wifiInterfaces.some(function(w) { return w.up })
  readonly property bool anyWifiConnected: wifiInterfaces.some(function(w) { return w.connected })

  // Bluetooth entry: {index, name, softBlocked, hardBlocked}
  property var btAdapters: []
  readonly property bool anyBtUp: btAdapters.some(function(a) { return !a.softBlocked && !a.hardBlocked })

  readonly property int activeFeatureCount: (gpsOn ? 1 : 0) + (loraOn ? 1 : 0) + (sdrOn ? 1 : 0) + (usbOn ? 1 : 0) + (anyWifiUp ? 1 : 0) + (anyBtUp ? 1 : 0)
  readonly property int totalFeatureCount: 6

  // The AIO v2 also carries a hardware RTC. Syncing it is a one-shot
  // action (like aiov2_ctl's --sync-rtc), not a persistent toggle.
  property string rtcSyncStatus: ""

  readonly property string antennaIcon: "󰀃"
  readonly property string powerIcon: "󰐥"

  Process {
    id: whichProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(exitCode, exitStatus) {
      root.pinctrlAvailable = (exitCode === 0)
      if (root.pinctrlAvailable) refreshStatus()
    }
  }

  Process {
    id: statusProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(exitCode, exitStatus) {
      var out = String(statusProcess.stdout.text || "")
      if (exitCode !== 0 || out.length === 0) return
      root.gpsOn = Model.isLineOn(Model.pinLine(out, root.gpsPin))
      root.loraOn = Model.isLineOn(Model.pinLine(out, root.loraPin))
      root.sdrOn = Model.isLineOn(Model.pinLine(out, root.sdrPin))
      root.usbOn = Model.isLineOn(Model.pinLine(out, root.usbPin))
    }
  }

  Process {
    id: setProcess
    onExited: function(exitCode, exitStatus) { refreshStatus() }
  }

  Process {
    id: wifiStatusProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(exitCode, exitStatus) {
      root.wifiInterfaces = Model.parseWifiInterfaces(String(wifiStatusProcess.stdout.text || ""))
    }
  }

  Process {
    id: wifiToggleProcess
    onExited: function(exitCode, exitStatus) { refreshWifiStatus() }
  }

  Process {
    id: btStatusProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(exitCode, exitStatus) {
      root.btAdapters = Model.parseBluetoothAdapters(String(btStatusProcess.stdout.text || ""))
    }
  }

  Process {
    id: btToggleProcess
    onExited: function(exitCode, exitStatus) { refreshBluetoothStatus() }
  }

  Process {
    id: rtcSyncProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0) {
        root.rtcSyncStatus = "Synced just now"
      } else {
        var err = String(rtcSyncProcess.stderr.text || "").trim()
        root.rtcSyncStatus = err !== "" ? err : "Sync failed"
      }
    }
  }

  function checkPinctrl() {
    whichProcess.command = ["sh", "-c", "command -v " + root.pinctrlPath]
    whichProcess.running = true
  }

  function refreshStatus() {
    if (!root.pinctrlAvailable) return
    var cmd = root.pinctrlPath + " get " + [root.gpsPin, root.loraPin, root.sdrPin, root.usbPin].join(",")
    statusProcess.command = ["sh", "-c", cmd]
    statusProcess.running = true
  }

  function setFeature(pin, on) {
    var level = on ? "dh" : "dl"
    var cmd = root.pinctrlPath + " " + pin + " op && " + root.pinctrlPath + " " + pin + " " + level
    setProcess.command = ["sh", "-c", cmd]
    setProcess.running = true
  }

  function toggleGps() { setFeature(root.gpsPin, !root.gpsOn) }
  function toggleLora() { setFeature(root.loraPin, !root.loraOn) }
  function toggleSdr() { setFeature(root.sdrPin, !root.sdrOn) }
  function toggleUsb() { setFeature(root.usbPin, !root.usbOn) }

  function refreshWifiStatus() {
    wifiStatusProcess.command = ["sh", "-c", Model.wifiStatusScript(root.ignoredWifiInterfaces)]
    wifiStatusProcess.running = true
  }

  function setWifiInterfaceState(name, up) {
    var iface = Model.sanitizeToken(name)
    if (iface === "") return
    wifiToggleProcess.command = ["sh", "-c", "ip link set " + iface + " " + (up ? "up" : "down")]
    wifiToggleProcess.running = true
  }

  function toggleWifiInterface(name, currentlyUp) { setWifiInterfaceState(name, !currentlyUp) }

  function refreshBluetoothStatus() {
    btStatusProcess.command = ["sh", "-c", "rfkill list bluetooth 2>/dev/null"]
    btStatusProcess.running = true
  }

  function setBluetoothAdapterState(index, up) {
    var idx = parseInt(index, 10)
    if (isNaN(idx)) return
    btToggleProcess.command = ["rfkill", up ? "unblock" : "block", String(idx)]
    btToggleProcess.running = true
  }

  function toggleBluetoothAdapter(index, currentlyUp) { setBluetoothAdapterState(index, !currentlyUp) }

  function syncRtc() {
    var lines = []
    lines.push("if command -v pkexec >/dev/null 2>&1; then")
    lines.push("  pkexec hwclock -w")
    lines.push("else")
    lines.push("  hwclock -w")
    lines.push("fi")
    rtcSyncProcess.command = ["sh", "-c", lines.join("\n")]
    rtcSyncProcess.running = true
  }

  function allOff() {
    setFeature(root.gpsPin, false)
    setFeature(root.loraPin, false)
    setFeature(root.sdrPin, false)
    setFeature(root.usbPin, false)
    root.wifiInterfaces.forEach(function(w) { if (w.up) setWifiInterfaceState(w.name, false) })
    root.btAdapters.forEach(function(a) { if (!a.softBlocked && !a.hardBlocked) setBluetoothAdapterState(a.index, false) })
  }

  Timer {
    id: updateTimer
    interval: root.refreshInterval * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      if (!root.pinctrlAvailable) checkPinctrl()
      else refreshStatus()
      refreshWifiStatus()
      refreshBluetoothStatus()
    }
  }

  Component.onCompleted: {
    checkPinctrl()
    refreshWifiStatus()
    refreshBluetoothStatus()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.antennaIcon
    onPressed: function(b) {
      if (b === Qt.RightButton) root.allOff()
      else root.toggle()
    }
  }

  // Laid out for the uConsole's short landscape screen: toggles sit two to a
  // row, wifi and Bluetooth share one "Radios" grid, and RTC sync shares the
  // bottom row with "All off". If it still doesn't fit (many interfaces),
  // the card caps at screen height and the content scrolls.
  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Flickable {
      id: scroller
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: scroller.width
        spacing: Style.spacing.panelGap

        readonly property real cellWidth: (width - Style.spacing.panelGap) / 2

        PanelHero {
          width: parent.width
          title: "AIO v2 antennas"
          meta: root.pinctrlAvailable ? "" : "pinctrl not found"
          detail: root.activeFeatureCount + "/" + root.totalFeatureCount
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.antennaIcon
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              color: root.activeFeatureCount > 0 ? Commons.Color.accent : Commons.Color.foreground
            }
          }
        }

        PanelSeparator { width: parent.width }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.spacing.panelGap
          rowSpacing: Style.spacing.panelGap

          Toggle {
            width: column.cellWidth
            label: "GPS"
            description: "GPIO" + root.gpsPin + (root.pinctrlAvailable ? "" : " — unavailable")
            checked: root.gpsOn
            enabled: root.pinctrlAvailable
            opacity: root.pinctrlAvailable ? 1.0 : 0.5
            onClicked: root.toggleGps()
          }

          Toggle {
            width: column.cellWidth
            label: "LoRa"
            description: "GPIO" + root.loraPin
            checked: root.loraOn
            enabled: root.pinctrlAvailable
            opacity: root.pinctrlAvailable ? 1.0 : 0.5
            onClicked: root.toggleLora()
          }

          Toggle {
            width: column.cellWidth
            label: "SDR"
            description: "GPIO" + root.sdrPin
            checked: root.sdrOn
            enabled: root.pinctrlAvailable
            opacity: root.pinctrlAvailable ? 1.0 : 0.5
            onClicked: root.toggleSdr()
          }

          Toggle {
            width: column.cellWidth
            label: "Internal USB"
            description: "GPIO" + root.usbPin
            checked: root.usbOn
            enabled: root.pinctrlAvailable
            opacity: root.pinctrlAvailable ? 1.0 : 0.5
            onClicked: root.toggleUsb()
          }
        }

        PanelSectionHeader {
          text: "Radios (AC1200)"
          visible: root.wifiInterfaces.length + root.btAdapters.length > 0
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.spacing.panelGap
          rowSpacing: Style.spacing.panelGap
          visible: root.wifiInterfaces.length + root.btAdapters.length > 0

          Repeater {
            model: root.wifiInterfaces

            Toggle {
              width: column.cellWidth
              label: "Wifi " + modelData.name
              description: modelData.up
                ? (modelData.connected ? modelData.ssid : "Not connected")
                : "Down"
              checked: modelData.up
              onClicked: root.toggleWifiInterface(modelData.name, modelData.up)
            }
          }

          Repeater {
            model: root.btAdapters

            Toggle {
              readonly property bool btEnabled: !modelData.softBlocked && !modelData.hardBlocked

              width: column.cellWidth
              label: "BT " + modelData.name
              description: modelData.hardBlocked ? "Hardware blocked" : (btEnabled ? "Enabled" : "Disabled")
              checked: btEnabled
              enabled: !modelData.hardBlocked
              onClicked: root.toggleBluetoothAdapter(modelData.index, btEnabled)
            }
          }
        }

        PanelSeparator { width: parent.width }

        Row {
          width: parent.width
          spacing: Style.spacing.rowPaddingX

          Column {
            width: parent.width - syncButton.width - allOffButton.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Text {
              textFormat: Text.PlainText
              text: "Board RTC"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.rtcSyncStatus !== "" ? root.rtcSyncStatus : "Write system time to the RTC"
              color: Qt.darker(Commons.Color.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Button {
            id: syncButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Sync"
            bordered: true
            onClicked: root.syncRtc()
          }

          Button {
            id: allOffButton
            anchors.verticalCenter: parent.verticalCenter
            text: "All off"
            iconText: root.powerIcon
            bordered: true
            foreground: Commons.Color.urgent
            enabled: root.pinctrlAvailable
            opacity: root.pinctrlAvailable ? 1.0 : 0.5
            onClicked: root.allOff()
          }
        }
      }
    }
  }
}
