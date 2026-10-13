/*
    Cato VPN Tray – popup shown when the tray icon is clicked.

    Shows the connection state and details, the connect form (user name,
    account, optional credential reset) and the Disconnect button while
    connected.  The client output lives in its own window (OutputWindow.qml).

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

PlasmaExtras.Representation {
    id: fullRoot

    required property PlasmoidItem plasmoidItem
    readonly property var vpn: plasmoidItem

    readonly property bool showConnect: vpn.vpnStatus === "disconnected"
                                     || vpn.vpnStatus === "unknown"
                                     || vpn.vpnStatus === "error"
    readonly property bool showDisconnect: !showConnect

    function detail(key) {
        return fullRoot.vpn.detail(key)
    }

    function copyToClipboard(text) {
        clipboardHelper.text = text
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        clipboardHelper.deselect()
    }

    function startConnect() {
        if (connectButton.enabled) {
            fullRoot.vpn.connectVPN(usernameField.text, accountField.text, resetCredCheck.checked)
        }
    }

    Connections {
        target: fullRoot.vpn

        function onVpnStatusChanged() {
            if (fullRoot.vpn.vpnStatus === "connected") {
                resetCredCheck.checked = false      // one-off option
            }
        }
    }

    // Invisible helper: QML has no clipboard API, but TextEdit.copy() works.
    TextEdit {
        id: clipboardHelper
        visible: false
        width: 0
        height: 0
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        // ── Header: icon, state, refresh ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                source: fullRoot.vpn.iconName
                isMask: true
                color: fullRoot.vpn.statusColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: fullRoot.vpn.statusLabel
                    color: fullRoot.vpn.statusColor
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                    elide: Text.ElideRight
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: fullRoot.vpn.statusDetail
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }

            PlasmaComponents3.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                running: fullRoot.vpn.actionPending || fullRoot.vpn.switching
                visible: running
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                text: i18n("Refresh now\nLast checked: %1", fullRoot.vpn.lastUpdated)
                display: QQC2.AbstractButton.IconOnly
                enabled: !fullRoot.vpn.isChecking
                onClicked: fullRoot.vpn.refreshStatus()

                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // ── Problems ─────────────────────────────────────────────────────────
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            visible: fullRoot.vpn.errorMessage !== "" && fullRoot.vpn.vpnStatus !== "error"
            text: fullRoot.vpn.errorMessage
        }

        // ── Browser sign-in pending ──────────────────────────────────────────
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Information
            visible: fullRoot.vpn.vpnStatus === "authenticating"
            text: fullRoot.vpn.authUrl !== ""
                ? i18n("Sign in with the link below to finish connecting.")
                : i18n("Waiting for the client to report the sign-in link…")
            actions: [
                Kirigami.Action {
                    text: i18n("Open in Browser")
                    icon.name: "internet-services"
                    visible: fullRoot.vpn.authUrl !== ""
                    onTriggered: Qt.openUrlExternally(fullRoot.vpn.authUrl)
                },
                Kirigami.Action {
                    text: i18n("Copy Link")
                    icon.name: "edit-copy"
                    visible: fullRoot.vpn.authUrl !== ""
                    onTriggered: fullRoot.copyToClipboard(fullRoot.vpn.authUrl)
                }
            ]
        }

        PlasmaComponents3.TextField {
            Layout.fillWidth: true
            visible: fullRoot.vpn.vpnStatus === "authenticating" && fullRoot.vpn.authUrl !== ""
            text: fullRoot.vpn.authUrl
            readOnly: true
            selectByMouse: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize

            QQC2.ToolTip.text: i18n("Sign-in link reported by the client")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        // ── Connection details ───────────────────────────────────────────────
        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: fullRoot.vpn.vpnStatus === "connected"

            PlasmaComponents3.Label {
                Kirigami.FormData.label: i18n("Account:")
                visible: text !== ""
                text: fullRoot.detail("account")
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                Kirigami.FormData.label: i18n("User:")
                visible: text !== ""
                text: fullRoot.detail("user")
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                Kirigami.FormData.label: i18n("PoP:")
                visible: text !== ""
                text: fullRoot.detail("pop name") !== ""
                    ? fullRoot.detail("pop name") + (fullRoot.detail("pop address") !== "" ? " (" + fullRoot.detail("pop address") + ")" : "")
                    : ""
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                Kirigami.FormData.label: i18n("Tunnel IP:")
                visible: text !== ""
                text: fullRoot.detail("tunnel ip")
            }
            PlasmaComponents3.Label {
                Kirigami.FormData.label: i18n("Duration:")
                visible: text !== ""
                text: fullRoot.detail("duration")
            }
            PlasmaComponents3.Label {
                Kirigami.FormData.label: i18n("Client:")
                visible: text !== ""
                text: fullRoot.detail("cato client")
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: fullRoot.vpn.updateAvailable !== ""
            text: i18n("Client update available: %1 (run “cato-sdp update” in a terminal)", fullRoot.vpn.updateAvailable)
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        // ── Connect form (shown while not connected) ─────────────────────────
        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: fullRoot.showConnect

            PlasmaComponents3.TextField {
                id: usernameField
                Kirigami.FormData.label: i18n("User name:")
                Layout.fillWidth: true
                placeholderText: i18n("user@example.com")
                inputMethodHints: Qt.ImhEmailCharactersOnly
                // Pre-filled from the last login; the binding breaks once edited
                text: fullRoot.vpn.cachedUsername
                onAccepted: fullRoot.startConnect()
            }

            PlasmaComponents3.TextField {
                id: accountField
                Kirigami.FormData.label: i18n("Account:")
                Layout.fillWidth: true
                placeholderText: i18n("Account name")
                text: fullRoot.vpn.cachedAccount
                onAccepted: fullRoot.startConnect()
            }

            PlasmaComponents3.CheckBox {
                id: resetCredCheck
                Kirigami.FormData.label: i18n("Options:")
                text: i18n("Reset stored credentials (%1)", fullRoot.vpn.resetCredentialsArgument)
            }
        }

        // ── Buttons ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                text: i18n("Logs")
                icon.name: "utilities-terminal"
                onClicked: fullRoot.vpn.showOutputWindow()

                QQC2.ToolTip.text: i18n("Open a window with the commands run and the client's output")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents3.Button {
                id: connectButton
                visible: fullRoot.showConnect
                text: fullRoot.vpn.actionPending ? i18n("Connecting…") : i18n("Connect")
                icon.name: "network-connect"
                enabled: fullRoot.vpn.canConnect
                      && usernameField.text.trim() !== ""
                      && accountField.text.trim() !== ""
                onClicked: fullRoot.startConnect()
            }

            PlasmaComponents3.Button {
                visible: fullRoot.showDisconnect
                text: i18n("Disconnect")
                icon.name: "network-disconnect"
                enabled: fullRoot.vpn.canDisconnect
                onClicked: fullRoot.vpn.disconnectVPN()
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
