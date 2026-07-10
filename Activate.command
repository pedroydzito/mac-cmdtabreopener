#!/bin/bash
#
# Activate.command — turns on "CmdTabReopener"
# Double-click this file. It installs a lightweight background service
# (a LaunchAgent) that keeps running even after you restart your Mac —
# no need to open anything manually after reboot.
#
# What it does:
#   When you Cmd+Tab to an app that has no window on screen (because you
#   closed all its windows a while ago, or minimized it), it reopens/
#   restores its window automatically — the same thing that happens when
#   you click its Dock icon. It also un-minimizes windows, and works for
#   Finder too.
#
#   Note: if you close an app's last window and immediately Cmd+Tab back
#   to it (macOS still shows it as the active app since no real switch
#   happened), it will NOT auto-reopen — this only triggers on an actual
#   app switch. That's intentional.
#
# Uses only public, permission-free APIs (NSWorkspace, CGWindowList,
# /usr/bin/open). No Accessibility or Automation permission required.

set -e

LABEL="com.cmdtabreopener.agent"
SUPPORT="$HOME/Library/Application Support/CmdTabReopener"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# Remove Gatekeeper quarantine flag (relevant if this came from a downloaded zip)
xattr -dr com.apple.quarantine "$SRC_DIR" 2>/dev/null || true

# Install the daemon script into a fixed location, so it keeps working
# even if you move or delete this folder later.
rm -rf "$SUPPORT"
mkdir -p "$SUPPORT"
cat > "$SUPPORT/daemon.js" <<'DAEMONEOF'
#!/usr/bin/osascript -l JavaScript
//
// CmdTabReopener daemon
// Event-driven (no polling): reacts to
// NSWorkspaceDidActivateApplicationNotification (fired on every real app
// switch — Cmd+Tab, Dock click, click on another app, etc.) and, only if
// the newly-activated app has ZERO on-screen windows (closed or
// minimized), reopens/restores it via `open -b` — the same thing that
// happens when you click its Dock icon.
//
// Two safety nets, both learned from real incidents:
//
// 1. Only acts when the target app actually has no window. Earlier
//    versions called `open -b` on every single switch, even for apps
//    that already had a window open. That's wasteful, and for apps
//    whose "reopen" handler always creates a new window regardless of
//    existing ones, it can spawn extra windows on ordinary switches.
//
// 2. A hard global cooldown: at most one `open -b` call per second,
//    full stop, no matter how many activation events arrive. If
//    anything (a system hiccup, another app, a notification storm)
//    ever causes a rapid burst of app-activation events, this cooldown
//    caps how much this daemon can possibly amplify it. A previous
//    version's watchdog (now removed) caused a runaway focus-stealing
//    loop that made the whole Mac briefly unusable; this cooldown makes
//    that class of failure structurally impossible, regardless of root
//    cause.
//
// Deliberately does NOT try to detect "app is still frontmost but lost
// its last window without a real switch happening" (e.g. closing an
// app's window and Cmd+Tabbing right back to it without touching any
// other app in between) — that requires guessing when an app is
// "stuck", which is exactly what caused the incident above.

ObjC.import('AppKit')
ObjC.import('CoreGraphics')
ObjC.import('Foundation')

// Bundle IDs to exclude entirely (menu-bar-only utilities you don't want
// auto-reopened, etc). Find an app's bundle id with:
//   osascript -e 'id of app "App Name"'
var BLACKLIST = [
  // 'com.example.someMenuBarApp',
]

var MIN_SECONDS_BETWEEN_REOPENS = 1.0

var ws = $.NSWorkspace.sharedWorkspace
var nc = ws.notificationCenter
var lastActivatedBid = ''
var lastReopenAt = 0

function isBlacklisted(bid) {
  return BLACKLIST.indexOf(bid) !== -1
}

function normalWindowCount(pid) {
  var info = $.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, $.kCGNullWindowID)
  var arr = ObjC.deepUnwrap(info)
  var count = 0
  for (var i = 0; i < arr.length; i++) {
    var w = arr[i]
    if (w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0) count++
  }
  return count
}

function reopen(bid) {
  var now = $.NSDate.date.timeIntervalSince1970
  if (now - lastReopenAt < MIN_SECONDS_BETWEEN_REOPENS) return
  lastReopenAt = now

  var t = $.NSTask.alloc.init
  t.launchPath = '/usr/bin/open'
  t.arguments = $(['-b', bid])
  t.launch
}

nc.addObserverForNameObjectQueueUsingBlock(
  'NSWorkspaceDidActivateApplicationNotification', $(), $.NSOperationQueue.mainQueue,
  function (notif) {
    var app = notif.userInfo.objectForKey('NSWorkspaceApplicationKey')
    if (app.isNil()) return
    var bidObj = app.bundleIdentifier
    if (bidObj.isNil()) return
    var bid = ObjC.unwrap(bidObj)

    if (bid === lastActivatedBid) return
    lastActivatedBid = bid

    if (isBlacklisted(bid)) return

    var pid = app.processIdentifier
    if (normalWindowCount(pid) > 0) return // already has a window, nothing to do

    reopen(bid)
  }
)

$.NSRunLoop.currentRunLoop.run()
DAEMONEOF

# Create the LaunchAgent (runs at login, restarts itself if it ever quits)
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/osascript</string>
        <string>-l</string>
        <string>JavaScript</string>
        <string>$SUPPORT/daemon.js</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo ""
echo "  CmdTabReopener: ACTIVATED"
echo "  Switching to an app via Cmd+Tab will now reopen/restore its window"
echo "  if it was closed or minimized."
echo ""
echo "  This keeps working after restarting your Mac. To turn it off,"
echo "  double-click Deactivate.command."
echo ""
echo "  (you can close this Terminal window now)"
