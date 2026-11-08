// A titled list of tasks in the popout. With no tasks it shows `emptyText`,
// or hides entirely when that is blank.

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: group

    property string title: ""
    property color titleColor: Theme.primary
    property var tasks: []
    property string emptyText: ""

    // Formats a task's YYYY-MM-DD date for the trailing label.
    property var dueLabel: date => date

    // Ids of tasks being completed: shown checked and struck through until
    // the caller removes them or clears the id after an error.
    property var pendingIds: []

    signal completeRequested(string taskId)

    width: parent.width
    spacing: Theme.spacingXS
    visible: tasks.length > 0 || emptyText !== ""

    StyledText {
        leftPadding: Theme.spacingS
        bottomPadding: Theme.spacingXS
        text: group.title
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: group.titleColor
    }

    StyledText {
        visible: group.tasks.length === 0
        leftPadding: Theme.spacingS
        text: group.emptyText
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceText
    }

    Repeater {
        model: group.tasks

        delegate: Item {
            id: row

            required property var modelData
            readonly property bool pending: group.pendingIds.includes(modelData.id)

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
                    onClicked: group.completeRequested(row.modelData.id)
                }
            }

            StyledText {
                id: itemText

                readonly property real firstLineHeight: fontMetrics.height

                anchors.left: check.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: due.left
                anchors.rightMargin: Theme.spacingS
                text: modelData.content
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeLarge
                font.strikeout: row.pending
                color: row.pending ? Theme.surfaceVariantText : Theme.surfaceText

                FontMetrics {
                    id: fontMetrics
                    font: itemText.font
                }
            }

            StyledText {
                id: due
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                y: Math.max(0, (itemText.firstLineHeight - height) / 2)
                text: group.dueLabel(modelData.date)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
