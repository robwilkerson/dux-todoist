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

    // "idle" | "loading" | "ready" | "noToken" | "noKeyring" | "noSecretTool" | "error"
    property string status: "idle"
    property string errorText: ""

    // True from a refresh request until its fetch settles, success or not.
    property bool busy: false

    // Plain objects: { id, content, date, time, recurring, priority }. `date`
    // is local YYYY-MM-DD; `time` is local HH:mm, or "" for an all-day task.
    property var tasks: []

    // Todoist's "Start of week" as a JS getDay() number (0 = Sunday), or -1
    // until read. Read once per shell session.
    property int weekStart: -1

    readonly property string query: "due before: +" + daysAhead + " days"
    readonly property string apiBase: "https://api.todoist.com/api/v1"

    // Set by each refresh's keyring lookup, so completing a task doesn't wait
    // on the keyring. Memory only.
    property string token: ""

    // Reports the outcome of complete(). The caller decides when the task
    // leaves the list; the client doesn't touch `tasks` here.
    signal completed(string taskId, bool ok, string errorText)

    // Bumped by every refresh request. A response only applies while its
    // generation is still current, so a slow older one can't land last.
    property int generation: 0

    // Coalesces bursts (a slider drag saves on every step) into one fetch.
    function refresh() {
        generation++;
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

    SecretTool {
        id: lookup
        command: ["secret-tool", "lookup", "application", "dux-todoist"]

        stdout: StdioCollector {
            id: lookupOut
        }
        stderr: StdioCollector {
            id: lookupErr
        }

        // A refresh requested mid-lookup runs its own lookup next, so this
        // one's outcome is already stale.
        onNotFound: {
            if (debounce.running)
                return;
            client.busy = false;
            client.errorText = lookup.installHint;
            client.status = "noSecretTool";
        }

        onExited: exitCode => {
            if (debounce.running)
                return;
            client.token = exitCode === 0 ? lookupOut.text.trim() : "";
            if (client.token !== "") {
                if (client.weekStart < 0)
                    client.fetchWeekStart();
                client.fetch(client.generation, null, []);
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

    function fetch(gen, cursor, acc) {
        let url = apiBase + "/tasks/filter?limit=200&query=" + encodeURIComponent(client.query);
        if (cursor)
            url += "&cursor=" + encodeURIComponent(cursor);

        request("GET", url, (status, text) => {
            // A newer refresh owns the list, the status, and busy now.
            if (gen !== client.generation)
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
                client.fetch(gen, body.next_cursor, all);
                return;
            }
            all.sort(client.byDueThenPriority);
            client.tasks = all;
            client.status = "ready";
            client.busy = false;
        });
    }

    // A failure leaves weekStart at -1, so the caller uses the locale's first
    // day and the next refresh tries again, unless a request is still out.
    property bool weekStartPending: false

    function fetchWeekStart() {
        if (weekStartPending)
            return;
        weekStartPending = true;
        request("GET", apiBase + "/user", (status, text) => {
            client.weekStartPending = false;
            let day = 0;
            if (status === 200) {
                try {
                    day = JSON.parse(text).start_day;
                } catch (e) {}
            }
            // Todoist counts 1 = Monday through 7 = Sunday.
            if (day >= 1 && day <= 7)
                client.weekStart = day % 7;
            else
                console.warn("todoist: couldn't read Start of week (HTTP " + status + "); using the locale's first day");
        });
    }

    function toTask(t) {
        // All-day dues are a bare date. Timed dues add a floating time, which
        // Date reads as local, or end in "Z" for a fixed timezone, which Date
        // converts from UTC to local.
        const raw = t.due?.date || "";
        const when = raw.length > 10 ? new Date(raw) : null;
        return {
            id: t.id,
            content: t.content,
            date: when ? Qt.formatDate(when, "yyyy-MM-dd") : raw,
            time: when ? Qt.formatTime(when, "HH:mm") : "",
            recurring: !!t.due?.is_recurring,
            priority: t.priority || 1
        };
    }

    // Earliest date first. Within a day, timed tasks by time and ahead of
    // all-day ones, then Todoist's priority 4 (urgent) first.
    function byDueThenPriority(a, b) {
        if (a.date !== b.date)
            return a.date < b.date ? -1 : 1;
        if (a.time !== b.time) {
            if (a.time === "")
                return 1;
            if (b.time === "")
                return -1;
            return a.time < b.time ? -1 : 1;
        }
        return b.priority - a.priority;
    }
}
