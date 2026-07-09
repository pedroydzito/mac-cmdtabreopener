#!/bin/bash
#
# Deactivate.command — turns off and fully removes CmdTabReopener.
# Double-click this file.

LABEL="com.cmdtabreopener.agent"
SUPPORT="$HOME/Library/Application Support/CmdTabReopener"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$SUPPORT"

echo ""
echo "  CmdTabReopener: DEACTIVATED"
echo "  The background service was stopped and completely removed."
echo "  Cmd+Tab is back to normal macOS behavior."
echo ""
echo "  (you can close this Terminal window now)"
