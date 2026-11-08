# Todoist — Command Runner
# Run `just` or `just --list` to see available commands.
#
# There is no build step: Dux loads the QML directly from disk. These recipes
# point the running bar at this working tree and reload it. The `dms` recipes
# must run in your Wayland session, not a detached shell or agent sandbox.

# Must match plugin.json's id exactly. It is also the directory name Dux looks
# for under plugins/.
PLUGIN_ID := "todoist"

# Show available commands
default:
    @just --list --unsorted

# Point the bar at this tree (start) or install its committed HEAD (stop)
[group('Dev')]
develop action="start":
    #!/usr/bin/env bash
    set -euo pipefail
    PLUGINS="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins"
    TARGET="$PLUGINS/{{ PLUGIN_ID }}"
    # Stashed outside the config tree, which is often a symlink into a dotfiles
    # repo; stashing beside it would show up in that repo's status.
    BACKUP="${XDG_CACHE_HOME:-$HOME/.cache}/dms-plugin-backup/{{ PLUGIN_ID }}"
    REPO="$(git rev-parse --show-toplevel)"

    case "{{ action }}" in
      start)
        if [ -L "$TARGET" ] && [ "$(readlink -f "$TARGET")" = "$REPO" ]; then
            echo "✅ Already developing: $TARGET -> $REPO"
            exit 0
        fi

        mkdir -p "$PLUGINS"
        if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
            # A real directory means the bar runs an installed copy and ignores
            # this tree. Move it, never delete it: it may hold changes this
            # tree does not.
            if [ -e "$BACKUP" ]; then
                echo "❌ Refusing to overwrite an existing backup at:" >&2
                echo "   $BACKUP" >&2
                exit 1
            fi
            mkdir -p "$(dirname "$BACKUP")"
            mv "$TARGET" "$BACKUP"
            echo "📦 Moved installed copy aside: $BACKUP"
        elif [ -L "$TARGET" ]; then
            rm "$TARGET"
        fi

        ln -s "$REPO" "$TARGET"
        echo "🔗 $TARGET -> $REPO"
        ;;

      stop)
        if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
            echo "❌ $TARGET is a real directory, not a dev symlink. Resolve by hand." >&2
            exit 1
        fi
        # Installs what's committed, so uncommitted work would be left out.
        if [ -n "$(git status --porcelain)" ]; then
            echo "❌ Uncommitted changes in $REPO. Commit or stash, then re-run." >&2
            exit 1
        fi
        rm -f "$TARGET"
        mkdir -p "$TARGET"
        git archive HEAD | tar -x -C "$TARGET"
        echo "📦 Installed $(git rev-parse --short HEAD) to $TARGET"
        if [ -e "$BACKUP" ]; then
            rm -rf "$BACKUP"
            echo "🗑️  Discarded the copy start moved aside: $BACKUP"
        fi
        ;;

      *)
        echo "❌ Unknown action '{{ action }}'. Expected 'start' or 'stop'." >&2
        exit 1
        ;;
    esac

    echo ""
    echo "⚠️  The plugin's source path changed, so a hot reload is not enough."
    echo "    Run: just restart"

# Show whether the bar is running this tree or an installed copy
[group('Dev')]
status:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins/{{ PLUGIN_ID }}"
    REPO="$(git rev-parse --show-toplevel)"

    if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
        echo "⚪ Not installed: $TARGET does not exist"
    elif [ -L "$TARGET" ]; then
        RESOLVED="$(readlink -f "$TARGET")"
        if [ "$RESOLVED" = "$REPO" ]; then
            echo "✅ Developing this tree: $TARGET -> $RESOLVED"
        else
            echo "⚠️  Symlinked elsewhere: $TARGET -> $RESOLVED"
        fi
    else
        echo "⚠️  Installed copy (a real directory): $TARGET"
        echo "    Edits in this tree will NOT load. Run: just develop start"
    fi

# Hot-reload the entry QML (does not re-read plugin.json or imported files)
[group('Dev')]
reload:
    dms ipc call plugins reload {{ PLUGIN_ID }}

# Full restart; required after plugin.json or component changes, or a develop swap
[group('Dev')]
restart:
    dms restart

# Show recent plugin load events and component errors
[group('Dev')]
logs:
    journalctl --user -n 50 --no-pager | grep -E 'Plugin|component error|todoist' || true
