import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    //width: parent ? parent.width : 1100
    //height: implicitHeight
    color: "#2b2b2b"
    radius: 6
    border.color: "#555"
    border.width: 1

    property var peersModel: []
    property string lastUpdated: ""
    property int headingFontSize: 20
    property int bodyFontSize: 16

    ScrollView {
        id: tableScroll
        anchors.fill: parent
        clip: true
        Layout.fillWidth: true
        Layout.fillHeight: true
        ScrollBar.horizontal.policy: ScrollBar.AsNeeded
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            spacing: 12

            //Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: "Connected Peers"
                    font.pixelSize: headingFontSize
                    font.bold: true
                    color: "#ffffff"
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: lastUpdated !== "" ? "Last Update: " + lastUpdated : ""
                    font.pixelSize: bodyFontSize
                    color: "#aaaaaa"
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
            }

            Rectangle {
                width: parent ? parent.width : 930
                height: 30
                color: "#444"
                radius: 4
                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 16

                Label { text: "UserAgent"; color: "white"; font.bold: true; font.pixelSize: 16; width: 160 }
                Label { text: "Height"; color: "white"; font.bold: true; font.pixelSize: 16; width: 90; horizontalAlignment: Text.AlignHCenter }
                Label { text: "Addr"; color: "white"; font.bold: true; font.pixelSize: 16; width: 180 }
                Label { text: "Version"; color: "white"; font.bold: true; font.pixelSize: 16; width: 80; horizontalAlignment: Text.AlignHCenter }
                Label { text: "Dir"; color: "white"; font.bold: true; font.pixelSize: 16; width: 90; horizontalAlignment: Text.AlignHCenter }
                Label { text: "Capabilities"; color: "white"; font.bold: true; font.pixelSize: 16; width: 130 }
                Label { text: "Difficulty"; color: "white"; font.bold: true; font.pixelSize: 16; width: 160 }
                }
            }

            ListView {
                id: peerList
                width: parent ? parent.width : 930
                height: 400
                clip: true
                spacing: 2
                model: root.peersModel
                Layout.fillWidth: true
                Layout.preferredHeight: 360

                delegate: Rectangle {
                    width: peerList.width
                    height: 28
                    color: index % 2 === 0 ? "#3a3a3a" : "#333333"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 16

                    Label { text: modelData.userAgent; color: "#ffffff"; width: 160; elide: Text.ElideRight; font.pixelSize: 16 }
                    Label { text: modelData.height; color: "#cccccc"; width: 90; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 16 }
                    Label { text: modelData.addr.asString; color: "#cccccc"; width: 180; elide: Text.ElideRight; font.pixelSize: 16 }
                    Label { text: modelData.version.asString; color: "#cccccc"; width: 80; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 16 }
                    Label { text: modelData.direction.asString; color: "#cccccc"; width: 90; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 16 }
                    Label { text: modelData.capabilities.asString; color: "#cccccc"; width: 130; elide: Text.ElideRight; font.pixelSize: 16 }
                    Label { text: modelData.totalDifficulty.asString; color: "#cccccc"; width: 160; elide: Text.ElideRight; font.pixelSize: 16 }
                    }
                }
            }
        }
    }

    // Verbindung zum C++-Signal
    Connections {
        target: nodeOwnerApi
        function onConnectedPeersUpdated(peersArray) {
            root.peersModel = peersArray
            var now = new Date()
            root.lastUpdated = now.toLocaleTimeString(Qt.locale(), "hh:mm:ss")
        }
    }
}
