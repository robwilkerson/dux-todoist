// The Todoist mark, recolored to follow the theme.
//
// The source SVG is a red rounded square with three white chevrons. Here the
// square and chevrons are one ShapePath with an odd-even fill, so the chevrons
// are cut out of a single solid shape and `markColor` controls all of it.

import QtQuick
import QtQuick.Shapes
import qs.Common

Item {
    id: mark

    property real size: 24
    property color markColor: Theme.widgetIconColor

    // Source viewBox. The paths are authored in these units and scaled to `size`.
    readonly property real viewBox: 256

    width: size
    height: size

    Shape {
        width: mark.viewBox
        height: mark.viewBox
        preferredRendererType: Shape.CurveRenderer

        // Scale origin defaults to (0,0), so the scaled mark fills the Item
        // from the top-left. Do not anchor-center the Shape as well.
        transform: Scale {
            xScale: mark.size / mark.viewBox
            yScale: mark.size / mark.viewBox
        }

        ShapePath {
            fillColor: mark.markColor
            strokeWidth: 0
            fillRule: ShapePath.OddEvenFill

            PathSvg {
                path: "M224.002 0H31.998C14.358.04.061 14.337 0 32v192c0 17.6 14.397 32 31.998 32h192.004c17.6 0 31.998-14.4 31.998-32V32c0-17.6-14.397-32-31.998-32"
                    + "M54.133 120.802c4.463-2.606 100.343-58.325 102.535-59.616 2.192-1.275 2.311-5.196-.16-6.615-2.454-1.41-7.117-4.089-8.846-5.117a8.03 8.03 0 0 0-7.907.096c-1.227.717-83.151 48.299-85.885 49.86-3.292 1.882-7.333 1.914-10.6 0L0 74.019v21.583c10.52 6.2 36.718 21.599 43.062 25.225 3.786 2.152 7.413 2.105 11.079-.024"
                    + "M54.133 161.61c4.463-2.607 100.343-58.326 102.535-59.617 2.192-1.275 2.311-5.196-.16-6.615-2.454-1.41-7.117-4.089-8.846-5.117a8.03 8.03 0 0 0-7.907.096c-1.227.717-83.151 48.298-85.885 49.86-3.292 1.882-7.333 1.913-10.6 0L0 114.826v21.583c10.52 6.2 36.718 21.599 43.062 25.225 3.786 2.152 7.413 2.104 11.079-.024"
                    + "M54.133 204.967c4.463-2.607 100.343-58.326 102.535-59.617 2.192-1.275 2.311-5.196-.16-6.615-2.454-1.41-7.117-4.088-8.846-5.117a8.03 8.03 0 0 0-7.907.096c-1.227.717-83.151 48.299-85.885 49.86-3.292 1.882-7.333 1.914-10.6 0L0 158.183v21.583c10.52 6.2 36.718 21.6 43.062 25.225 3.786 2.152 7.413 2.105 11.079-.023"
            }
        }
    }
}
