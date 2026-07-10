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
#   Also: quitting an app (Cmd+Q) does NOT trigger a reopen of whatever
#   app macOS activates next (often Finder), even if that app has no
#   window — that's the OS handing off focus automatically, not you
#   choosing to switch to it.
#
#   Only acts on apps you explicitly list in ALLOWLIST below (empty by
#   default — add bundle IDs for the apps you want this behavior for).
#   Some apps run background helpers (login items, auto-updaters) that
#   can briefly activate themselves with no window, which this daemon
#   would otherwise try to "helpfully" reopen — better to opt in per
#   app than to react to every app on the system.
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
//
// Third safety/correctness net: when you Cmd+Q an app, macOS
// automatically activates whatever app comes next (often Finder) —
// that's not a deliberate Cmd+Tab switch, just the OS handing off
// focus. We can't tell the two apart from the activation event alone,
// so we suppress reopening for a couple seconds after any app quits.
// Without this, quitting an app while Finder happened to be minimized
// would make Finder pop open right after, which is surprising and not
// something the user asked for.
//
// Important ordering detail (measured directly, not assumed): the
// "next app activated" notification fires BEFORE the "app terminated"
// notification for the app you just quit — by only a few milliseconds,
// but the wrong order all the same. Checking "did an app quit recently"
// at the moment of activation is therefore always too early: the quit
// hasn't been reported yet. To fix that, the actual reopen decision
// runs on a short delay (REOPEN_CHECK_DELAY_SECONDS) after activation,
// giving the (near-simultaneous) termination notification time to
// arrive first if this was a quit-triggered handoff.
//
// Fourth safety net, and the most important one: ALLOWLIST instead of
// blacklist. This used to react to every app on the system by default.
// Some apps (e.g. TickTick) run background helpers — login items,
// Sparkle auto-updaters, etc — with their own bundle IDs that can
// briefly self-activate with no window of their own, for reasons that
// have nothing to do with the user switching apps. Reacting to that
// caused a focus-stealing loop bouncing between that helper and
// whatever else was running. There's no permission-free way to tell
// "the user pressed Cmd+Tab" apart from "some app activated something
// programmatically" — so instead of chasing every app's internal
// quirks one at a time, this only ever acts on apps listed below.

ObjC.import('AppKit')
ObjC.import('CoreGraphics')
ObjC.import('Foundation')

// Only apps listed here get auto-reopened. Empty by default — add the
// bundle IDs of the apps you actually want this for. Find an app's
// bundle id with:
//   osascript -e 'id of app "App Name"'
var ALLOWLIST = [
  // 'com.example.someApp',
]

var MIN_SECONDS_BETWEEN_REOPENS = 1.0
var SECONDS_TO_SUPPRESS_AFTER_QUIT = 2.0
var REOPEN_CHECK_DELAY_SECONDS = 0.35

var ws = $.NSWorkspace.sharedWorkspace
var nc = ws.notificationCenter
var lastActivatedBid = ''
var lastReopenAt = 0
var lastQuitAt = 0

function isAllowed(bid) {
  return ALLOWLIST.indexOf(bid) !== -1
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
  'NSWorkspaceDidTerminateApplicationNotification', $(), $.NSOperationQueue.mainQueue,
  function (notif) {
    lastQuitAt = $.NSDate.date.timeIntervalSince1970
  }
)

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

    if (!isAllowed(bid)) return

    var pid = app.processIdentifier

    // Wait a beat before deciding: if this activation was actually
    // caused by another app quitting, its termination notification
    // will arrive within a few milliseconds — this delay gives it time
    // to land before we check lastQuitAt.
    $.NSTimer.scheduledTimerWithTimeIntervalRepeatsBlock(REOPEN_CHECK_DELAY_SECONDS, false, function () {
      var now = $.NSDate.date.timeIntervalSince1970
      if (now - lastQuitAt < SECONDS_TO_SUPPRESS_AFTER_QUIT) return // was an automatic OS handoff after quitting another app, not a deliberate switch
      if (normalWindowCount(pid) > 0) return // already has a window, nothing to do
      reopen(bid)
    })
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
echo "  ALLOWLIST is empty by default — this does nothing until you add"
echo "  bundle IDs to the ALLOWLIST array near the top of this file, then"
echo "  re-run Activate.command."
echo ""
echo "  This keeps working after restarting your Mac. To turn it off,"
echo "  double-click Deactivate.command."
echo ""
echo "  (you can close this Terminal window now)"
