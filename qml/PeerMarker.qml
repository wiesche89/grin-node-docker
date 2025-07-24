import QtQuick 2.15
import QtLocation 5.15
import QtPositioning 5.15

MapQuickItem {
    id: marker
    objectName: "peerMarker"
    anchorPoint.x: 8
    anchorPoint.y: 8
    coordinate: QtPositioning.coordinate(0, 0)

    sourceItem: Rectangle {
        width: 24
        height: 24
        radius: 12
        color: "yellow"
        border.color: "black"
        border.width: 2
    }
}
