import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "./components"

PluginComponent {
    id: root

    readonly property real markSize: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)

    // The task list grows with its content up to this height, then scrolls.
    readonly property real maxListHeight: 420

    // pluginData reloads whenever the settings pane saves. tokenSavedAt only
    // exists so a new token triggers a refresh here.
    readonly property int daysAhead: pluginData.daysAhead ?? 1
    readonly property var tokenSavedAt: pluginData.tokenSavedAt ?? 0
    onTokenSavedAtChanged: client.refresh()

    Component.onCompleted: client.refresh()

    // The popout's content is built once and reused, so its own onCompleted
    // doesn't fire per open. interactionActive does.
    onInteractionActiveChanged: {
        if (interactionActive) {
            client.refresh();
            root.now = root.minuteNow();
            root.armClock();
        } else {
            clock.stop();
            root.closeAdd();
        }
    }

    // The add field at the top of the popout. Stays open after each add, so
    // several can go in a row.
    property bool adding: false
    property bool addBusy: false

    // The last add's failure as ErrorNotice fields, or null. Cleared by the
    // next attempt or by closing the field.
    property var addNotice: null

    // The text of the add in flight. The field may be closed by the time it
    // fails, so the popout restores it from here instead of losing it.
    property string pendingAdd: ""

    function closeAdd() {
        adding = false;
        addNotice = null;
    }

    function submitAdd(text) {
        const trimmed = text.trim();
        if (trimmed === "" || addBusy)
            return;
        addBusy = true;
        addNotice = null;
        pendingAdd = trimmed;
        client.addTask(trimmed);
    }

    TodoistClient {
        id: client
        daysAhead: root.daysAhead
        onDaysAheadChanged: refresh()
    }

    // The time the groups are drawn against, floored to the minute. Todoist
    // stores minutes, so a 3:00 PM task is overdue once this reads 3:00.
    property var now: minuteNow()

    function minuteNow() {
        return new Date(Math.floor(Date.now() / 60000) * 60000);
    }

    // Ticks at the top of each minute while the popout is open, regrouping
    // locally without a fetch. The pad keeps an early fire from flooring back
    // to the previous minute.
    function armClock() {
        clock.interval = 60000 - Date.now() % 60000 + 50;
        clock.restart();
    }

    Timer {
        id: clock
        onTriggered: {
            root.now = root.minuteNow();
            root.armClock();
        }
    }

    // A completed task stays visible, struck through, until both its request
    // has succeeded and this long has passed since the click.
    readonly property int completeHoldMs: 2000

    // taskId -> { startedAt, succeeded, unconfirmed, task }, where `task` is
    // the row as it was clicked. Replaced, never mutated, so bindings update.
    property var completions: ({})
    readonly property var pendingIds: Object.keys(completions)

    // Completions whose close timed out. Their rows stay struck through, in
    // the error color and unclickable, so a retry can't close a recurring
    // task twice. The next successful refresh releases them to the server's
    // state.
    readonly property var unconfirmedIds: pendingIds.filter(id => completions[id].unconfirmed)

    function completeTask(taskId) {
        const task = client.tasks.find(t => t.id === taskId);
        if (completions[taskId] || !task)
            return;
        completions = Object.assign({}, completions, {
            [taskId]: {
                startedAt: Date.now(),
                succeeded: false,
                unconfirmed: false,
                task: task
            }
        });
        client.complete(taskId);
    }

    // A task being completed shows as it was clicked until its hold ends, so a
    // refresh meanwhile can't drop it early or move it to its next occurrence.
    readonly property var shownTasks: {
        const ids = Object.keys(completions);
        if (ids.length === 0)
            return client.tasks;
        const held = ids.map(id => completions[id].task);
        return client.tasks.filter(t => !completions[t.id]).concat(held).sort(client.byDueThenPriority);
    }

    function dropCompletion(taskId) {
        const next = Object.assign({}, completions);
        delete next[taskId];
        completions = next;
    }

    Connections {
        target: client

        function onCompleted(taskId, ok, errorText) {
            if (!root.completions[taskId])
                return;
            if (!ok) {
                root.dropCompletion(taskId);
                ToastService.showError("Couldn't complete task in Todoist", errorText);
                return;
            }
            root.completions = Object.assign({}, root.completions, {
                [taskId]: Object.assign({}, root.completions[taskId], {
                    succeeded: true
                })
            });
        }

        function onUnconfirmed(taskId) {
            if (!root.completions[taskId])
                return;
            root.completions = Object.assign({}, root.completions, {
                [taskId]: Object.assign({}, root.completions[taskId], {
                    unconfirmed: true
                })
            });
        }

        function onRefreshed() {
            for (const id of root.unconfirmedIds)
                root.dropCompletion(id);
        }

        // The field clears itself on "ok" (see the popout); a failure keeps
        // the text so Enter can retry it.
        function onAdded(outcome, detail) {
            root.addBusy = false;
            if (outcome === "ok")
                ToastService.showInfo("Added to Todoist", detail);
            else if (outcome === "unverified")
                root.addNotice = { icon: "❓", message: "Unable to verify task was added", instruction: "Check the list before retrying" };
            else
                root.addNotice = root.failureNotice(detail, "Press Enter to try again");
        }
    }

    // Removes each task once its request succeeded and its hold has elapsed,
    // whichever comes last. Only a recurring task needs a refresh, to pick up
    // its next occurrence; any other task is simply gone.
    Timer {
        interval: 100
        repeat: true
        running: root.pendingIds.length > root.unconfirmedIds.length
        onTriggered: {
            const now = Date.now();
            const done = root.pendingIds.filter(id => {
                const c = root.completions[id];
                return c.succeeded && now - c.startedAt >= root.completeHoldMs;
            });
            if (done.length === 0)
                return;
            const recurred = done.some(id => root.completions[id].task.recurring);
            for (const id of done) {
                client.removeLocal(id);
                root.dropCompletion(id);
            }
            if (recurred)
                client.refresh();
        }
    }

    // Found through its desktop entry, which covers the Flatpak (whose binary
    // isn't on PATH) and native installs alike. Reading `applications` makes
    // this re-evaluate when apps are installed or removed.
    readonly property var appEntry: {
        DesktopEntries.applications.values;
        return DesktopEntries.heuristicLookup("com.todoist.Todoist") ?? DesktopEntries.heuristicLookup("todoist");
    }
    readonly property bool appInstalled: !!appEntry

    function openApp() {
        root.closePopout();
        // Todoist is single-instance: a second launch raises the open window.
        appEntry.execute();
    }

    function localDate(offsetDays) {
        const d = new Date(now);
        d.setDate(d.getDate() + offsetDays);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function dayLabel(date) {
        return Qt.formatDate(date, "ddd, MMM d");
    }

    function timeLabel(task) {
        return task.time === "" ? "" : new Date(task.date + "T" + task.time).toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    function dateLabel(task) {
        return dayLabel(new Date(task.date + "T00:00:00"));
    }

    // Overdue from earlier today reads better as its time than as today's date.
    function overdueLabel(task) {
        return task.date === localDate(0) ? timeLabel(task) : dateLabel(task);
    }

    // Calendar weeks start on Todoist's "Start of week", or the locale's
    // first day until that's read.
    readonly property int weekStart: client.weekStart >= 0 ? client.weekStart : Qt.locale().firstDayOfWeek

    // Overdue shows only when it has tasks. The rest show when at least one
    // day of the window falls in them, even if empty. Tomorrow wins over a
    // week boundary. Client order (date, time, priority) carries through.
    // The groups themselves are fixed, so a refresh only changes their rows.
    readonly property var sections: {
        const tasks = root.shownTasks;
        const last = daysAhead - 1;
        const today = localDate(0);
        const clockTime = Qt.formatTime(now, "HH:mm");
        const tomorrow = new Date(now);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const weekEnd = (weekStart + 6 - now.getDay()) % 7;
        const nextStart = Math.max(2, weekEnd + 1);
        const between = (from, to) => tasks.filter(t => t.date >= localDate(from) && (to === null || t.date <= localDate(to)));
        // Earlier days, plus today's timed tasks once the clock reaches them.
        const isOverdue = t => t.date < today || (t.date === today && t.time !== "" && t.time <= clockTime);
        const overdue = tasks.filter(isOverdue);

        return {
            overdue: { shown: overdue.length > 0, title: "Overdue", tasks: overdue },
            today: { shown: true, title: "Today (" + dayLabel(now) + ")", tasks: between(0, 0).filter(t => !isOverdue(t)) },
            tomorrow: { shown: last >= 1, title: "Tomorrow (" + dayLabel(tomorrow) + ")", tasks: between(1, 1) },
            thisWeek: { shown: weekEnd >= 2 && last >= 2, title: "This Week", tasks: between(2, weekEnd) },
            nextWeek: { shown: last >= nextStart, title: "Next Week", tasks: between(nextStart, weekEnd + 7) },
            later: { shown: last >= weekEnd + 8, title: "Later", tasks: between(weekEnd + 8, null) }
        };
    }

    // The plugin can't work at all: no Todoist app, or no secret-tool to read
    // the token with. Tints the pill and styles the popout message as an error.
    readonly property bool hardFail: !appInstalled || client.status === "noSecretTool"

    // Also tinted while Todoist can't be reached, until a request gets through.
    readonly property color pillColor: hardFail || client.offline ? Theme.error : Theme.widgetIconColor

    // Stands in for the list when it can't be shown, as ErrorNotice fields,
    // or null. Loading isn't an error, so it's handled apart.
    readonly property var blocker: {
        if (!appInstalled)
            return { icon: "🔎", message: "Todoist not installed", instruction: "Install it to use this widget" };
        switch (client.status) {
        case "noToken":
            return { icon: "🔑", message: "Missing API token", instruction: "Add it in plugin settings" };
        case "noKeyring":
            return { icon: "🔒", message: "Unable to access keyring", instruction: "Unlock it, then refresh" };
        case "noSecretTool":
            return { icon: "🔒", message: "Unable to access keyring", instruction: "Install libsecret to use this widget" };
        case "error":
            return failureNotice(client.errorText, "Refresh to try again");
        default:
            return null;
        }
    }

    // A request failure as ErrorNotice fields. The reason is one of
    // client.failureText()'s strings; the icon carries the kind, so only
    // Todoist's own errors spell the reason out.
    function failureNotice(reason, instruction) {
        if (reason === "Timed out")
            return { icon: "⌛", message: "Todoist timed out", instruction: instruction };
        if (reason === "Network error")
            return { icon: "📡", message: "Unable to reach Todoist", instruction: instruction };
        return { icon: "⚠️", message: "Todoist error (" + reason + ")", instruction: instruction };
    }
    readonly property bool listReady: blocker === null && client.status === "ready"

    // Sits above a loaded list. A failed add is shown first, since it sits
    // right under the field that caused it. An unconfirmed completion outranks
    // a failed refresh, since it asks for something the list alone can't show.
    readonly property var listNotice: {
        if (addNotice !== null)
            return addNotice;
        if (unconfirmedIds.length > 0)
            return { icon: "❓", message: "Unable to verify completion", instruction: "Refresh to check" };
        if (client.staleText !== "")
            return failureNotice(client.staleText, "");
        return null;
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: barIcon.width
            implicitHeight: barIcon.height
            anchors.verticalCenter: parent.verticalCenter

            TodoistMark {
                id: barIcon
                anchors.centerIn: parent
                size: root.markSize
                markColor: root.pillColor
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: barIconV.width
            implicitHeight: barIconV.height
            anchors.horizontalCenter: parent.horizontalCenter

            TodoistMark {
                id: barIconV
                anchors.centerIn: parent
                size: root.markSize
                markColor: root.pillColor
            }
        }
    }

    popoutWidth: 360
    popoutContent: Component {
        PopoutComponent {
            headerText: "Todoist"

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    DActionButton {
                        visible: root.listReady
                        iconName: "add"
                        iconColor: root.adding ? Theme.primary : Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Add Task"
                        tooltipSide: "bottom"
                        onClicked: root.adding ? root.closeAdd() : root.adding = true
                    }

                    DRefreshButton {
                        busy: client.busy
                        iconColor: Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Refresh"
                        tooltipSide: "bottom"
                        onClicked: client.refresh()
                    }

                    DActionButton {
                        iconName: "settings"
                        iconColor: Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Plugin Settings"
                        tooltipSide: "bottom"
                        onClicked: {
                            root.closePopout();
                            PopoutService.openSettingsWithTab("plugins");
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Slides open under the header, pushing the list down.
                Item {
                    visible: height > 0
                    width: parent.width
                    height: root.adding && root.listReady ? addRow.implicitHeight : 0
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }

                    Row {
                        id: addRow
                        width: parent.width
                        spacing: Theme.spacingXS

                        DTextField {
                            id: addField
                            width: addRow.width - dismiss.width - addRow.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            leftIconName: "add_task"
                            placeholderText: "Call mom tomorrow 5pm #Family p1"
                            hidePlaceholderOnFocus: false
                            busy: root.addBusy
                            readOnly: root.addBusy
                            keyForwardTargets: [addKeys]

                            onAccepted: root.submitAdd(text)
                            onTextEdited: root.addNotice = null

                            Item {
                                id: addKeys
                                Keys.onEscapePressed: event => {
                                    root.closeAdd();
                                    event.accepted = true;
                                }
                            }
                        }

                        DActionButton {
                            id: dismiss
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "close"
                            iconColor: Theme.surfaceVariantText
                            buttonSize: 28
                            tooltipText: "Dismiss"
                            tooltipSide: "bottom"
                            onClicked: root.closeAdd()
                        }
                    }

                    Connections {
                        target: root

                        function onAddingChanged() {
                            if (root.adding)
                                Qt.callLater(() => addField.forceActiveFocus());
                            else
                                addField.text = "";
                        }
                    }

                    Connections {
                        target: client

                        // A failure puts the submitted text back if the field
                        // was closed meanwhile, so reopening it can retry.
                        function onAdded(outcome, detail) {
                            if (outcome === "ok")
                                addField.text = "";
                            else if (addField.text === "")
                                addField.text = root.pendingAdd;
                            root.pendingAdd = "";
                        }
                    }
                }

                ErrorNotice {
                    visible: root.blocker !== null
                    width: parent.width
                    topPadding: Theme.spacingM
                    bottomPadding: Theme.spacingM
                    icon: root.blocker?.icon ?? ""
                    message: root.blocker?.message ?? ""
                    instruction: root.blocker?.instruction ?? ""
                }

                StyledText {
                    visible: root.blocker === null && !root.listReady
                    leftPadding: Theme.spacingS
                    topPadding: Theme.spacingM
                    bottomPadding: Theme.spacingM
                    text: "Loading…"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                }

                ErrorNotice {
                    visible: root.listReady && root.listNotice !== null
                    width: parent.width
                    icon: root.listNotice?.icon ?? ""
                    message: root.listNotice?.message ?? ""
                    instruction: root.listNotice?.instruction ?? ""
                }

                DFlickable {
                    visible: root.listReady
                    width: parent.width
                    height: Math.min(groups.implicitHeight, root.maxListHeight)
                    contentHeight: groups.implicitHeight
                    interactive: contentHeight > height
                    clip: true

                    Column {
                        id: groups
                        width: parent.width
                        spacing: Theme.spacingL

                        Repeater {
                            model: [
                                { key: "overdue", label: root.overdueLabel, emptyText: "" },
                                { key: "today", label: root.timeLabel, emptyText: "🎉 Nothing planned" },
                                { key: "tomorrow", label: root.timeLabel, emptyText: "" },
                                { key: "thisWeek", label: root.dateLabel, emptyText: "" },
                                { key: "nextWeek", label: root.dateLabel, emptyText: "" },
                                { key: "later", label: root.dateLabel, emptyText: "" }
                            ]

                            // Overdue sits on a card so it stands out from the
                            // groups that are still on schedule.
                            delegate: StyledRect {
                                id: card

                                required property var modelData
                                readonly property var section: root.sections[modelData.key]
                                readonly property bool overdue: modelData.key === "overdue"
                                readonly property real inset: overdue ? Theme.spacingS : 0

                                visible: section.shown
                                width: parent.width
                                height: group.implicitHeight + inset * 2
                                radius: Theme.cornerRadius
                                color: overdue ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.55) : "transparent"

                                TaskGroup {
                                    id: group
                                    x: card.inset
                                    y: card.inset
                                    width: card.width - card.inset * 2
                                    title: card.section.title
                                    titleColor: card.overdue ? Theme.error : Theme.surfaceText
                                    tasks: card.section.tasks
                                    dueLabel: card.modelData.label
                                    emptyText: card.modelData.emptyText
                                    pendingIds: root.pendingIds
                                    errorIds: root.unconfirmedIds
                                    onCompleteRequested: taskId => root.completeTask(taskId)
                                }
                            }
                        }
                    }
                }

                DButton {
                    width: parent.width
                    text: "Open Todoist"
                    buttonHeight: 36
                    visible: root.appInstalled
                    onClicked: root.openApp()
                }
            }
        }
    }
}
