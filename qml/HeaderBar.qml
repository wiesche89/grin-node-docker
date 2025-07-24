import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ToolBar {
    id: root
    signal refreshClicked()

    background: Rectangle {
        color: "#212121"
        border.color: "#333"
    }

    // Wir packen eine RowLayout in einen Container mit Margins
    Item {
        anchors.fill: parent
        anchors.margins: 12    // Abstand innen

        RowLayout {
            anchors.fill: parent
            spacing: 20

            Label {
                text: "Grin Node Dashboard"
                font.pixelSize: 22
                font.bold: true
                color: "white"
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true } // flexibler Abstand

            Button {
                text: "🔄 Refresh"
                font.pixelSize: 16
                onClicked: root.refreshClicked()
            }
        }
    }
}
