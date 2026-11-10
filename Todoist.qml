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
        }
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

    // taskId -> { startedAt, succeeded, task }, where `task` is the row as it
    // was clicked. Replaced, never mutated, so bindings on pendingIds update.
    property var completions: ({})
    readonly property var pendingIds: Object.keys(completions)

    function completeTask(taskId) {
        const task = client.tasks.find(t => t.id === taskId);
        if (completions[taskId] || !task)
            return;
        completions = Object.assign({}, completions, {
            [taskId]: {
                startedAt: Date.now(),
                succeeded: false,
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
    }

    // Removes each task once its request succeeded and its hold has elapsed,
    // whichever comes last. Only a recurring task needs a refresh, to pick up
    // its next occurrence; any other task is simply gone.
    Timer {
        interval: 100
        repeat: true
        running: root.pendingIds.length > 0
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
    readonly property color pillColor: hardFail ? Theme.error : Theme.widgetIconColor

    readonly property string emptyMessage: {
        if (!appInstalled)
            return "Todoist wasn't found. Install it (Flathub: com.todoist.Todoist), or remove this widget from the bar.";
        switch (client.status) {
        case "noToken":
            return "Add your Todoist API token in the plugin's settings.";
        case "noKeyring":
            return "Can't reach a keyring (Secret Service). " + client.errorText;
        case "noSecretTool":
            return client.errorText;
        case "error":
            return "Couldn't load tasks: " + client.errorText;
        case "ready":
            return "";
        default:
            return "Loading…";
        }
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

                StyledText {
                    visible: root.emptyMessage !== ""
                    width: parent.width
                    leftPadding: Theme.spacingS
                    rightPadding: Theme.spacingS
                    topPadding: Theme.spacingM
                    bottomPadding: Theme.spacingM
                    text: root.emptyMessage
                    wrapMode: Text.WordWrap
                    font.pixelSize: root.hardFail ? Theme.fontSizeLarge : Theme.fontSizeMedium
                    color: root.hardFail ? Theme.error : Theme.surfaceVariantText
                }

                DFlickable {
                    visible: root.emptyMessage === ""
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
