#!/bin/bash
set -e

echo ""
echo "  Друкар (Drukar) — Installer"
echo "  ─────────────────────────────"
echo ""

APP_NAME="Drukar.app"
INPUT_METHODS_DIR="$HOME/Library/Input Methods"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$SCRIPT_DIR/$APP_NAME" ]; then
    APP_SOURCE="$SCRIPT_DIR/$APP_NAME"
elif [ -d "./$APP_NAME" ]; then
    APP_SOURCE="./$APP_NAME"
else
    echo "  Error: $APP_NAME not found in current directory."
    echo "  Make sure Drukar.app is in the same folder as this script."
    exit 1
fi

killall Drukar 2>/dev/null || true
sleep 1

mkdir -p "$INPUT_METHODS_DIR"
rm -rf "$INPUT_METHODS_DIR/$APP_NAME"
cp -R "$APP_SOURCE" "$INPUT_METHODS_DIR/"

echo "  Installed to: $INPUT_METHODS_DIR/$APP_NAME"
echo ""
echo "  Next steps:"
echo "  1. Open System Settings → Keyboard → Input Sources → Edit"
echo "  2. Click '+' and find 'Drukar'"
echo "  3. Add it and select as your input source"
echo ""
echo "  If Drukar doesn't appear, log out and back in."
echo ""
echo "  Done!"
