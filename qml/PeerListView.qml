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

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header mit Titel und Uhrzeit nebeneinander
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Connected Peers"
                font.pixelSize: 20
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true } // Platzhalter

            Label {
                text: lastUpdated !== "" ? "Last Update: " + lastUpdated : ""
                font.pixelSize: 14
                color: "#aaaaaa"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
        }
        // Header row
        Rectangle {
            Layout.fillWidth: true
            height: 30
            color: "#444"
            radius: 4
            Row {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 16

                Label { text: "UserAgent"; color: "white"; font.bold: true; width: 160 }
                Label { text: "Height"; color: "white"; font.bold: true; width: 90; horizontalAlignment: Text.AlignHCenter }
                Label { text: "Addr"; color: "white"; font.bold: true; width: 180 }
                Label { text: "Version"; color: "white"; font.bold: true; width: 80; horizontalAlignment: Text.AlignHCenter }
                Label { text: "Dir"; color: "white"; font.bold: true; width: 90; horizontalAlignment: Text.AlignHCenter }
                Label { text: "Capabilities"; color: "white"; font.bold: true; width: 130 }
                Label { text: "Difficulty"; color: "white"; font.bold: true; width: 160 }
            }
        }

        ListView {
            id: peerList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 180
            Layout.preferredHeight: Math.max(220, Math.min(460, contentHeight + 40))
            Layout.maximumHeight: 520
            clip: true
            spacing: 2
            model: root.peersModel

            delegate: Rectangle {
                width: peerList.width
                height: 28
                color: index % 2 === 0 ? "#3a3a3a" : "#333333"

                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 16

                    Label { text: modelData.userAgent; color: "#ffffff"; width: 160; elide: Text.ElideRight }
                    Label { text: modelData.height; color: "#cccccc"; width: 90; horizontalAlignment: Text.AlignHCenter }
                    Label { text: modelData.addr.asString; color: "#cccccc"; width: 180; elide: Text.ElideRight }
                    Label { text: modelData.version.asString; color: "#cccccc"; width: 80; horizontalAlignment: Text.AlignHCenter }
                    Label { text: modelData.direction.asString; color: "#cccccc"; width: 90; horizontalAlignment: Text.AlignHCenter }
                    Label { text: modelData.capabilities.asString; color: "#cccccc"; width: 130; elide: Text.ElideRight }
                    Label { text: modelData.totalDifficulty.asString; color: "#cccccc"; width: 160; elide: Text.ElideRight }
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
