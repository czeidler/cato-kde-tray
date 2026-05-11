/*
    Cato VPN Tray – settings page.

    Plasma binds every `cfg_<key>` property to the matching entry in
    config/main.xml and writes the values back when the dialog is applied.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configPage

    property alias cfg_username:          usernameField.text
    property alias cfg_account:           accountField.text
    property alias cfg_pollInterval:      pollSpin.value
    property alias cfg_fullPollInterval:  fullPollSpin.value
    property alias cfg_tunnelDevice:      tunnelDeviceField.text
    property alias cfg_statusCommand:     statusCmdField.text
    property alias cfg_connectCommand:    connectCmdField.text
    property alias cfg_disconnectCommand: disconnectCmdField.text
    property alias cfg_openSignInPage:    openSignInCheck.checked

    // Plasma passes the schema defaults as cfg_<key>Default; declare them so
    // the dialog does not log "does not have a property" warnings.
    property var cfg_usernameDefault
    property var cfg_accountDefault
    property var cfg_pollIntervalDefault
    property var cfg_fullPollIntervalDefault
    property var cfg_tunnelDeviceDefault
    property var cfg_statusCommandDefault
    property var cfg_connectCommandDefault
    property var cfg_disconnectCommandDefault
    property var cfg_openSignInPageDefault

    Kirigami.FormLayout {
        id: form

        // ── Credentials ──────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Credentials")
            Kirigami.FormData.isSection: true
        }

        QQC2.TextField {
            id: usernameField
            Kirigami.FormData.label: i18n("Username / Email:")
            placeholderText: i18n("user@example.com")
            inputMethodHints: Qt.ImhEmailCharactersOnly
        }

        QQC2.TextField {
            id: accountField
            Kirigami.FormData.label: i18n("Account name:")
            placeholderText: i18n("MyCompany")
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Both are required to connect. They are pre-filled in the popup and updated automatically from the last login.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        // ── Sign-in ──────────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Sign-in")
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: openSignInCheck
            Kirigami.FormData.label: i18n("Browser:")
            text: i18n("Open the sign-in page automatically")
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("The client cannot open a browser itself when started from the tray. When it reports a sign-in link, the applet opens that link for you; the link is also shown in the popup.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        // ── Status checks ────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Status checks")
            Kirigami.FormData.isSection: true
        }

        QQC2.TextField {
            id: tunnelDeviceField
            Kirigami.FormData.label: i18n("Tunnel device:")
            placeholderText: "tun0"
        }

        QQC2.SpinBox {
            id: pollSpin
            Kirigami.FormData.label: i18n("Check device every:")
            from: 5
            to: 3600
            stepSize: 5
            textFromValue: (value, locale) => i18np("%1 second", "%1 seconds", value)
            valueFromText: (text, locale) => parseInt(text, 10) || 0
        }

        QQC2.SpinBox {
            id: fullPollSpin
            Kirigami.FormData.label: i18n("Run status command every:")
            from: 30
            to: 86400
            stepSize: 30
            textFromValue: (value, locale) => i18np("%1 second", "%1 seconds", value)
            valueFromText: (text, locale) => parseInt(text, 10) || 0
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("The tunnel device is checked cheaply; the status command only runs when the device appears or disappears, when you open the popup, while a connection is being set up, or after this interval. Clear the device name to always run the status command instead.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        // ── Commands ─────────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.label: i18n("Commands")
            Kirigami.FormData.isSection: true
        }

        QQC2.TextField {
            id: statusCmdField
            Kirigami.FormData.label: i18n("Status command:")
            placeholderText: "cato-sdp status"
        }

        QQC2.TextField {
            id: connectCmdField
            Kirigami.FormData.label: i18n("Connect command:")
            placeholderText: "cato-sdp start --user {username} --account {account}"
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("{username} and {account} are replaced with the values above.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        QQC2.TextField {
            id: disconnectCmdField
            Kirigami.FormData.label: i18n("Disconnect command:")
            placeholderText: "cato-sdp stop"
        }
    }
}
