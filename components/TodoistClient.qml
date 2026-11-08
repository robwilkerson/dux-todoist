// Reads open Todoist tasks due within a window of days.
//
// The API token lives in the Secret Service (gnome-keyring, KWallet, KeePassXC)
// and is read through `secret-tool` on each refresh, so it is never written to
// plugin settings or held anywhere but memory. The task endpoints return only
// open tasks, so "incomplete only" needs no filtering here.

import QtQuick
import Quickshell.Io

Item {
    id: client

    // Days to show, counting today. 1 means today only. Overdue tasks are
    // always included, since `due before:` matches every earlier date.
    property int daysAhead: 1

    // "idle" | "loading" | "ready" | "noToken" | "noKeyring" | "error"
    property string status: "idle"
    property string errorText: ""

    // Plain objects: { id, content, date, priority }. `date` is YYYY-MM-DD.
    property var tasks: []

    readonly property string query: "due before: +" + daysAhead + " days"

    // Coalesces bursts (a slider drag saves on every step) into one fetch.
    function refresh() {
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: {
            if (lookup.running) {
                debounce.restart();
                return;
            }
            if (client.status !== "ready")
                client.status = "loading";
            lookup.running = true;
        }
    }

    Process {
        id: lookup
        command: ["secret-tool", "lookup", "application", "dux-todoist"]

        stdout: StdioCollector {
            id: lookupOut
        }
        stderr: StdioCollector {
            id: lookupErr
        }

        onExited: exitCode => {
            const token = lookupOut.text.trim();
            if (exitCode === 0 && token !== "") {
                client.fetch(token, client.query, null, []);
                return;
            }
            // No match exits non-zero with nothing on stderr. Anything on
            // stderr means the Secret Service itself could not be reached.
            const err = lookupErr.text.trim();
            if (err !== "") {
                client.errorText = err;
                client.status = "noKeyring";
            } else {
                client.status = "noToken";
            }
        }
    }

    function fetch(token, query, cursor, acc) {
        let url = "https://api.todoist.com/api/v1/tasks/filter?limit=200&query=" + encodeURIComponent(query);
        if (cursor)
            url += "&cursor=" + encodeURIComponent(cursor);

        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            // A newer refresh changed the window mid-flight; drop this one.
            if (query !== client.query)
                return;
            if (xhr.status !== 200) {
                client.errorText = xhr.status === 0 ? "Network error" : "HTTP " + xhr.status;
                client.status = "error";
                return;
            }
            let body;
            try {
                body = JSON.parse(xhr.responseText);
            } catch (e) {
                client.errorText = "Unreadable response from Todoist";
                client.status = "error";
                return;
            }
            const all = acc.concat((body.results || []).map(client.toTask));
            if (body.next_cursor) {
                client.fetch(token, query, body.next_cursor, all);
                return;
            }
            all.sort(client.byDueThenPriority);
            client.tasks = all;
            client.status = "ready";
        };
        xhr.open("GET", url);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.send();
    }

    function toTask(t) {
        return {
            id: t.id,
            content: t.content,
            date: (t.due?.date || "").slice(0, 10),
            priority: t.priority || 1
        };
    }

    // Earliest date first; within a day, Todoist's priority 4 (urgent) first.
    function byDueThenPriority(a, b) {
        if (a.date !== b.date)
            return a.date < b.date ? -1 : 1;
        return b.priority - a.priority;
    }
}
