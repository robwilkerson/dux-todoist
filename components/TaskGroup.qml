// A titled list of tasks in the popout. With no tasks it shows `emptyText`,
// or a blank line when that is blank, so an empty group still reads as one.

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: group

    property string title: ""
    property color titleColor: Theme.primary
    property var tasks: []
    property string emptyText: ""

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
        visible: group.tasks.length === 0
        leftPadding: Theme.spacingS
        text: group.emptyText !== "" ? group.emptyText : " "
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
                    visible: row.modelData.recurring
                    name: "sync"
                    size: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: group.dueLabel(row.modelData)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
