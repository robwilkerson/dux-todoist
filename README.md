# Todoist

A [Dux](https://github.com/AvengeMedia/DankMaterialShell) (formerly
DankMaterialShell) bar widget for [Todoist](https://todoist.com). Puts your
overdue and upcoming tasks one click away, without Todoist's tray icon or a
window to open.

Scope is deliberately narrow: **see what's due, and check it off**. Creating
and editing tasks stay in Todoist's own app, one click away from the popout.

## Prerequisites

- **Dux (DankMaterialShell) `>= 2.0.0`**: the shell that loads this plugin.
- **`secret-tool`** (libsecret) and a running **Secret Service** keyring:
  gnome-keyring, KDE Wallet, or KeePassXC all work. Your API token is stored
  there. On Fedora, `secret-tool` comes from `libsecret`; on Debian and Ubuntu,
  from `libsecret-tools`.
- **The Todoist app** (optional, x86_64 only): the
  [Flathub build](https://flathub.org/apps/com.todoist.Todoist) or any install
  with a desktop entry. Used only for "Open Todoist". Without it, the bar mark
  turns your theme's error color and the popout says Todoist wasn't found.

## Bar

The Todoist mark, themed to match the bar's other icons. Click opens the
popout.

## Popout

- **Overdue**: open tasks due before today, or earlier today at a time that has
  passed. Shown only when there are some.
- **Today** and **Tomorrow**: each task shows its time, if it has one. An empty
  Today says so.
- **This Week**, **Next Week**, and **Later**: each task shows its date. Weeks
  are calendar weeks, starting on the day set in Todoist's "Start of week".
- Each group appears only when the number of days you've set reaches it, and
  keeps its header even when empty.
- **Recurring tasks** carry a two-arrow icon. Todoist only tracks a recurring
  task's next occurrence, so it appears once.
- **Complete a task**: click its circle. It stays struck through until Todoist
  confirms, then disappears. Recurring tasks move to their next occurrence. If
  Todoist can't be reached, a notification says so and the task stays.
- **Refresh**: reloads from Todoist. The list also refreshes every time the
  popout opens. While it's open, tasks move between groups as the clock passes
  their due time, without reloading.
- **Open Todoist**: brings up the app for anything the popout doesn't do.

## Settings

- **Days to Show**: 1 (today only) through 14. Overdue tasks always show.
- **API Token**: copy it from Todoist under Settings → Integrations → Developer,
  paste it in, and click Save. It goes straight to your keyring, never to Dux's
  settings files, which are often tracked in a dotfiles repo. The pane shows
  whether a token is saved but never displays it.

## Install

Dux loads plugins from `~/.config/dms/plugins/`. Either clone this repo
directly into that directory:

```sh
git clone git@github.com:robwilkerson/dux-todoist.git \
  ~/.config/dms/plugins/todoist
```

or clone it anywhere and symlink it in:

```sh
git clone git@github.com:robwilkerson/dux-todoist.git
ln -s "$(pwd)/dux-todoist" ~/.config/dms/plugins/todoist
```

The directory name must match the plugin id, `todoist`. Then:

1. Enable it in Settings → Plugin Management. Adding it to a bar alone isn't
   enough; a plugin that isn't enabled never loads, and nothing says so.
2. Add it to a bar section.
3. Open its settings and save your API token.

## Uninstall

Remove it from the bar in Settings → Plugin Management, delete the plugin
directory, and clear the token from your keyring:

```sh
rm -rf ~/.config/dms/plugins/todoist
secret-tool clear application dux-todoist
```

## Notes

- Tasks come from Todoist's API v1 using its filter query
  `due before: +N days`, which includes overdue tasks.
- After editing a file the plugin *imports* (anything in `components/`), a
  plugin reload isn't enough, because Dux only cache-busts the entry file.
  Restart the shell with `dms restart`, or `just restart` from this repo.

## About the Robot

Yes, an LLM helped write this. So did an editor, a compiler, a linter,
autocomplete, and a number of other tools. It's just a tool. One that "talks"
back, but still a tool. And it helps me salvage some of my weekend. It types
faster than I do, reads faster than I do, and, much to my chagrin, knows more
than I do.

Every line here was read, discussed, sometimes argued, and ultimately signed
off by a human (me). I run this on my own bar all day and live with the result.

The AI doesn't get the credit and it doesn't get the blame. If something here
is broken, sloppy, or wrong, that's 100% on me and I welcome the feedback. A
bug report or a PR is always appreciated.

## License

MIT. See [LICENSE](./LICENSE).
