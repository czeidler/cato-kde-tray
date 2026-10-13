/*
    Cato VPN Tray – client output window.

    A normal, resizable window showing the commands the applet ran and
    everything the client printed.  Opened from the popup, or by the applet
    itself when a connect attempt fails; in that case it closes again by
    itself once the VPN is connected.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Window {
    id: logWindow

    required property PlasmoidItem plasmoidItem
    readonly property var vpn: plasmoidItem

    // Set when the applet opened the window because something failed; such a
    // window closes by itself once the VPN is connected.
    property bool openedAutomatically: false

    title: i18n("Cato VPN – Client Output")
    flags: Qt.Window
    transientParent: null      // a top-level window, not a child of the panel
    visible: false
    color: content.Kirigami.Theme.backgroundColor

    minimumWidth: Kirigami.Units.gridUnit * 24
    minimumHeight: Kirigami.Units.gridUnit * 10
    width: Kirigami.Units.gridUnit * 40
    height: Kirigami.Units.gridUnit * 24

    function open(automatically) {
        if (!logWindow.visible) {
            logWindow.openedAutomatically = !!automatically
            logWindow.visible = true
        } else if (!automatically) {
            logWindow.openedAutomatically = false   // the user asked for it: keep it
        }
        logWindow.raise()
        logWindow.requestActivate()
        Qt.callLater(outputFlickable.scrollToEnd)
    }

    function closeIfOpenedAutomatically() {
        if (logWindow.visible && logWindow.openedAutomatically) {
            logWindow.visible = false
        }
    }

    onVisibleChanged: {
        if (!visible) {
            logWindow.openedAutomatically = false
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel, StandardKey.Close]
        onActivated: logWindow.visible = false
    }

    Item {
        id: content
        anchors.fill: parent

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            // ── Toolbar: state + actions ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    source: logWindow.vpn.iconName
                    isMask: true
                    color: logWindow.vpn.statusColor
                }

                QQC2.Label {
                    text: logWindow.vpn.statusLabel
                    color: logWindow.vpn.statusColor
                    font.bold: true
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: logWindow.vpn.statusDetail
                    opacity: 0.7
                    elide: Text.ElideRight
                }

                Item {
                    Layout.fillWidth: true
                    visible: logWindow.vpn.statusDetail === ""
                }

                QQC2.CheckBox {
                    id: followCheck
                    text: i18n("Follow output")
                    checked: true
                }

                QQC2.ToolButton {
                    text: i18n("Copy All")
                    icon.name: "edit-copy"
                    enabled: logWindow.vpn.transcript !== ""
                    onClicked: {
                        outputArea.selectAll()
                        outputArea.copy()
                        outputArea.deselect()
                    }
                }

                QQC2.ToolButton {
                    text: i18n("Clear")
                    icon.name: "edit-clear-history"
                    enabled: logWindow.vpn.transcript !== ""
                    onClicked: logWindow.vpn.clearTranscript()
                }
            }

            // ── Console ──────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#1b1e20"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                radius: Kirigami.Units.cornerRadius

                Flickable {
                    id: outputFlickable
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                    function scrollToEnd() {
                        contentY = Math.max(0, contentHeight - height)
                    }

                    QQC2.TextArea.flickable: QQC2.TextArea {
                        id: outputArea
                        text: logWindow.vpn.transcript !== ""
                            ? logWindow.vpn.transcript
                            : i18n("(no client output yet – it appears here when you connect, disconnect or refresh)")
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: "monospace"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: "#d8dee9"
                        background: null
                        onTextChanged: {
                            if (followCheck.checked) {
                                Qt.callLater(outputFlickable.scrollToEnd)
                            }
                        }
                    }
                }
            }

            // ── Footer ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n("Commands run by the applet and everything the client printed. While this window is open the status checks are logged too.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    wrapMode: Text.Wrap
                }

                QQC2.Button {
                    text: i18n("Close")
                    icon.name: "dialog-close"
                    onClicked: logWindow.visible = false
                }
            }
        }
    }
}
