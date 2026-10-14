/*
    Cato VPN Tray – client output window.

    A normal, resizable window with the last few commands the applet ran.
    The list on the left has the newest command first; the output of the
    selected one is shown on the right.  Opened from the popup, or by the
    applet itself when a connect attempt fails; in that case it closes again
    by itself once the VPN is connected.

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

    // What the console shows: the selected command and everything it printed
    readonly property string shownText: commandList.currentItem
        ? "[" + formatTime(commandList.currentItem.timestamp) + "] $ "
              + commandList.currentItem.command + "\n" + commandList.currentItem.output
        : ""

    title: i18n("Cato VPN – Client Output")
    flags: Qt.Window
    transientParent: null      // a top-level window, not a child of the panel
    visible: false
    color: content.Kirigami.Theme.backgroundColor

    minimumWidth: Kirigami.Units.gridUnit * 28
    minimumHeight: Kirigami.Units.gridUnit * 10
    width: Kirigami.Units.gridUnit * 48
    height: Kirigami.Units.gridUnit * 24

    function formatTime(timestamp) {
        return Qt.formatTime(new Date(timestamp), "hh:mm:ss")
    }

    function selectLatest() {
        if (commandList.count > 0) {
            commandList.currentIndex = 0
        }
    }

    function open(automatically) {
        if (!logWindow.visible) {
            logWindow.openedAutomatically = !!automatically
            logWindow.visible = true
        } else if (!automatically) {
            logWindow.openedAutomatically = false   // the user asked for it: keep it
        }
        logWindow.raise()
        logWindow.requestActivate()
        logWindow.selectLatest()
        Qt.callLater(outputFlickable.scrollToTop)
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

                QQC2.ToolButton {
                    text: i18n("Copy")
                    icon.name: "edit-copy"
                    enabled: logWindow.shownText !== ""
                    onClicked: {
                        outputArea.selectAll()
                        outputArea.copy()
                        outputArea.deselect()
                    }

                    QQC2.ToolTip.text: i18n("Copy the shown command and its output")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                QQC2.ToolButton {
                    text: i18n("Clear")
                    icon.name: "edit-clear-history"
                    enabled: commandList.count > 0
                    onClicked: logWindow.vpn.clearCommandLog()
                }
            }

            // ── Command list (left) and console (right) ──────────────────────
            QQC2.SplitView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: Qt.Horizontal

                Rectangle {
                    QQC2.SplitView.preferredWidth: Kirigami.Units.gridUnit * 13
                    QQC2.SplitView.minimumWidth: Kirigami.Units.gridUnit * 7

                    Kirigami.Theme.colorSet: Kirigami.Theme.View
                    Kirigami.Theme.inherit: false
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: Kirigami.ColorUtils.linearInterpolation(
                        Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, Kirigami.Theme.frameContrast)
                    radius: Kirigami.Units.cornerRadius

                    ListView {
                        id: commandList
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                        focus: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: logWindow.vpn.commandLog

                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                        // Start every command's output at the top
                        onCurrentItemChanged: Qt.callLater(outputFlickable.scrollToTop)

                        delegate: QQC2.ItemDelegate {
                            id: entry

                            required property int index
                            required property double timestamp
                            required property string command
                            required property string output
                            required property int exitCode

                            readonly property color textColor: highlighted
                                ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor

                            width: commandList.width
                            highlighted: entry.ListView.isCurrentItem
                            onClicked: commandList.currentIndex = entry.index

                            contentItem: ColumnLayout {
                                spacing: 0

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: logWindow.formatTime(entry.timestamp)
                                    font: Kirigami.Theme.smallFont
                                    color: entry.textColor
                                    opacity: 0.7
                                }

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: entry.command
                                    color: entry.textColor
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        QQC2.Label {
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.largeSpacing * 2
                            visible: commandList.count === 0
                            text: i18n("No commands yet")
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            opacity: 0.6
                        }
                    }
                }

                Rectangle {
                    QQC2.SplitView.fillWidth: true
                    QQC2.SplitView.minimumWidth: Kirigami.Units.gridUnit * 10
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

                        function scrollToTop() {
                            contentY = 0
                        }

                        QQC2.TextArea.flickable: QQC2.TextArea {
                            id: outputArea
                            text: logWindow.shownText !== ""
                                ? logWindow.shownText
                                : i18n("(no client output yet – it appears here when you connect, disconnect or refresh)")
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: "#d8dee9"
                            background: null
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
                    text: i18n("The last %1 commands the applet ran, newest first, with everything the client printed. While this window is open the status checks are logged too.", logWindow.vpn.maxLogEntries)
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
