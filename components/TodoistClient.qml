// Reads open Todoist tasks due within a window of days, and completes them.
//
// The API token lives in the Secret Service (gnome-keyring, KWallet, KeePassXC)
// and is read through `secret-tool` on each refresh. It is held in memory only,
// never written to plugin settings. The task endpoints return only open tasks,
// so "incomplete only" needs no filtering here.

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

    // True from a refresh request until its fetch settles, success or not.
    property bool busy: false

    // Plain objects: { id, content, date, priority }. `date` is YYYY-MM-DD.
    property var tasks: []

    readonly property string query: "due before: +" + daysAhead + " days"
    readonly property string apiBase: "https://api.todoist.com/api/v1"

    // Set by each refresh's keyring lookup, so completing a task doesn't wait
    // on the keyring. Memory only.
    property string token: ""

    // Reports the outcome of complete(). The caller decides when the task
    // leaves the list; the client doesn't touch `tasks` here.
    signal completed(string taskId, bool ok, string errorText)

    // Coalesces bursts (a slider drag saves on every step) into one fetch.
    function refresh() {
        busy = true;
        debounce.restart();
    }

    // Closes the task in Todoist. A recurring task closes to its next
    // occurrence, which a later refresh picks up.
    function complete(taskId) {
        if (token === "") {
            completed(taskId, false, "No API token");
            return;
        }
        request("POST", apiBase + "/tasks/" + encodeURIComponent(taskId) + "/close", (status, text) => {
            const ok = status === 200 || status === 204;
            client.completed(taskId, ok, ok ? "" : status === 0 ? "Network error" : "HTTP " + status);
        });
    }

    // Drops a task locally, for after the caller is done showing it.
    function removeLocal(taskId) {
        tasks = tasks.filter(t => t.id !== taskId);
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
            client.token = exitCode === 0 ? lookupOut.text.trim() : "";
            if (client.token !== "") {
                client.fetch(client.query, null, []);
                return;
            }
            client.busy = false;
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

    function request(method, url, onDone) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE)
                onDone(xhr.status, xhr.responseText);
        };
        xhr.open(method, url);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.send();
    }

    function fetch(query, cursor, acc) {
        let url = apiBase + "/tasks/filter?limit=200&query=" + encodeURIComponent(query);
        if (cursor)
            url += "&cursor=" + encodeURIComponent(cursor);

        request("GET", url, (status, text) => {
            // A newer refresh changed the window mid-flight; drop this one.
            if (query !== client.query)
                return;
            if (status !== 200) {
                client.errorText = status === 0 ? "Network error" : "HTTP " + status;
                client.status = "error";
                client.busy = false;
                return;
            }
            let body;
            try {
                body = JSON.parse(text);
            } catch (e) {
                client.errorText = "Unreadable response from Todoist";
                client.status = "error";
                client.busy = false;
                return;
            }
            const all = acc.concat((body.results || []).map(client.toTask));
            if (body.next_cursor) {
                client.fetch(query, body.next_cursor, all);
                return;
            }
            all.sort(client.byDueThenPriority);
            client.tasks = all;
            client.status = "ready";
            client.busy = false;
        });
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
