# CmdTabReopener

A tiny, permission-free background service for macOS that fixes an
annoying gap in `Cmd+Tab`: when you switch to an app that's still
running but has **no window on screen** (because you closed it, or
minimized it), macOS just... does nothing. You get a blank screen and
have to go click the app's icon in the Dock to actually bring it back.

**CmdTabReopener makes `Cmd+Tab` behave the way you'd expect** — selecting
an app reopens or restores its window automatically, exactly like
clicking its Dock icon would.

![Dock preview](assets/dock-preview.png)

## What it does

- You close all windows of an app (`Cmd+W`) but it's still running.
- You `Cmd+Tab` to it later.
- Its window reopens automatically. No need to touch the Dock.

It also works for:
- **Minimized windows** — `Cmd+Tab`-ing to a minimized app un-minimizes it.
- **Finder** — selecting Finder with no window open opens a new Finder window.

## What it intentionally does *not* do

If you close an app's last window and immediately `Cmd+Tab` right back
to it **without switching to any other app in between**, it will
**not** reopen. macOS still reports that app as the "active" one in
that case (no real app switch ever happens), so there's no reliable
signal to react to. Working around that turned out to require guessing
when an app is "stuck", which risks false positives — an earlier
version of this tool tried it and produced a runaway feedback loop that
made the Mac unusable. Not worth the risk for an edge case that rarely
comes up in normal use.

## How it works

macOS treats "activating" an app and "reopening" an app as two
different things:

- Clicking a Dock icon sends a **"reopen"** event → the app creates or
  shows a window.
- `Cmd+Tab` only **activates** the app → if it has no window, you just
  see a blank screen.

CmdTabReopener runs a tiny background script that listens for real app
switches (`NSWorkspaceDidActivateApplicationNotification`, the same
system notification AltTab/Contexts-style switchers use) and, on every
switch, sends that app the same `reopen` signal a Dock click would
(`open -b <bundle-id>`).

It's event-driven, not a polling loop — it reacts instantly to app
switches instead of checking on a timer.

## Requirements

- macOS (tested on recent versions of macOS 15 Sequoia)
- No third-party dependencies
- **No special permissions** — no Accessibility, no Automation, nothing
  to approve in System Settings. It only uses public, unprivileged
  APIs (`NSWorkspace` notifications and `/usr/bin/open`).

## Install

1. Download or clone this repository.
2. Double-click **`Activate.command`**.
3. Approve the Gatekeeper prompt if macOS shows one (right-click →
   Open the first time, since the files came from the internet).

That's it. A background service (a macOS LaunchAgent) is installed and
starts immediately. It also starts automatically every time you log in
— you never need to open anything again after a restart.

## Uninstall

Double-click **`Deactivate.command`**. This stops the background
service and removes every file it installed. `Cmd+Tab` goes back to
plain macOS behavior.

## Customize

Some apps you might *not* want to auto-reopen (menu-bar-only utilities,
for example). Open `Activate.command` in a text editor and add the
app's bundle ID to the `BLACKLIST` array near the top of the embedded
script, then re-run `Activate.command` to apply the change:

```js
var BLACKLIST = [
  'com.example.someMenuBarApp',
]
```

To find an app's bundle ID:

```bash
osascript -e 'id of app "App Name"'
```

## How it's installed under the hood

`Activate.command` writes a small JavaScript-for-Automation daemon to
`~/Library/Application Support/CmdTabReopener/daemon.js` and registers
it as a LaunchAgent at
`~/Library/LaunchAgents/com.cmdtabreopener.agent.plist`, so macOS keeps
it running in the background and restarts it automatically if it ever
quits. `Deactivate.command` unregisters the LaunchAgent and deletes
both.

## Why not just use a bigger tool?

Window/app switchers like [AltTab](https://alt-tab-macos.netlify.app/)
are great, but they focus on the switcher UI itself, and reopening
closed apps isn't really their job. This project does exactly one
narrow thing, with no UI, no menu-bar icon, and no permissions to
grant — you can read the entire implementation in `Activate.command`
in a couple of minutes.

## License

MIT — do whatever you want with it.
