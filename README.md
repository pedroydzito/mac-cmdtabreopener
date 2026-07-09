# CmdTabReopener

Reopen closed or minimized app windows via `Cmd+Tab` on macOS — no
permissions needed.

![Dock preview](assets/dock-preview.png)

## Install

Download the latest [release](https://github.com/pedroydzito/mac-cmdtabreopener/releases/latest),
unzip it, then double-click **`Activate.command`**. To remove it,
double-click **`Deactivate.command`**.

Note: it won't reopen an app if you close its last window and
immediately `Cmd+Tab` right back to it without switching to any other
app first — that's intentional (see the top of `Activate.command` for why).
