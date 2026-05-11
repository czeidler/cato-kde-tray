/*
    Cato VPN Tray – Plasma 6 applet root.

    Keeps the VPN state, runs the cato-sdp commands through the
    plasma5support "executable" data engine and exposes everything the
    compact (tray icon) and full (popup) representations need.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // ── VPN state ────────────────────────────────────────────────────────────
    // One of: "unknown" | "connected" | "authenticating" | "connecting"
    //         | "disconnecting" | "disconnected" | "error"
    property string vpnStatus: "unknown"
    property string statusOutput: ""      // last status-command output, ANSI codes stripped
    property var    details: ({})         // "key = value" / "Key: value" pairs parsed from statusOutput
    property string authUrl: ""           // browser sign-in link while authenticating
    property string updateAvailable: ""   // newer client version advertised by cato-sdp, if any
    property string statusError: ""       // problem running the status command
    property string actionError: ""       // problem running the last connect/disconnect command
    property string lastUpdated: ""
    property string transcript: ""        // console log shown in the popup

    // ── Bookkeeping ──────────────────────────────────────────────────────────
    property bool   isChecking: false     // status command in flight
    property bool   actionPending: false  // connect/disconnect command in flight
    property string pendingAction: ""     // "" | "connect" | "disconnect": waiting for the daemon to settle
    property string pendingCommand: ""    // exact command string of the running action
    property string statusSource: ""      // exact command string of the running status check
    property string tunnelSource: ""      // exact command string of the running tunnel check
    property int    tunnelState: -1       // -1 unknown, 0 device absent, 1 device present
    property double lastFullCheck: 0      // Date.now() of the last completed status command
    property double authenticatingSince: 0 // Date.now() when we last entered "authenticating"
    property double trayConnectAt: 0      // Date.now() of the last Connect started from this applet
    property string lastConnectCommand: "" // connect command of the current attempt (without --reset-cred)
    property bool   retriedWithReset: false // already retried this attempt with --reset-cred
    // Argument cato-sdp asks for when the given user/account differ from its stored ones
    readonly property string resetCredentialsArgument: "--reset-cred"
    property string lastOpenedAuthUrl: "" // sign-in link we already handed to the browser
    property bool   browserHandledByClient: false // the client said it opened the browser itself

    readonly property string errorMessage: statusError !== "" ? statusError : actionError

    readonly property bool transitional: vpnStatus === "connecting"
                                      || vpnStatus === "authenticating"
                                      || vpnStatus === "disconnecting"
    // Short-lived states that are always worth re-checking quickly
    readonly property bool switching: vpnStatus === "connecting" || vpnStatus === "disconnecting"
    // Browser sign-in can take a while; re-check often for ten minutes, then slow down
    readonly property int attentionWindowMs: 10 * 60 * 1000
    readonly property bool canConnect: !actionPending
                                    && (vpnStatus === "disconnected" || vpnStatus === "unknown" || vpnStatus === "error")
    readonly property bool canDisconnect: !actionPending
                                       && (vpnStatus === "connected" || vpnStatus === "authenticating" || vpnStatus === "connecting")

    // Credentials remembered from the last login / last Connect
    readonly property string cachedUsername: String(Plasmoid.configuration.username || "").trim()
    readonly property string cachedAccount:  String(Plasmoid.configuration.account  || "").trim()
    readonly property bool   hasCredentials: cachedUsername !== "" && cachedAccount !== ""

    readonly property string statusCommand: String(Plasmoid.configuration.statusCommand).trim()
    readonly property string tunnelDevice: String(Plasmoid.configuration.tunnelDevice).trim()
    readonly property string tunnelCheckCommand: tunnelDevice !== ""
        ? "test -e /sys/class/net/" + shellQuote(tunnelDevice)
        : ""

    // ── Presentation helpers shared by both representations ──────────────────
    readonly property string iconName: "network-vpn-symbolic"

    readonly property color statusColor: {
        switch (vpnStatus) {
        case "connected":      return Kirigami.Theme.positiveTextColor
        case "authenticating":
        case "connecting":
        case "disconnecting":  return Kirigami.Theme.neutralTextColor
        case "disconnected":
        case "error":          return Kirigami.Theme.negativeTextColor
        default:               return Kirigami.Theme.disabledTextColor
        }
    }

    readonly property string statusLabel: {
        switch (vpnStatus) {
        case "connected":      return i18n("Connected")
        case "authenticating": return i18n("Sign-in required")
        case "connecting":     return i18n("Connecting…")
        case "disconnecting":  return i18n("Disconnecting…")
        case "disconnected":   return i18n("Disconnected")
        case "error":          return i18n("Error")
        default:               return i18n("Status unknown")
        }
    }

    readonly property string statusDetail: {
        if (vpnStatus === "connected") {
            const parts = []
            if (detail("pop name") !== "")  parts.push(i18n("PoP %1", detail("pop name")))
            if (detail("tunnel ip") !== "") parts.push(detail("tunnel ip"))
            return parts.join(" · ")
        }
        if (vpnStatus === "authenticating") return i18n("Finish signing in via your browser")
        if (vpnStatus === "error" && errorMessage !== "") return errorMessage
        return ""
    }

    function detail(key) {
        const d = root.details
        return (d && d[key] !== undefined) ? String(d[key]) : ""
    }

    // ── Plasmoid integration ─────────────────────────────────────────────────
    Plasmoid.icon: "network-vpn"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("Cato VPN")
    toolTipSubText: root.statusDetail !== "" ? root.statusLabel + "\n" + root.statusDetail : root.statusLabel

    // Do NOT set preferredRepresentation here: the Plasma 6 system tray refuses
    // to expand any applet that has one set (SystemTrayState.setActiveApplet),
    // so left-click would never open the popup.  Panels pick the compact
    // representation from the form factor anyway.
    compactRepresentation: CompactRepresentation { plasmoidItem: root }
    fullRepresentation: FullRepresentation { plasmoidItem: root }

    onExpandedChanged: {
        if (root.expanded) {
            root.refreshStatus()
        }
    }

    onVpnStatusChanged: {
        if (root.vpnStatus === "authenticating") {
            root.authenticatingSince = Date.now()
        }
    }

    onAuthUrlChanged: root.handleSignInLink()

    // A connection started from the tray cannot pop up a browser by itself
    // (the client only does that from an interactive terminal), so open the
    // sign-in link for it, once per link.  Otherwise make sure the link is
    // visible in the popup.
    function handleSignInLink() {
        if (root.authUrl === "" || root.authUrl === root.lastOpenedAuthUrl) {
            return
        }
        const startedHere = (Date.now() - root.trayConnectAt) < 5 * 60 * 1000
        if (!startedHere) {
            return   // started from a terminal: the client handles the browser itself
        }
        root.lastOpenedAuthUrl = root.authUrl
        if (root.browserHandledByClient) {
            // cato-sdp launched the browser itself; don't open a second tab.
            root.browserHandledByClient = false
            return
        }
        if (Plasmoid.configuration.openSignInPage) {
            Qt.openUrlExternally(root.authUrl)
        } else {
            root.expanded = true
        }
    }

    // Extract the sign-in link from client output.  The link runs to the end
    // of its line and may contain spaces in its last query parameter.
    function extractSignInUrl(text) {
        const m = String(text).match(/https?:\/\/[^\n\r]*/)
        return m ? m[0].trim().replace(/ /g, "%20") : ""
    }

    // ── Command runner ───────────────────────────────────────────────────────
    P5Support.DataSource {
        id: cmdSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            const stdout   = String(data["stdout"]  || "")
            const stderr   = String(data["stderr"]  || "")
            const exitCode = Number(data["exit code"] || 0)
            // Disconnect first so the same command can be re-run later
            cmdSource.disconnectSource(sourceName)
            root.handleCommandOutput(sourceName, stdout, stderr, exitCode)
        }
    }

    // ── Timers ───────────────────────────────────────────────────────────────
    // Cheap check: does the tunnel device exist?  Drives everything else.
    Timer {
        id: quickTimer
        interval: Math.max(5, Plasmoid.configuration.pollInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.quickCheck()
    }

    // While a connect/disconnect is settling, ask the client more often.
    Timer {
        id: settleTimer
        interval: 4000
        repeat: true
        running: root.switching || root.pendingAction !== ""
        onTriggered: root.refreshStatus()
    }

    // Re-check shortly after a connect/disconnect command returned.
    Timer {
        id: refreshTimer
        interval: 2500
        onTriggered: root.refreshStatus()
    }

    // Stop waiting for the daemon to reach the requested state.
    Timer {
        id: pendingActionTimer
        interval: 45000
        onTriggered: {
            if (root.pendingAction === "connect"
                    && root.vpnStatus !== "connected" && root.vpnStatus !== "authenticating") {
                root.actionError = i18n("The client did not report a connection within 45 seconds.")
                noteTranscript(root.actionError)
            }
            root.pendingAction = ""
        }
    }

    // A hung status command must not block polling forever.
    Timer {
        id: statusWatchdog
        interval: 30000
        onTriggered: {
            if (root.statusSource !== "") {
                cmdSource.disconnectSource(root.statusSource)
            }
            root.statusSource = ""
            root.isChecking = false
        }
    }

    // A connect command may sit waiting for browser sign-in; release the UI
    // after a while and let the status polling tell the real story.
    Timer {
        id: actionWatchdog
        interval: 90000
        onTriggered: {
            if (root.pendingCommand !== "") {
                cmdSource.disconnectSource(root.pendingCommand)
            }
            root.pendingCommand = ""
            root.actionPending = false
            root.refreshStatus()
        }
    }

    // ── Polling logic ────────────────────────────────────────────────────────
    function quickCheck() {
        if (root.tunnelCheckCommand === "") {
            // No device configured: fall back to running the status command
            root.refreshStatus()
            return
        }
        if (root.tunnelSource !== "") {
            return   // previous check still running
        }
        root.tunnelSource = root.tunnelCheckCommand
        cmdSource.connectSource(root.tunnelSource)
    }

    function refreshStatus() {
        if (root.isChecking || root.statusCommand === "") {
            return
        }
        root.isChecking = true
        root.statusSource = root.statusCommand
        statusWatchdog.restart()
        cmdSource.connectSource(root.statusSource)
    }

    function handleCommandOutput(source, stdout, stderr, exitCode) {
        if (source === root.tunnelSource) {
            root.tunnelSource = ""
            handleTunnelCheck(exitCode === 0)
        } else if (source === root.statusSource) {
            root.statusSource = ""
            if (root.expanded) {
                appendTranscript(source, stdout, stderr, exitCode)
            }
            handleStatusOutput(stdout, stderr, exitCode)
        } else if (source === root.pendingCommand) {
            appendTranscript(source, stdout, stderr, exitCode)
            handleActionFinished(stdout, stderr, exitCode)
        }
        // Anything else belongs to a command we stopped tracking; ignore it.
    }

    function handleTunnelCheck(devicePresent) {
        const previous = root.tunnelState
        root.tunnelState = devicePresent ? 1 : 0

        const now = Date.now()
        const changed = previous !== root.tunnelState
        const fullInterval = Math.max(30, Plasmoid.configuration.fullPollInterval) * 1000
        const stale = (now - root.lastFullCheck) > fullInterval
        const awaitingSignIn = root.vpnStatus === "authenticating"
                            && (now - root.authenticatingSince) < root.attentionWindowMs

        if (changed || stale || awaitingSignIn || root.switching || root.pendingAction !== "") {
            root.refreshStatus()
        }
    }

    function handleStatusOutput(stdout, stderr, exitCode) {
        statusWatchdog.stop()
        root.isChecking = false
        root.lastFullCheck = Date.now()
        root.lastUpdated = Qt.formatTime(new Date(), "hh:mm:ss")

        const out = stripAnsi(stdout).trim()
        const err = stripAnsi(stderr).trim()
        root.statusOutput = out !== "" ? out : err
        root.details = parseDetails(root.statusOutput)

        const update = root.statusOutput.match(/new client version is available \[([^\]]+)\]/i)
        root.updateAvailable = update ? update[1] : ""

        const parsed = parseStatus(root.statusOutput, exitCode)

        if (parsed === "error") {
            root.statusError = err !== "" ? err
                             : (out !== "" ? out : i18n("Status command failed (exit code %1)", exitCode))
        } else {
            root.statusError = ""
        }

        root.authUrl = parsed === "authenticating" ? extractSignInUrl(root.statusOutput) : ""

        if (parsed === "connected") {
            rememberCredentials(detail("user"), detail("account"))
        }

        applyStatus(parsed)
    }

    // Persist the user name / account so the connect form is pre-filled next time.
    function rememberCredentials(username, account) {
        const u = String(username || "").trim()
        const a = String(account  || "").trim()
        if (u !== "" && u !== root.cachedUsername) {
            Plasmoid.configuration.username = u
        }
        if (a !== "" && a !== root.cachedAccount) {
            Plasmoid.configuration.account = a
        }
    }

    // Apply a freshly parsed state, but while a connect/disconnect is still
    // settling only accept states that confirm the requested direction.
    function applyStatus(parsed) {
        if (root.pendingAction === "connect") {
            if (parsed === "connected") {
                root.vpnStatus = parsed
                actionSettled()
            } else if (parsed === "authenticating") {
                root.vpnStatus = parsed
            }
            return
        }
        if (root.pendingAction === "disconnect") {
            if (parsed === "disconnected") {
                root.vpnStatus = parsed
                actionSettled()
            }
            return
        }
        root.vpnStatus = parsed
    }

    function actionSettled() {
        root.pendingAction = ""
        root.actionError = ""
        pendingActionTimer.stop()
    }

    // ── Connect / disconnect ─────────────────────────────────────────────────
    function connectVPN(username, account, resetCredentials) {
        if (root.actionPending) {
            return
        }
        const u = String(username || "").trim()
        const a = String(account  || "").trim()
        if (u === "" || a === "") {
            root.expanded = true     // the popup has the form
            return
        }
        rememberCredentials(u, a)
        let cmd = String(Plasmoid.configuration.connectCommand)
        cmd = fillPlaceholder(cmd, "username", u)
        cmd = fillPlaceholder(cmd, "account",  a)
        root.lastConnectCommand = cmd.trim()
        // A forced reset counts as the retry, so a refusal afterwards is final
        root.retriedWithReset = !!resetCredentials
        runAction(resetCredentials ? root.lastConnectCommand + " " + root.resetCredentialsArgument
                                   : root.lastConnectCommand,
                  "connect", "connecting")
    }

    function disconnectVPN() {
        if (root.actionPending) {
            return
        }
        runAction(String(Plasmoid.configuration.disconnectCommand).trim(), "disconnect", "disconnecting")
    }

    function runAction(cmd, action, transientStatus) {
        if (cmd === "") {
            root.actionError = i18n("No command configured")
            return
        }
        root.actionError = ""
        root.authUrl = ""
        root.actionPending = true
        root.pendingAction = action
        if (action === "connect") {
            root.trayConnectAt = Date.now()
            root.browserHandledByClient = false
        }
        root.pendingCommand = cmd
        root.vpnStatus = transientStatus
        pendingActionTimer.restart()
        actionWatchdog.restart()
        cmdSource.connectSource(cmd)
    }

    function handleActionFinished(stdout, stderr, exitCode) {
        actionWatchdog.stop()
        root.actionPending = false
        root.pendingCommand = ""

        const out = stripAnsi(stdout).trim()
        const err = stripAnsi(stderr).trim()
        const combined = (out + "\n" + err).toLowerCase()

        // cato-sdp exits 0 even when it refuses to connect, so look for the
        // messages it prints in that case.
        const failureLine = root.pendingAction === "connect" ? findFailureLine(out + "\n" + err) : ""

        // The client refuses to connect when its stored credentials differ from
        // the ones given and asks for --reset-cred; do that once automatically.
        if (failureLine.toLowerCase().indexOf(root.resetCredentialsArgument) !== -1
                && root.lastConnectCommand !== "" && !root.retriedWithReset) {
            root.retriedWithReset = true
            noteTranscript(i18n("Stored credentials differ from the ones given; retrying with %1", root.resetCredentialsArgument))
            runAction(root.lastConnectCommand + " " + root.resetCredentialsArgument, "connect", "connecting")
            return
        }

        if (exitCode !== 0 || failureLine !== "") {
            root.actionError = failureLine !== "" ? failureLine
                             : (err !== "" ? err : (out !== "" ? out : i18n("Command failed (exit code %1)", exitCode)))
            root.pendingAction = ""
            pendingActionTimer.stop()
            root.vpnStatus = "unknown"   // the next status check decides
            root.expanded = true         // the popup shows the message and console
        } else if (root.pendingAction === "connect") {
            // "…in progress on your browser, please check…" means the client
            // ran xdg-open itself; "…please open in your browser link: …" means
            // it left that to us.
            root.browserHandledByClient = combined.indexOf("on your browser") !== -1
                                       && combined.indexOf("error opening browser") === -1
            const url = extractSignInUrl(out)
            if (combined.indexOf("authentication is now in progress") !== -1) {
                root.vpnStatus = "authenticating"
                if (url !== "") {
                    root.authUrl = url
                }
            }
        }
        refreshTimer.restart()
    }

    // ── Console transcript for the popup ─────────────────────────────────────
    function appendTranscript(command, stdout, stderr, exitCode) {
        let chunk = "[" + Qt.formatTime(new Date(), "hh:mm:ss") + "] $ " + command + "\n"
        const out = stripAnsi(stdout).trim()
        const err = stripAnsi(stderr).trim()
        if (out !== "") {
            chunk += out + "\n"
        }
        if (err !== "") {
            chunk += err + "\n"
        }
        if (exitCode !== 0) {
            chunk += "[exit code " + exitCode + "]\n"
        }
        pushTranscript(chunk)
    }

    function noteTranscript(message) {
        pushTranscript("[" + Qt.formatTime(new Date(), "hh:mm:ss") + "] # " + message + "\n")
    }

    function pushTranscript(chunk) {
        const lines = (root.transcript + chunk + "\n").split("\n")
        const maxLines = 400
        root.transcript = lines.slice(Math.max(0, lines.length - maxLines)).join("\n")
    }

    // ── Parsing helpers ──────────────────────────────────────────────────────
    // First line of connect output that reads like a refusal, or "".
    function findFailureLine(text) {
        const markers = ["disconnected", "failed", "doesn't match", "does not match",
                         "please fix", "error", "a browser is needed", "not running",
                         "try again"]
        const lines = String(text).split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim()
            const lc = line.toLowerCase()
            if (line === "" || lc.indexOf("new client version") !== -1) {
                continue
            }
            for (let j = 0; j < markers.length; ++j) {
                if (lc.indexOf(markers[j]) !== -1) {
                    return line
                }
            }
        }
        return ""
    }

    function stripAnsi(s) {
        return String(s).replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "")
    }

    // Shell-safe single quoting
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // Replace {key} in a command template.  An empty value removes the
    // placeholder together with the option introducing it ("--user {username}").
    function fillPlaceholder(template, key, value) {
        const trimmed = value.trim()
        if (trimmed === "") {
            return template.replace(new RegExp("\\s*(--?[\\w-]+(=|\\s+))?\\{" + key + "\\}", "g"), "")
        }
        return template.split("{" + key + "}").join(shellQuote(trimmed))
    }

    // Map the cato-sdp status output to one of our states.
    //   connected        – "state = STATE_AUTHENTICATED"
    //   authenticating   – "state = STATE_CONNECTED_UNAUTH" / sign-in link printed
    //   disconnected     – "Cato client is disconnected" (or any "disconnected"/"not connected")
    //   connecting       – any other STATE_* reported by the daemon
    //   error            – command failed and printed nothing recognisable
    function parseStatus(text, exitCode) {
        const lc = text.toLowerCase()
        const stateMatch = lc.match(/state\s*=\s*(state_[a-z0-9_]+)/)
        const state = stateMatch ? stateMatch[1] : ""

        if (state === "state_authenticated") {
            return "connected"
        }
        if (state === "state_connected_unauth" || lc.indexOf("authentication is now in progress") !== -1) {
            return "authenticating"
        }
        if (lc.indexOf("disconnected") !== -1 || lc.indexOf("not connected") !== -1) {
            return "disconnected"
        }
        if (state !== "") {
            return "connecting"
        }
        if (exitCode !== 0) {
            return "error"
        }
        if (/\btunnel ip\s*=/.test(lc)) {
            return "connected"
        }
        return "unknown"
    }

    // Collect "key = value" and "Key: value" lines (keys lower-cased).
    function parseDetails(text) {
        const result = {}
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            let m = line.match(/^\s*([A-Za-z][A-Za-z0-9 _-]*?)\s*=\s*(.+?)\s*$/)
            if (!m) {
                m = line.match(/^\s*(Account|User|Cato Client)\s*:\s*(.+?)\s*$/i)
            }
            if (m) {
                result[m[1].trim().toLowerCase()] = m[2].replace(/^"(.*)"$/, "$1")
            }
        }
        return result
    }
}
