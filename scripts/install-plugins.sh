#!/bin/sh
# install-plugins.sh -- Install plugins declared in plugins.json on container startup.
#
# Expected to run inside the barazo-api container before the main process starts.
# Reads /app/plugins.json (bind-mounted from the host) and installs each plugin
# into /app/plugins/ (a named Docker volume that persists across restarts).
#
# If plugins.json does not exist or is empty, this script exits silently.
# If a plugin is already installed at the requested version, it is skipped.

set -e

PLUGINS_FILE="/app/plugins.json"
PLUGINS_DIR="/app/plugins"

if [ ! -f "$PLUGINS_FILE" ]; then
  echo "[install-plugins] No plugins.json found, skipping plugin installation."
  exit 0
fi

PLUGIN_COUNT=$(node -e "
  const fs = require('fs');
  try {
    const data = JSON.parse(fs.readFileSync('$PLUGINS_FILE', 'utf8'));
    const plugins = data.plugins || [];
    console.log(plugins.length);
  } catch {
    console.log('0');
  }
")

if [ "$PLUGIN_COUNT" = "0" ]; then
  echo "[install-plugins] plugins.json has no plugins declared, skipping."
  exit 0
fi

echo "[install-plugins] Installing $PLUGIN_COUNT plugin(s) from plugins.json..."

# Ensure plugins directory has a package.json for npm install
if [ ! -f "$PLUGINS_DIR/package.json" ]; then
  echo '{"name":"barazo-plugins","private":true,"dependencies":{}}' > "$PLUGINS_DIR/package.json"
fi

# Parse plugins.json and install each plugin
node -e "
  const fs = require('fs');
  const { execSync } = require('child_process');
  const data = JSON.parse(fs.readFileSync('$PLUGINS_FILE', 'utf8'));
  const plugins = data.plugins || [];

  for (const plugin of plugins) {
    const spec = plugin.version ? plugin.name + '@' + plugin.version : plugin.name;
    console.log('[install-plugins] Installing ' + spec + '...');
    try {
      execSync('npm install --prefix $PLUGINS_DIR ' + spec, {
        stdio: 'inherit',
        timeout: 120000,
      });
      console.log('[install-plugins] Installed ' + spec);
    } catch (err) {
      console.error('[install-plugins] Failed to install ' + spec + ': ' + err.message);
      process.exit(1);
    }
  }
  console.log('[install-plugins] All plugins installed successfully.');
"
