import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    Layout.fillWidth: true
    Layout.fillHeight: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        Label {
            text: "Kernel"
            color: "white"
            font.pixelSize: 28
            font.bold: true
        }

        Label {
            text: "Kernel content goes here."
            color: "#bbbbbb"
        }
    }
}
