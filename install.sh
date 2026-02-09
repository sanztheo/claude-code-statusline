#!/bin/bash

# Claude Code Statusline Installer
# https://github.com/sanztheo/claude-code-statusline

set -e

INSTALL_DIR="$HOME/.claude/utils/claude_monitor_statusline"
SETTINGS_FILE="$HOME/.claude/settings.json"
REPO_URL="https://github.com/sanztheo/claude-code-statusline.git"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Code Statusline Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check Ruby
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby is required but not installed."
    echo "   Install it with: brew install ruby"
    exit 1
fi
echo "✓ Ruby found: $(ruby --version | head -1)"

# Create directory
echo ""
echo "→ Installing to $INSTALL_DIR..."
mkdir -p "$(dirname "$INSTALL_DIR")"

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "→ Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull --quiet
else
    echo "→ Cloning repository..."
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

# Make executable
chmod +x "$INSTALL_DIR/statusline.rb"
chmod +x "$INSTALL_DIR/barstatus_ui.rb"
echo "✓ Scripts installed"

# Install bar-status CLI command
echo ""
echo "→ Installing bar-status command..."
BIN_DIR=""
for dir in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
    if [ -d "$dir" ] && echo "$PATH" | grep -q "$dir"; then
        BIN_DIR="$dir"
        break
    fi
done

if [ -z "$BIN_DIR" ]; then
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    echo "  Created $BIN_DIR (add it to your PATH if needed)"
fi

cat > "$BIN_DIR/bar-status" << 'WRAPPER'
#!/usr/bin/env bash
exec ruby "$HOME/.claude/utils/claude_monitor_statusline/barstatus_ui.rb" "$@"
WRAPPER
chmod +x "$BIN_DIR/bar-status"
echo "✓ bar-status command installed to $BIN_DIR/bar-status"

# Configure settings.json
echo ""
echo "→ Configuring Claude Code..."

if [ -f "$SETTINGS_FILE" ]; then
    # Check if statusLine already configured
    if grep -q '"statusLine"' "$SETTINGS_FILE"; then
        echo "⚠ statusLine already configured in settings.json"
        echo "  You may need to update it manually."
    else
        # Add statusLine to existing settings
        # Using Ruby since it's available
        ruby -rjson -e '
            settings = JSON.parse(File.read(ARGV[0]))
            settings["statusLine"] = {
                "type" => "command",
                "command" => "CLAUDE_STATUS_DISPLAY_MODE=minimal CLAUDE_STATUS_INFO_MODE=text CLAUDE_STATUS_PLAN=max5 " + ARGV[1] + "/statusline.rb",
                "padding" => 0
            }
            File.write(ARGV[0], JSON.pretty_generate(settings))
        ' "$SETTINGS_FILE" "$INSTALL_DIR"
        echo "✓ settings.json updated"
    fi
else
    # Create new settings.json
    cat > "$SETTINGS_FILE" << EOF
{
  "statusLine": {
    "type": "command",
    "command": "CLAUDE_STATUS_DISPLAY_MODE=minimal CLAUDE_STATUS_INFO_MODE=text CLAUDE_STATUS_PLAN=max5 $INSTALL_DIR/statusline.rb",
    "padding": 0
  }
}
EOF
    echo "✓ settings.json created"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Restart Claude Code to see your new statusline."
echo ""
echo "  Configuration:"
echo "    bar-status                  Open interactive config menu"
echo "    CLAUDE_STATUS_PLAN=max5|max20|pro"
echo "    CLAUDE_STATUS_DISPLAY_MODE=minimal|colors|background"
echo ""
