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

    Column {
        width: parent.width
        spacing: 2

        AioAntennaRow {
            width: parent.width
            iconName: "satellite_alt"
            label: "GPS"
            pinLabel: "GPIO" + (daemon?.gpsPin ?? "")
            active: daemon?.gpsOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleGps()
        }

        AioAntennaRow {
            width: parent.width
            iconName: "sensors"
            label: "LoRa"
            pinLabel: "GPIO" + (daemon?.loraPin ?? "")
            active: daemon?.loraOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleLora()
        }

        AioAntennaRow {
            width: parent.width
            iconName: "radio"
            label: "SDR"
            pinLabel: "GPIO" + (daemon?.sdrPin ?? "")
            active: daemon?.sdrOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleSdr()
        }

        AioAntennaRow {
            width: parent.width
            iconName: "usb"
            label: "Internal USB"
            pinLabel: "GPIO" + (daemon?.usbPin ?? "")
            active: daemon?.usbOn ?? false
            enabled: daemon?.pinctrlAvailable ?? false
            onToggled: daemon && daemon.toggleUsb()
        }
    }

    StyledText {
        text: "Wifi (AC1200)"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceVariantText
        visible: (daemon?.wifiInterfaces?.length ?? 0) > 0
    }

    Column {
        width: parent.width
        spacing: 2
        visible: (daemon?.wifiInterfaces?.length ?? 0) > 0

        Repeater {
            model: daemon?.wifiInterfaces ?? []

            AioAntennaRow {
                width: parent.width
                iconName: modelData.up ? "wifi" : "wifi_off"
                label: modelData.name
                statusText: modelData.up
                    ? (modelData.connected ? "Connected: " + modelData.ssid : "Up, not connected")
                    : "Down"
                active: modelData.up
                enabled: true
                onToggled: daemon && daemon.toggleWifiInterface(modelData.name, modelData.up)
            }
        }
    }

    StyledText {
        text: "No wifi adapter detected"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        visible: (daemon?.wifiInterfaces?.length ?? 0) === 0
    }

    StyledText {
        text: "Bluetooth (AC1200)"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceVariantText
        visible: (daemon?.btAdapters?.length ?? 0) > 0
    }

    Column {
        width: parent.width
        spacing: 2
        visible: (daemon?.btAdapters?.length ?? 0) > 0

        Repeater {
            model: daemon?.btAdapters ?? []

            AioAntennaRow {
                readonly property bool btEnabled: !modelData.softBlocked && !modelData.hardBlocked

                width: parent.width
                iconName: btEnabled ? "bluetooth" : "bluetooth_disabled"
                label: modelData.name
                statusText: modelData.hardBlocked
                    ? "Hardware blocked"
                    : (btEnabled ? "Enabled" : "Disabled")
                active: btEnabled
                enabled: !modelData.hardBlocked
                onToggled: daemon && daemon.toggleBluetoothAdapter(modelData.index, btEnabled)
            }
        }
    }

    StyledText {
        text: "No Bluetooth adapter detected"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        visible: (daemon?.btAdapters?.length ?? 0) === 0
    }

    StyledText {
        text: "Board"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceVariantText
    }

    Rectangle {
        width: parent.width
        height: 48
        color: "transparent"

        Row {
            anchors.fill: parent
            anchors.rightMargin: 76
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
                    text: "Hardware clock (RTC)"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    width: parent.width
                    elide: Text.ElideRight
                }

                StyledText {
                    text: (daemon?.rtcSyncStatus ?? "") !== "" ? daemon.rtcSyncStatus : "Write system time to the board RTC"
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
            anchors.right: parent.right
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
    }

    Rectangle {
        width: parent.width
        height: 40
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
