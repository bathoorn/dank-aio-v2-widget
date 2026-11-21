import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string label: ""
    property string pinLabel: ""
    property string statusText: ""
    property bool active: false
    property bool enabled: true

    signal toggled()

    width: parent ? parent.width : 0
    height: 48
    radius: Theme.cornerRadius
    color: rowMouseArea.containsMouse ? Theme.surfaceHover : "transparent"
    opacity: enabled ? 1.0 : 0.5

    Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingS

        DankIcon {
            name: root.iconName
            size: Theme.iconSize - 4
            color: root.active ? Theme.primary : Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            width: root.width - (Theme.iconSize - 4) - 40 - Theme.spacingS * 4

            StyledText {
                text: root.label
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                width: parent.width
                elide: Text.ElideRight
            }

            StyledText {
                text: root.statusText !== "" ? root.statusText : (root.pinLabel + " · " + (root.active ? "On" : "Off"))
                font.pixelSize: Theme.fontSizeSmall
                isMonospace: true
                color: Theme.surfaceVariantText
                width: parent.width
                elide: Text.ElideRight
            }
        }
    }

    Rectangle {
        width: 40
        height: 22
        radius: 11
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        color: root.active ? Theme.primary : Theme.surfaceVariant
        border.width: 1
        border.color: Theme.outline

        Rectangle {
            width: 16
            height: 16
            radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: root.active ? parent.width - width - 3 : 3
            color: Theme.surface

            Behavior on x {
                NumberAnimation { duration: 120 }
            }
        }
    }

    DankRipple {
        id: rowRipple
        rippleColor: Theme.surfaceText
        cornerRadius: root.radius
    }

    MouseArea {
        id: rowMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.enabled
        onPressed: mouse => rowRipple.trigger(mouse.x, mouse.y)
        onClicked: root.toggled()
    }
}
