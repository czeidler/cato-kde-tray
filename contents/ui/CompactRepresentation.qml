/*
    Cato VPN Tray – tray icon.

    A tinted VPN icon: green when connected, amber while connecting or
    waiting for sign-in, red when disconnected, greyed out while unknown.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

MouseArea {
    id: compactRoot

    required property PlasmoidItem plasmoidItem

    readonly property bool busy: plasmoidItem.actionPending
                              || plasmoidItem.vpnStatus === "connecting"
                              || plasmoidItem.vpnStatus === "disconnecting"

    // Size hints for panels; the system tray sizes the item itself.
    Layout.minimumWidth: {
        switch (Plasmoid.formFactor) {
        case PlasmaCore.Types.Vertical:   return 0
        case PlasmaCore.Types.Horizontal: return height
        default:                          return Kirigami.Units.gridUnit * 3
        }
    }
    Layout.minimumHeight: {
        switch (Plasmoid.formFactor) {
        case PlasmaCore.Types.Vertical:   return width
        case PlasmaCore.Types.Horizontal: return 0
        default:                          return Kirigami.Units.gridUnit * 3
        }
    }

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    // Left click: open/close the popup.
    onClicked: mouse => {       
        compactRoot.plasmoidItem.expanded = !compactRoot.plasmoidItem.expanded
    }

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        source: compactRoot.plasmoidItem.iconName
        isMask: true
        color: compactRoot.plasmoidItem.statusColor
        active: compactRoot.containsMouse
        opacity: compactRoot.busy ? 0.35 : 1
    }

    PlasmaComponents3.BusyIndicator {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        running: compactRoot.busy
        visible: running
    }
}
