import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: root
    visible: true
    width: 1700
    height: 1024
    title: "GrinNode"
    color: "#1e1e1e"

    // 🔹 Hintergrundbild immer sichtbar
    Image {
        anchors.fill: parent
        source: "qrc:/res/media/grin-node/image_10.jpg"
        //opacity: 0.3

        // Glanz darüberlegen
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#40FFFFFF" }  // leichtes Weiß
                GradientStop { position: 0.5; color: "#00FFFFFF" }  // durchsichtig
                GradientStop { position: 1.0; color: "#40FFFFFF" }
            }
        }
    }

    // 🔹 Gesamtes Layout über dem Hintergrund
    RowLayout {
        anchors.fill: parent
        spacing: 0
        z: 1

        // ---------------- Sidebar ----------------
        Rectangle {
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            color: "#2d2d2d"
            opacity: 0.7          // halbtransparent
            radius: 4

            Column {
                anchors.fill: parent
                anchors.margins: 10
                anchors.topMargin: 80
                spacing: 15

                SidebarButton {
                    text: "Home"
                    onClicked: root.currentIndex = 0
                }
                SidebarButton {
                    text: "Map"
                    onClicked: root.currentIndex = 1
                }
                SidebarButton {
                    text: "Peers"
                    onClicked: root.currentIndex = 2
                }
                SidebarButton {
                    text: "Transaction"
                    onClicked: root.currentIndex = 3
                }
                SidebarButton {
                    text: "Chain"
                    onClicked: root.currentIndex = 4
                }
            }
        }

        // ---------------- Hauptbereich ----------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1e1e1e"

            // 👉 Dynamische Transparenz: wenn Peers aktiv (Index 1) -> weniger transparent
            opacity: root.currentIndex === 1 ? 0.85 : 0.7

            StackLayout {
                id: stack
                anchors.fill: parent
                currentIndex: root.currentIndex

                Home {
                    id: homePage            // <— wichtig
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
                Map         { Layout.fillWidth: true; Layout.fillHeight: true }
                Peers {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // nur laden/aktualisieren, wenn Node wirklich läuft
                    //nodeRunning: true
                }
                Transaction { Layout.fillWidth: true; Layout.fillHeight: true }
                Chain       { Layout.fillWidth: true; Layout.fillHeight: true }
            }
        }
    }

    // ---------------- Eigene Property ----------------
    property int currentIndex: 0
}
