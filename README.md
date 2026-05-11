# Cato VPN KDE Plasma Tray Applet

A KDE Plasma 6 system tray widget that shows the state of the
[Cato Networks](https://www.catonetworks.com/) Linux client (`cato-sdp`)
and lets you connect and disconnect manually.

## Features

- Tray icon tinted by state: **green** connected, **amber** connecting or
  waiting for browser sign-in, **red** disconnected, grey while unknown
- Left-click opens a popup with account, user, PoP, tunnel IP and session
  duration, plus the raw client output on demand
- While disconnected the popup shows the connect form: user name and
  account (pre-filled from the last login and remembered), an optional
  credential reset, and a **Connect** button
- A collapsible **Client output** console in the popup shows the commands
  run and everything the client printed; it opens by itself when the client
  refuses or fails and folds away once the VPN is up
- **Disconnect** button while connected
- Browser sign-in: the client opens the SSO page itself when it can; if it
  only reports the link, the applet opens it for you (configurable). The
  link is also shown in the popup with **Open in Browser** and **Copy Link**
- If the client refuses because the user/account differ from its stored
  credentials, the applet retries once with `--reset-cred`, as the client
  suggests
- Shows a hint when `cato-sdp` reports that a newer client is available
- Cheap status polling: the tunnel device (`tun0`) is checked every few
  seconds and `cato-sdp status` only runs when something changes
- All commands are configurable (wrapper scripts, `pkexec`, …)

## Requirements

| Requirement  | Notes                                                                       |
| ------------ | --------------------------------------------------------------------------- |
| KDE Plasma 6 | Tested on Plasma 6.6 (Ubuntu 26.04). Plasma 5 is no longer supported.       |
| `cato-sdp`   | Cato Networks Linux client on `$PATH` (or an absolute path in the settings) |

## Installation

```bash
./install.sh --restart
```

`--restart` restarts the Plasma shell so the system tray loads the applet.
Without the flag, run `systemctl --user restart plasma-plasmashell.service`
yourself or log out and back in.

The applet registers itself as a system tray entry and is enabled by
default. If it does not show up: right-click the tray arrow →
**Configure System Tray…** → **Entries** → _Cato VPN Tray_ → _Always shown_.

## Configuration

Right-click the tray icon → **Configure Cato VPN Tray…**

| Setting                  | Default                                                | Description                                                                |
| ------------------------ | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| Username / Email         | _(empty)_                                              | Pre-fills the connect form; updated from the last login automatically      |
| Account name             | _(empty)_                                              | Pre-fills the connect form; updated from the last login automatically      |
| Tunnel device            | `tun0`                                                 | Device whose presence is checked cheaply. Empty: always run status command |
| Check device every       | `10` s                                                 | Interval of the cheap device check                                         |
| Run status command every | `300` s                                                | Interval of the full `cato-sdp status` run when nothing changed            |
| Status command           | `cato-sdp status`                                      | Command that reports the client state                                      |
| Connect command          | `cato-sdp start --user {username} --account {account}` | `{username}` / `{account}` are substituted with the form values            |
| Disconnect command       | `cato-sdp stop`                                        | Command that ends the session                                              |
| Open sign-in page        | on                                                     | Open the SSO link automatically when the client does not open a browser    |

Both values are required: the Connect button stays disabled until the
popup form has a user name and an account name. Whatever you enter, and
whatever `cato-sdp status` reports while connected, is stored in the applet
settings so the form is pre-filled next time.

### Why the two-tier polling?

Every `cato-sdp status` call appends roughly 2.5 KB to
`~/.cato/cato-sdp.log` and the client does not rotate that file. Polling it
every minute would add several megabytes per day. The applet therefore only
checks whether the tunnel device exists (reading `/sys/class/net`), and runs
the real status command when the device appears or disappears, when the
popup is opened, after connect/disconnect, while a sign-in is pending, or
after the configured full interval.

### Running with elevated privileges

If `cato-sdp` requires root on your system, prefix the commands with
`pkexec`:

```
pkexec cato-sdp start --user {username} --account {account}
pkexec cato-sdp stop
```

## Connecting and sign-in

Pressing **Connect** in the popup runs the connect command and logs the
command and everything the client prints to the popup's console (expand it
with _Client output_; while the popup is open the status checks are logged
there too). Cato then needs a browser sign-in:

1. If the client prints "Authentication is now in progress on your browser",
   it launched the browser itself and the applet does nothing more.
2. Otherwise the applet waits for `cato-sdp status` to report the sign-in
   link (`state = STATE_CONNECTED_UNAUTH`) and opens it with your default
   browser. Disable this in the settings if you prefer to use the **Open in
   Browser** / **Copy Link** buttons in the popup.
3. If the client answers "User/account doesn't match previous credentials",
   the applet retries once with `--reset-cred` appended.

Any other refusal printed by the client (it exits with status 0 even then)
is shown in the popup and the console expands so you can read the output.
The _Reset stored credentials_ option adds `--reset-cred` to the command up
front.

## Development

Install with `./install.sh`, then load the applet in a window with
`plasmawindowed org.kde.cato-kde-tray` to see QML warnings on stderr.
Do not set `preferredRepresentation` on the root item: the Plasma 6 system
tray never expands an applet that has one, so left-click would stop opening
the popup.

## Status detection

The status command output (ANSI colours stripped) is mapped as follows:

| Output contains                                    | State            |
| -------------------------------------------------- | ---------------- |
| `state = STATE_AUTHENTICATED`                      | Connected        |
| `state = STATE_CONNECTED_UNAUTH` or a sign-in link | Sign-in required |
| `disconnected` / `not connected`                   | Disconnected     |
| any other `state = STATE_*`                        | Connecting…      |
| non-zero exit code and nothing recognisable        | Error            |

Lines of the form `key = value` and `Account:` / `User:` / `Cato Client:`
are parsed for the details shown in the popup.

## Uninstall

```bash
kpackagetool6 --type Plasma/Applet --remove org.kde.cato-kde-tray
```

## Project layout

```
cato-kde-tray/
├── metadata.json                      # Plasma 6 applet metadata
├── install.sh                         # Install / update helper
└── contents/
    ├── config/
    │   ├── config.qml                 # Settings dialog page list
    │   └── main.xml                   # KConfig schema (persistent settings)
    └── ui/
        ├── main.qml                   # PlasmoidItem: state, polling, commands
        ├── CompactRepresentation.qml  # Tray icon
        ├── FullRepresentation.qml     # Popup: status, connect form, console
        └── ConfigGeneral.qml          # Settings page
```
