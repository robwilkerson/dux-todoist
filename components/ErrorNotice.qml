// A popout error: an emoji, the error, and optionally what to do about it.
// The error is always one line, elided if it must be; the instruction wraps.
// Both sit in their own column, so they stay aligned beside the icon.

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: notice

    property string icon: "⛔"
    property string message: ""
    property string instruction: ""

    spacing: Theme.spacingS
    leftPadding: Theme.spacingS
    rightPadding: Theme.spacingS

    StyledText {
        id: glyph
        text: notice.icon
        font.pixelSize: Theme.fontSizeMedium
    }

    Column {
        width: notice.width - notice.leftPadding - notice.rightPadding - glyph.width - notice.spacing

        StyledText {
            width: parent.width
            text: notice.message
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.error
        }

        StyledText {
            width: parent.width
            visible: notice.instruction !== ""
            text: notice.instruction
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.error
        }
    }
}
