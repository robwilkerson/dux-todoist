# dux-todoist

A Dux plugin that puts Todoist tasks where the user already looks, the way Apple
Reminders does: a **bar pill** with a task count that brings up the Todoist
window on click, and a **desktop widget** showing an agenda for the next N days.
One plugin, two capabilities, one shared Todoist client. It replaces Todoist's
tray icon and window-only view; it is not a Todoist client. Creating, editing,
and completing tasks hand off to the Todoist app. Issue #1 holds the scoping.

Dux is DankMaterialShell's new name. The installed shell still uses the old
names: CLI `dms`, source `/usr/share/quickshell/dms/`, plugins loaded from
`~/.config/dms/plugins/<id>`. Treat "DMS" in older docs and sibling repos as Dux.

## Stack

QML (Qt 6 / Quickshell) only. No build step, no package manager, no test
framework. Data comes from Todoist API v1 (`https://api.todoist.com/api/v1/`).
`just` runs the dev loop, mirroring `dms-protonvpn`.

## Hard Constraints

- **Plugin id is `todoist`.** Registry ids are camelCase, no hyphens. The
  installed directory name must match the id.
- **Two capabilities:** `"dankbar-widget"` and `"desktop-widget"` in
  `plugin.json`. Read `Modules/DesktopWidgetLayer.qml`,
  `Modules/Plugins/DesktopPluginComponent.qml`, and
  `DesktopWidgetSettings/PluginDesktopWidgetSettings.qml` before inventing
  desktop-widget patterns.
- **Two enables.** Placing the pill in the bar is not enough; without
  `{"todoist":{"enabled":true}}` in `plugin_settings.json` it silently never loads.
- **The API token never touches the repo.** Where it lives is undecided; compare
  gnome-keyring (`secret-tool`, needs the `process` permission) with alternatives
  before picking. Record the decision in an ADR.
- **Days ahead is a setting**, expressed as a filter query
  (`GET /tasks/filter?query=due before: +N days`), not date math in QML.
- **Clicking the pill runs `todoist`.** The app is single-instance, so a second
  launch raises the existing window. No IPC.
- **x86_64 only.** The Todoist Flatpak has no aarch64 build. Without Todoist, the
  plugin shows a clear empty state instead of erroring.
- **Icon is Todoist's own mark** (SVG in the repo), never a Material icon.
- **Size bar content with `Theme.barIconSize(...)`**, never `Theme.iconSize`.
  Colors come from `Theme.*`, no literals.
- **A settings pane declares `pluginId: "todoist"` itself.** Bar widgets get it
  injected; `PluginSettings` requires it and injects nothing.
- **Keep the agenda view ignorant of Todoist's response shapes.** A move to
  CalDAV via dcal is possible. Map API data to plain task objects at the client
  boundary, but build no provider abstraction until that move is real.

## Dev Loop

No tests. Verify in the running shell. DMS loads plugins from
`~/.config/dms/plugins/todoist`, so that path must symlink to this clone or edits
are silently ignored. `plugins reload` only cache-busts the entry file: after
editing anything it imports, or `plugin.json`, restart the shell. Trust
`journalctl --user -n 30 | grep -E 'Plugin|component error'` over
`dms ipc call plugins list`. `dms-protonvpn`'s CLAUDE.md and justfile document
these traps in depth; copy its justfile recipes rather than reinventing them.

## Related Projects

Read on-demand; never preload at session start.

- **Reference** [`dankscale`](https://github.com/AvengeMedia/dankscale) — the
  structural model for a bar pill. Consult before inventing a pattern.
- **Reference** `~/Development/lookout-software/dms-protonvpn`, `dms-caffeinate`,
  `dms-distro-menu` — sibling plugins by the same author. Justfile, README shape,
  `.gitignore`, and `.claude/` conventions follow theirs.
- **Reference** [`Zeknes/todoist-dms`](https://github.com/Zeknes/todoist-dms) —
  prior-art pill and panel. Read for API patterns only; it uses a Python helper.

## Integrations

- Repo `robwilkerson/dux-todoist` on GitHub. Issues live there; no CI, no
  automated review.
- Todoist API v1 docs: https://developer.todoist.com/api/v1/. Auth is a personal
  token from Settings → Integrations → Developer, sent as
  `Authorization: Bearer <token>`.

This file and `.claude/` are committed and shared. `SESSION_CONTEXT.md` and
`.claude/settings.local.json` stay ignored. No hostnames, tokens, or one-box paths.
