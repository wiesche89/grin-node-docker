import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: "#2b2b2b"
    radius: 6
    border.color: "#555"
    border.width: 1

    property var peersModel: []
    property string lastUpdated: ""
    property int headingFontSize: 20
    property int bodyFontSize: 16

    readonly property int columnSpacing: 16
    readonly property int headerPadding: 12
    readonly property int uaColumnWidth: 170
    readonly property int heightColumnWidth: 90
    readonly property int addrColumnWidth: 220
    readonly property int versionColumnWidth: 90
    readonly property int capabilitiesColumnWidth: 220
    readonly property int tableContentWidth: uaColumnWidth + heightColumnWidth + addrColumnWidth
                                            + versionColumnWidth + capabilitiesColumnWidth
                                            + (4 * columnSpacing) + (2 * headerPadding)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Connected Peers"
                font.pixelSize: headingFontSize
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            }

            Item { Layout.fillWidth: true }

            Label {
                text: lastUpdated !== "" ? "Last Update: " + lastUpdated : ""
                font.pixelSize: bodyFontSize
                color: "#aaaaaa"
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            }
        }

        Flickable {
            id: horizontalScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            contentWidth: Math.max(tableContentWidth, width)
            contentHeight: height
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: tableColumn
                width: tableContentWidth
                height: horizontalScroll.height
                spacing: 12

                Rectangle {
                    id: tableHeader
                    width: parent.width
                    height: 34
                    color: "#444"
                    radius: 4

                    Row {
                        anchors.fill: parent
                        anchors.margins: headerPadding
                        spacing: columnSpacing

                        Label { text: "UserAgent"; color: "white"; font.bold: true; font.pixelSize: 16; width: uaColumnWidth }
                        Label { text: "Height"; color: "white"; font.bold: true; font.pixelSize: 16; width: heightColumnWidth; horizontalAlignment: Text.AlignHCenter }
                        Label { text: "Addr"; color: "white"; font.bold: true; font.pixelSize: 16; width: addrColumnWidth }
                        Label { text: "Version"; color: "white"; font.bold: true; font.pixelSize: 16; width: versionColumnWidth; horizontalAlignment: Text.AlignHCenter }
                        Label { text: "Capabilities"; color: "white"; font.bold: true; font.pixelSize: 16; width: capabilitiesColumnWidth }
                    }
                }

                ListView {
                    id: peerList
                    width: parent.width
                    height: Math.max(0, horizontalScroll.height - tableHeader.height - tableColumn.spacing)
                    clip: true
                    spacing: 2
                    model: root.peersModel
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        width: peerList.width
                        height: 32
                        color: index % 2 === 0 ? "#3a3a3a" : "#333333"

                        Row {
                            anchors.fill: parent
                            anchors.margins: headerPadding
                            spacing: columnSpacing

                            Label { text: modelData.userAgent; color: "#ffffff"; width: uaColumnWidth; elide: Text.ElideRight; font.pixelSize: 16 }
                            Label { text: modelData.height; color: "#cccccc"; width: heightColumnWidth; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 16 }
                            Label { text: modelData.addr.asString; color: "#cccccc"; width: addrColumnWidth; elide: Text.ElideRight; font.pixelSize: 16 }
                            Label { text: modelData.version.asString; color: "#cccccc"; width: versionColumnWidth; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 16 }
                            Label { text: modelData.capabilities.asString; color: "#cccccc"; width: capabilitiesColumnWidth; elide: Text.ElideRight; font.pixelSize: 16 }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: nodeOwnerApi
        function onConnectedPeersUpdated(peersArray) {
            root.peersModel = peersArray
            var now = new Date()
            root.lastUpdated = now.toLocaleTimeString(Qt.locale(), "hh:mm:ss")
        }
    }
}
