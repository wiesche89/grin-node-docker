import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.1 as QtSettings

ApplicationWindow {
    id: root
    visible: true
    property real usableScreenWidth: (Qt.application.primaryScreen ? Qt.application.primaryScreen.availableGeometry.width : Screen.width)
    property real usableScreenHeight: (Qt.application.primaryScreen ? Qt.application.primaryScreen.availableGeometry.height : Screen.height)
    width: Math.min(usableScreenWidth, 1700)
    height: Math.min(usableScreenHeight, 1024)
    minimumWidth: 360
    minimumHeight: 600
    title: "GrinNode"
    color: "#1e1e1e"

    property bool compactLayout: width < 900
    property var pageTitles: ["Home", "Map", "Peers", "Transaction", "Chain", "Settings"]
    onCompactLayoutChanged: if (!compactLayout && sidebarDrawer.opened) sidebarDrawer.close()

    ListModel {
        id: navigationModel
        ListElement { title: "Home"; index: 0 }
        ListElement { title: "Map"; index: 1 }
        ListElement { title: "Peers"; index: 2 }
        ListElement { title: "Transaction"; index: 3 }
        ListElement { title: "Chain"; index: 4 }
        ListElement { title: "Settings"; index: 5 }
    }

    QtSettings.Settings {
        id: appSettings
        fileName: "grin-node-settings.ini"
        property string controllerUrlOverride: ""
    }

    header: ToolBar {
        visible: root.compactLayout
        implicitHeight: visible ? 56 : 0

        RowLayout {
            anchors.fill: parent
            spacing: 8

            ToolButton {
                text: "\u2630"
                font.pixelSize: 24
                onClicked: sidebarDrawer.open()
            }

            Label {
                text: root.pageTitles[root.currentIndex]
                Layout.fillWidth: true
                font.pixelSize: 18
                elide: Label.ElideRight
                color: "white"
            }
        }
    }

    Drawer {
        id: sidebarDrawer
        edge: Qt.LeftEdge
        modal: true
        enabled: root.compactLayout
        interactive: root.compactLayout
        width: Math.min(parent.width * 0.7, 260)
        height: parent.height
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#2d2d2d"; opacity: 0.9 }

        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 15

            Repeater {
                model: navigationModel
                delegate: SidebarButton {
                    width: parent.width
                    text: title
                    onClicked: {
                        root.currentIndex = index
                        sidebarDrawer.close()
                    }
                }
            }
        }
    }

    // Background image with soft gradient overlay
    Image {
        anchors.fill: parent
        source: "qrc:/res/media/grin-node/image_10.jpg"
        fillMode: Image.PreserveAspectCrop

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#40FFFFFF" }
                GradientStop { position: 0.5; color: "#00FFFFFF" }
                GradientStop { position: 1.0; color: "#40FFFFFF" }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        z: 1

        // Sidebar for large layouts
        Rectangle {
            Layout.preferredWidth: root.compactLayout ? 0 : 200
            Layout.minimumWidth: root.compactLayout ? 0 : 200
            Layout.fillHeight: true
            visible: !root.compactLayout
            color: "#2d2d2d"
            opacity: 0.7
            radius: 4

            Column {
                anchors.fill: parent
                anchors.margins: 10
                anchors.topMargin: 80
                spacing: 15

                Repeater {
                    model: navigationModel
                    delegate: SidebarButton {
                        text: title
                        onClicked: root.currentIndex = index
                    }
                }
            }
        }

        // Main content stack
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1e1e1e"
            opacity: root.currentIndex === 1 ? 0.85 : 0.7

            StackLayout {
                id: stack
                anchors.fill: parent
                currentIndex: root.currentIndex

                Home {
                    id: homePage
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    compactLayout: root.compactLayout
                    settingsStore: appSettings
                }
                Map {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    compactLayout: root.compactLayout
                }
                Peers {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    nodeRunning: homePage.nodeRunning
                    compactLayout: root.compactLayout
                }
                Transaction {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    nodeRunning: homePage.nodeRunning
                    compactLayout: root.compactLayout
                }
                Chain {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    nodeRunning: homePage.nodeRunning
                    compactLayout: root.compactLayout
                }
                Settings {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    compactLayout: root.compactLayout
                    settingsStore: appSettings
                }
            }
        }
    }

    property int currentIndex: 0
}
