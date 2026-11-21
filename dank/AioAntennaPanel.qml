import QtQuick
import qs.Common
import qs.Widgets
import "."

Column {
    id: root

    property var daemon: null

    width: parent.width
    spacing: Theme.spacingM

    StyledRect {
        width: parent.width
        height: warnCol.implicitHeight + Theme.spacingS * 2
        visible: !(daemon?.pinctrlAvailable ?? true)
        color: Theme.withAlpha(Theme.error, 0.1)
        border.width: 1
        border.color: Theme.withAlpha(Theme.error, 0.3)

        Row {
            id: warnCol
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            DankIcon {
                name: "warning"
                size: Theme.iconSize - 6
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "pinctrl not found on PATH"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Two to a row so the popout fits the uConsole's short landscape screen.
    Grid {
        id: gpioGrid
        width: parent.width
        columns: 2
        columnSpacing: Theme.spacingS
        rowSpacing: 2

        readonly property real cellWidth: (width - columnSpacing) / 2

        AioAntennaRow {
            width: gpioGrid.cellWidth
            iconName: "satellite_alt"
            label: "GPS"
            pinLabel: "GPIO" + (daemon?.gpsPin ?? "")
            active: daemon?.gpsOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleGps()
        }

        AioAntennaRow {
            width: gpioGrid.cellWidth
            iconName: "sensors"
            label: "LoRa"
            pinLabel: "GPIO" + (daemon?.loraPin ?? "")
            active: daemon?.loraOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleLora()
        }

        AioAntennaRow {
            width: gpioGrid.cellWidth
            iconName: "radio"
            label: "SDR"
            pinLabel: "GPIO" + (daemon?.sdrPin ?? "")
            active: daemon?.sdrOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleSdr()
        }

        AioAntennaRow {
            width: gpioGrid.cellWidth
            iconName: "usb"
            label: "Internal USB"
            pinLabel: "GPIO" + (daemon?.usbPin ?? "")
            active: daemon?.usbOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleUsb()
        }
    }

    StyledText {
        readonly property bool hasRadios: (daemon?.wifiInterfaces?.length ?? 0) + (daemon?.btAdapters?.length ?? 0) > 0
        text: hasRadios ? "Radios (AC1200)" : "No AC1200 radios detected"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: hasRadios ? Font.Medium : Font.Normal
        color: Theme.surfaceVariantText
    }

    Grid {
        id: radioGrid
        width: parent.width
        columns: 2
        columnSpacing: Theme.spacingS
        rowSpacing: 2
        visible: (daemon?.wifiInterfaces?.length ?? 0) + (daemon?.btAdapters?.length ?? 0) > 0

        readonly property real cellWidth: (width - columnSpacing) / 2

        Repeater {
            model: daemon?.wifiInterfaces ?? []

            AioAntennaRow {
                width: radioGrid.cellWidth
                iconName: modelData.up ? "wifi" : "wifi_off"
                label: "Wifi " + modelData.name
                statusText: modelData.up
                    ? (modelData.connected ? modelData.ssid : "Not connected")
                    : "Down"
                active: modelData.up
                enabled: true
                onToggled: daemon && daemon.toggleWifiInterface(modelData.name, modelData.up)
            }
        }

        Repeater {
            model: daemon?.btAdapters ?? []

            AioAntennaRow {
                readonly property bool btEnabled: !modelData.softBlocked && !modelData.hardBlocked

                width: radioGrid.cellWidth
                iconName: btEnabled ? "bluetooth" : "bluetooth_disabled"
                label: "BT " + modelData.name
                statusText: modelData.hardBlocked
                    ? "Hardware blocked"
                    : (btEnabled ? "Enabled" : "Disabled")
                active: btEnabled
                enabled: !modelData.hardBlocked
                onToggled: daemon && daemon.toggleBluetoothAdapter(modelData.index, btEnabled)
            }
        }
    }

    // Board RTC sync and All Off share the bottom row.
    Rectangle {
        width: parent.width
        height: 48
        color: "transparent"

        Row {
            anchors.fill: parent
            anchors.rightMargin: 64 + 96 + Theme.spacingS * 2
            spacing: Theme.spacingS

            DankIcon {
                name: "schedule"
                size: Theme.iconSize - 4
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                width: parent.width - (Theme.iconSize - 4) - Theme.spacingS

                StyledText {
                    text: "Board RTC"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    width: parent.width
                    elide: Text.ElideRight
                }

                StyledText {
                    text: (daemon?.rtcSyncStatus ?? "") !== "" ? daemon.rtcSyncStatus : "Write system time to the RTC"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    width: parent.width
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            width: 64
            height: 28
            radius: Theme.cornerRadius
            anchors.right: allOffButton.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            color: rtcMouseArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.8) : Theme.primary

            StyledText {
                anchors.centerIn: parent
                text: "Sync"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surface
            }

            DankRipple {
                id: rtcRipple
                rippleColor: Theme.surface
                cornerRadius: parent.radius
            }

            MouseArea {
                id: rtcMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => rtcRipple.trigger(mouse.x, mouse.y)
                onClicked: daemon && daemon.syncRtc()
            }
        }

        Rectangle {
            id: allOffButton
            width: 96
            height: 28
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.cornerRadius
            opacity: (daemon?.pinctrlAvailable ?? false) ? 1.0 : 0.5
            color: allOffMouseArea.containsMouse ? Theme.withAlpha(Theme.error, 0.8) : Theme.error

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankIcon {
                    name: "power_settings_new"
                    size: Theme.iconSize - 8
                    color: Theme.surface
                }

                StyledText {
                    text: "All Off"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surface
                }
            }

            DankRipple {
                id: allOffRipple
                rippleColor: Theme.surface
                cornerRadius: parent.radius
            }

            MouseArea {
                id: allOffMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: daemon?.pinctrlAvailable ?? false
                onPressed: mouse => allOffRipple.trigger(mouse.x, mouse.y)
                onClicked: daemon && daemon.allOff()
            }
        }
    }
}
