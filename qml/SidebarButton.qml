import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    property alias text: label.text
    signal clicked()

    width: parent ? parent.width - 20 : 180
    height: 50
    radius: 8
    color: hovered ? "#3a3a3a" : "#2d2d2d"
    border.color: "#555"
    border.width: 1

    property bool hovered: false

    Text {
        id: label
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 16
        font.bold: true
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
        onEntered: root.hovered = true
        onExited: root.hovered = false
    }
}
