import QtQuick 2.15
import QtQuick.Controls 2.15

Button {
    id: control
    implicitHeight: 46
    implicitWidth: 160
    flat: true
    padding: 10

    background: Rectangle {
        radius: 6
        color: control.down ? "#2f2f2f" : control.enabled ? control.hovered ? "#3d3d3d" : "#2b2b2b" : "#1f1f1f"
        border.color: control.down ? "#66aaff" : "#555"
        border.width: 1
    }

    contentItem: Text {
        text: control.text
        color: control.enabled ? "white" : "#777"
        font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
