import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects    // für MultiEffect / DropShadow

Rectangle {
    id: root
    width: parent ? parent.width : 600
    height: childrenRect.height + 32   // Inhaltshöhe + 2x16 Margin
    color: "#2b2b2b"
    radius: 6
    border.color: "#555"
    border.width: 1

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 3
        shadowBlur: 0.6
        shadowColor: "#80000000"
    }

    // komplette Datenstruktur aus C++
    property var currentStatus: null
    // neue Property für die Uhrzeit
    property string lastUpdated: ""

    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        spacing: 12

        // Header mit Titel und Uhrzeit nebeneinander
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Node Status"
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

        Rectangle {
            height: 1
            color: "#555555"
            Layout.fillWidth: true
        }

        // Zwei Spalten nebeneinander
        RowLayout {
            Layout.fillWidth: true
            spacing: 40

            // Linke Spalte
            ColumnLayout {
                spacing: 6

                RowLayout {
                    Label { text: "Chain:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label { text: currentStatus ? currentStatus.chain : ""; color: "white"; Layout.fillWidth: true }
                }
                RowLayout {
                    Label { text: "Protocol Version:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label { text: currentStatus ? currentStatus.protocolVersion : ""; color: "white"; Layout.fillWidth: true }
                }
                RowLayout {
                    Label { text: "User Agent:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label {
                        text: currentStatus ? currentStatus.userAgent : ""
                        color: "white"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                RowLayout {
                    Label { text: "Sync Status:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label { text: currentStatus ? currentStatus.syncStatus : ""; color: "white"; Layout.fillWidth: true }
                }
                RowLayout {
                    Label { text: "Sync Info:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label { text: currentStatus ? currentStatus.syncInfo.jsonString : ""; color: "white"; Layout.fillWidth: true }
                }
            }

            // Rechte Spalte
            ColumnLayout {
                spacing: 6

                RowLayout {
                    Label { text: "Connections:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label { text: currentStatus ? currentStatus.connections : ""; color: "white"; Layout.fillWidth: true }
                }

                RowLayout {
                    Label { text: "Height:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label {
                        text: currentStatus && currentStatus.tip ? currentStatus.tip.height : ""
                        color: "white"
                        Layout.fillWidth: true
                    }
                }
                RowLayout {
                    Label { text: "Last Block:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label {
                        text: currentStatus && currentStatus.tip ? currentStatus.tip.lastBlockPushed : ""
                        color: "white"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                RowLayout {
                    Label { text: "Prev Block:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label {
                        text: currentStatus && currentStatus.tip ? currentStatus.tip.prevBlockToLast : ""
                        color: "white"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                RowLayout {
                    Label { text: "Total Difficulty:"; font.bold: true; color: "#dddddd"; Layout.preferredWidth: 130 }
                    Label {
                        text: currentStatus && currentStatus.tip ? currentStatus.tip.totalDifficulty : ""
                        color: "white"
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // Verbindung zum C++-Signal
    Connections {
        target: nodeOwnerApi
        function onStatusUpdated(statusObj) {
            root.currentStatus = statusObj
            // Uhrzeit setzen
            var now = new Date()
            var h = now.getHours().toString().padStart(2, "0")
            var m = now.getMinutes().toString().padStart(2, "0")
            var s = now.getSeconds().toString().padStart(2, "0")
            root.lastUpdated = h + ":" + m + ":" + s
        }
    }
}
