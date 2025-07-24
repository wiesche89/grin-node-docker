import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: root
    visible: true
    width: 1700
    height: 1024
    title: "GrinMesh"
    color: "#1e1e1e"

    // 🔹 Hintergrundbild immer sichtbar
    Image {
        anchors.fill: parent
        source: "qrc:/res/media/image3.jpg"
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
                    text: "Peers"
                    onClicked: root.currentIndex = 1
                }
                SidebarButton {
                    text: "Transaction"
                    onClicked: root.currentIndex = 2
                }
                SidebarButton {
                    text: "Chain"
                    onClicked: root.currentIndex = 3
                }
                SidebarButton {
                    text: "Header"
                    onClicked: root.currentIndex = 4
                }
                SidebarButton {
                    text: "Block"
                    onClicked: root.currentIndex = 5
                }
                SidebarButton {
                    text: "Kernel"
                    onClicked: root.currentIndex = 6
                }
                SidebarButton {
                    text: "Output"
                    onClicked: root.currentIndex = 7
                }
                SidebarButton {
                    text: "Pool"
                    onClicked: root.currentIndex = 8
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

                Home        { Layout.fillWidth: true; Layout.fillHeight: true }
                Peers       { Layout.fillWidth: true; Layout.fillHeight: true }
                Transaction { Layout.fillWidth: true; Layout.fillHeight: true }
                Chain       { Layout.fillWidth: true; Layout.fillHeight: true }
                Header      { Layout.fillWidth: true; Layout.fillHeight: true }
                Block       { Layout.fillWidth: true; Layout.fillHeight: true }
                Kernel      { Layout.fillWidth: true; Layout.fillHeight: true }
                Output      { Layout.fillWidth: true; Layout.fillHeight: true }
                Pool        { Layout.fillWidth: true; Layout.fillHeight: true }
            }
        }

    }

    // ---------------- Eigene Property ----------------
    property int currentIndex: 0
}
