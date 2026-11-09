// A titled list of tasks in the popout. With no tasks it shows `emptyText`,
// or a blank line when that is blank, so an empty group still reads as one.

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: group

    property string title: ""
    property color titleColor: Theme.primary
    // Plain task objects from the client. Each change is diffed into `rows`
    // by id, so unchanged rows keep their delegates instead of rebuilding.
    property var tasks: []
    property string emptyText: ""

    ListModel {
        id: rows
    }

    onTasksChanged: sync(tasks)
    Component.onCompleted: sync(tasks)

    function toRow(t) {
        return {
            taskId: t.id,
            content: t.content,
            date: t.date,
            time: t.time,
            recurring: t.recurring
        };
    }

    function indexOf(taskId, from) {
        for (let i = from; i < rows.count; i++) {
            if (rows.get(i).taskId === taskId)
                return i;
        }
        return -1;
    }

    // Removes rows that are gone, then walks the new order, moving, inserting,
    // or updating each row in place.
    function sync(next) {
        const keep = new Set(next.map(t => t.id));
        for (let i = rows.count - 1; i >= 0; i--) {
            if (!keep.has(rows.get(i).taskId))
                rows.remove(i);
        }
        for (let i = 0; i < next.length; i++) {
            const row = toRow(next[i]);
            const at = indexOf(row.taskId, i);
            if (at < 0) {
                rows.insert(i, row);
                continue;
            }
            if (at !== i)
                rows.move(at, i, 1);
            const current = rows.get(i);
            for (const key in row) {
                if (current[key] !== row[key])
                    rows.setProperty(i, key, row[key]);
            }
        }
    }

    // Formats a task's trailing label, such as its time or date.
    property var dueLabel: task => task.date

    // Ids of tasks being completed: shown checked and struck through until
    // the caller removes them or clears the id after an error.
    property var pendingIds: []

    signal completeRequested(string taskId)

    width: parent.width
    spacing: Theme.spacingXS

    StyledText {
        leftPadding: Theme.spacingS
        bottomPadding: Theme.spacingXS
        text: group.title
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: group.titleColor
    }

    StyledText {
        visible: rows.count === 0
        leftPadding: Theme.spacingS
        text: group.emptyText !== "" ? group.emptyText : " "
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    Repeater {
        model: rows

        delegate: Item {
            id: row

            required property string taskId
            required property string content
            required property string date
            required property string time
            required property bool recurring
            readonly property bool pending: group.pendingIds.includes(taskId)
            width: group.width
            height: Math.max(check.height, itemText.implicitHeight)

            // Top-aligned with the first line of text rather than centered on
            // the row, so it stays put if a row ever grows taller.
            Rectangle {
                id: check
                x: Theme.spacingS
                y: Math.max(0, (itemText.firstLineHeight - height) / 2)
                width: Math.round(Theme.fontSizeLarge * 1.2)
                height: width
                radius: width / 2
                color: row.pending ? Theme.primary : "transparent"
                border.width: 1.5
                border.color: row.pending || checkArea.containsMouse ? Theme.primary : Theme.surfaceVariantText

                DIcon {
                    anchors.centerIn: parent
                    name: "check"
                    size: parent.width * 0.75
                    color: row.pending ? Theme.primaryText : Theme.primary
                    visible: row.pending || checkArea.containsMouse
                }

                // Larger than the circle, for an easier click target.
                MouseArea {
                    id: checkArea
                    anchors.fill: parent
                    anchors.margins: -Theme.spacingXS
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !row.pending
                    onClicked: group.completeRequested(row.taskId)
                }
            }

            StyledText {
                id: itemText

                readonly property real firstLineHeight: fontMetrics.height

                anchors.left: check.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: due.left
                anchors.rightMargin: Theme.spacingS
                text: row.content
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeLarge
                font.strikeout: row.pending
                color: row.pending ? Theme.surfaceVariantText : Theme.surfaceText

                FontMetrics {
                    id: fontMetrics
                    font: itemText.font
                }
            }

            // A recurring task shows only its next occurrence, so the icon
            // explains why it appears once.
            Row {
                id: due
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                y: Math.max(0, (itemText.firstLineHeight - height) / 2)
                spacing: Theme.spacingXS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.recurring
                    name: "sync"
                    size: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: group.dueLabel({
                        date: row.date,
                        time: row.time
                    })
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
