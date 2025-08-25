import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    Layout.fillWidth: true
    Layout.fillHeight: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        Label {
            text: "Grin Node Settings"
            color: "white"
            font.pixelSize: 28
            font.bold: true
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: config.allEntries()
            delegate: Rectangle {
                width: parent.width
                height: type === 1 ? 20 : 40   // Section kleiner anzeigen
                color: type === 2 ? "#333" : "transparent"

                RowLayout {
                    anchors.fill: parent
                    spacing: 6

                    Label {
                        visible: type === 2
                        text: key
                        color: "#dddddd"
                        Layout.preferredWidth: 250
                    }

                    TextField {
                        visible: type === 2
                        text: value
                        Layout.fillWidth: true
                        onEditingFinished: config.setValue(section, key, text)
                    }

                    Label {
                        visible: type === 1
                        text: "[" + section + "]"
                        color: "#66aaff"
                        font.bold: true
                    }
                }
            }
        }

        Button {
            text: "Save Config"
            onClicked: config.save("C:/Users/Wiesche/.grin/test/grin-server.toml")
        }
    }
}
