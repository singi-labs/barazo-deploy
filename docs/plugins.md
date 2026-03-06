# Plugin Installation for Self-Hosters

Barazo supports extending your forum with plugins. Plugins are npm packages installed into a persistent Docker volume.

## Quick Start

1. Copy the example plugin configuration:

   ```bash
   cp plugins.json.example plugins.json
   ```

2. Edit `plugins.json` to declare the plugins you want:

   ```json
   {
     "plugins": [
       {
         "name": "@barazo/plugin-polls",
         "version": "^1.0.0"
       }
     ]
   }
   ```

3. Restart the API container to install plugins:

   ```bash
   docker compose restart barazo-api
   ```

The `install-plugins.sh` script runs on startup. It reads `plugins.json` and installs each declared plugin into the `plugins` volume at `/app/plugins/`.

## plugins.json Format

```json
{
  "plugins": [
    {
      "name": "@barazo/plugin-polls",
      "version": "^1.0.0"
    },
    {
      "name": "community-badges",
      "version": "2.0.0"
    }
  ]
}
```

Each entry requires:

- `name` -- the npm package name (scoped or unscoped)
- `version` -- a semver range (optional; defaults to `latest`)

## How It Works

- `plugins.json` is bind-mounted read-only into the container at `/app/plugins.json`
- On startup, `install-plugins.sh` reads the file and runs `npm install` for each plugin
- Plugins are installed into the `plugins` Docker volume at `/app/plugins/`
- The volume persists across container restarts -- plugins are not reinstalled unless the version changes
- If `plugins.json` is missing or empty, no plugins are installed and the forum runs normally

## Enabling and Configuring Plugins

After installation, enable plugins through the admin UI:

1. Go to **Admin > Plugins**
2. Find the installed plugin in the **Installed** tab
3. Toggle it on
4. Configure plugin-specific settings if available

## Adding a New Plugin

1. Add the plugin to `plugins.json`
2. Restart the API: `docker compose restart barazo-api`
3. Enable it in the admin UI

## Removing a Plugin

1. Remove the plugin entry from `plugins.json`
2. Disable it in the admin UI
3. Restart the API: `docker compose restart barazo-api`

To fully remove installed files, delete the plugins volume and restart:

```bash
docker compose down
docker volume rm barazo_plugins
docker compose up -d
```

This reinstalls only the plugins declared in `plugins.json`.

## Troubleshooting

**Plugin fails to install:**

Check the API container logs:

```bash
docker compose logs barazo-api | grep install-plugins
```

Common causes:
- Invalid package name in `plugins.json`
- Network connectivity issues (the container needs access to the npm registry)
- Version not found on npm

**Plugin installed but not showing in admin:**

Ensure `PLUGINS_ENABLED=true` is set in your `.env` file (this is the default).
