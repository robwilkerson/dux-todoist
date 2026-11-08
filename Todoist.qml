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

    readonly property int refreshMinutes: 5

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
        if (interactionActive)
            client.refresh();
    }

    TodoistClient {
        id: client
        daysAhead: root.daysAhead
        onDaysAheadChanged: refresh()
    }

    Timer {
        interval: root.refreshMinutes * 60 * 1000
        running: true
        repeat: true
        onTriggered: client.refresh()
    }

    // A completed task stays visible, struck through, until both its request
    // has succeeded and this long has passed since the click.
    readonly property int completeHoldMs: 2000

    // taskId -> { startedAt, succeeded }. Replaced, never mutated, so bindings
    // on pendingIds update.
    property var completions: ({})
    readonly property var pendingIds: Object.keys(completions)

    function completeTask(taskId) {
        if (completions[taskId])
            return;
        completions = Object.assign({}, completions, {
            [taskId]: {
                startedAt: Date.now(),
                succeeded: false
            }
        });
        client.complete(taskId);
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
    // whichever comes last, then refreshes so a recurring task's next
    // occurrence shows up.
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
            for (const id of done) {
                client.removeLocal(id);
                root.dropCompletion(id);
            }
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
        const d = new Date();
        d.setDate(d.getDate() + offsetDays);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function dueLabel(date) {
        if (date === localDate(0))
            return "Today";
        if (date === localDate(1))
            return "Tomorrow";
        return Qt.formatDate(new Date(date + "T00:00:00"), "MMM d");
    }

    // Client order (date, then priority) carries through both filters.
    readonly property var overdueTasks: client.tasks.filter(t => t.date < localDate(0))
    readonly property var agendaTasks: client.tasks.filter(t => t.date >= localDate(0))

    readonly property string emptyMessage: {
        if (!appInstalled)
            return "Todoist wasn't found. Install it (Flathub: com.todoist.Todoist), or remove this widget from the bar.";
        switch (client.status) {
        case "noToken":
            return "Add your Todoist API token in the plugin's settings.";
        case "noKeyring":
            return "Can't reach a keyring (Secret Service). " + client.errorText;
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
                markColor: root.appInstalled ? Theme.widgetIconColor : Theme.error
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
                markColor: root.appInstalled ? Theme.widgetIconColor : Theme.error
            }
        }
    }

    popoutWidth: 360
    popoutContent: Component {
        PopoutComponent {
            headerText: "Todoist"

            headerActions: Component {
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

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    visible: root.emptyMessage !== ""
                    width: parent.width
                    leftPadding: Theme.spacingS
                    rightPadding: Theme.spacingS
                    text: root.emptyMessage
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
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

                        TaskGroup {
                            title: "Overdue"
                            titleColor: Theme.error
                            tasks: root.overdueTasks
                            dueLabel: root.dueLabel
                            pendingIds: root.pendingIds
                            onCompleteRequested: taskId => root.completeTask(taskId)
                        }

                        TaskGroup {
                            title: "Agenda"
                            titleColor: Theme.surfaceText
                            tasks: root.agendaTasks
                            dueLabel: root.dueLabel
                            pendingIds: root.pendingIds
                            onCompleteRequested: taskId => root.completeTask(taskId)
                            emptyText: root.daysAhead === 1 ? "🎉 Enjoy the rest of your day!" : "🎉 Nothing due. Enjoy the break!"
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
