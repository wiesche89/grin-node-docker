// Main.qml
// -----------------------------------------------------------------------------
// Main application window for the Grin Node Controller UI
// - owns global settings (Qt.labs.settings)
// - owns global I18n instance (I18n.qml)
// - owns the central GrinNodeManager instance
// - hosts navigation, sidebar, and the page StackLayout
// -----------------------------------------------------------------------------

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQml 2.15
import QtCore 6.5 as QtCore
import Grin 1.0          // GrinNodeManager

ApplicationWindow {
    id: root
    visible: true
    property string umbrelHomeUrl: "http://umbrel.local"

    // -----------------------------------------------------------------
    // Window sizing
    // -----------------------------------------------------------------
    property real usableScreenWidth: (Qt.application.primaryScreen
                                      ? Qt.application.primaryScreen.availableGeometry.width
                                      : Screen.width)
    property real usableScreenHeight: (Qt.application.primaryScreen
                                       ? Qt.application.primaryScreen.availableGeometry.height
                                       : Screen.height)

    width: Math.min(usableScreenWidth, 1700)
    height: Math.min(usableScreenHeight, 1024)
    minimumWidth: 360
    minimumHeight: 600

    title: "GrinNode"
    color: "#1e1e1e"

    // -----------------------------------------------------------------
    // Layout / navigation state
    // -----------------------------------------------------------------
    property bool compactLayout: width < 900
    onCompactLayoutChanged: {
        // Close drawer automatically when switching to non-compact layout
        if (!compactLayout && sidebarDrawer.opened)
            sidebarDrawer.close()
    }

    // Index in the main StackLayout / navigation model
    property int currentIndex: 0

    // Navigation keys for page titles (resolved via i18n)
    property var navTitleKeys: [
        "nav_home",
        "nav_map",
        "nav_peers",
        "nav_tx",
        "nav_chain",
        "nav_explorer",
        "nav_utxo",
        "nav_price",
        "nav_wallet",
        "nav_settings"
    ]

    // -----------------------------------------------------------------
    // Persistent application settings
    // -----------------------------------------------------------------
    QtCore.Settings {
        id: appSettings

        category: "grin-node"
        location: "grin-node-settings.ini"

        property string controllerUrlOverride: ""
        property string languageCode: "en"
        property bool backgroundEnabled: true
        property string transactionHistoryJson: "[]"
    }

    property bool backgroundEnabled: appSettings.backgroundEnabled

    // -----------------------------------------------------------------
    // Global internationalization helper
    // -----------------------------------------------------------------
    I18n {
        id: i18n
        settingsStore: appSettings
    }

    // -----------------------------------------------------------------
    // Navigation model
    // -----------------------------------------------------------------
    ListModel {
        id: navigationModel
        ListElement { titleKey: "nav_home";     index: 0 }
        ListElement { titleKey: "nav_map";      index: 1 }
        ListElement { titleKey: "nav_peers";    index: 2 }
        ListElement { titleKey: "nav_tx";       index: 3 }
        ListElement { titleKey: "nav_chain";    index: 4 }
        ListElement { titleKey: "nav_explorer"; index: 5 }
        ListElement { titleKey: "nav_utxo";     index: 6 }
        ListElement { titleKey: "nav_price";    index: 7 }
        ListElement { titleKey: "nav_wallet";   index: 8 }
        ListElement { titleKey: "nav_settings"; index: 9 }
    }

    // -----------------------------------------------------------------
    // Central Grin node manager
    // -----------------------------------------------------------------
    GrinNodeManager {
        id: grinMgr

        // Base URL is computed in Home.qml and exposed as controllerApiUrl
        baseUrl: homePage.controllerApiUrl

        username: ""
        password: ""

    }

    // -----------------------------------------------------------------
    // Header for compact layouts (mobile / narrow window)
    // -----------------------------------------------------------------
    header: ToolBar {
        visible: root.compactLayout
        implicitHeight: visible ? 56 : 0

        RowLayout {
            anchors.fill: parent
            spacing: 8

            ToolButton {
                text: "\u2630" // simple “hamburger” icon
                font.pixelSize: 24
                onClicked: sidebarDrawer.open()
            }

            Label {
                Layout.fillWidth: true
                font.pixelSize: 18
                elide: Label.ElideRight
                color: "white"

                text: {
                    var key = navTitleKeys[root.currentIndex]
                    return i18n ? i18n.t(key) : key
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Drawer navigation for compact layouts
    // -----------------------------------------------------------------
    Drawer {
        id: sidebarDrawer
        edge: Qt.LeftEdge
        modal: true
        enabled: root.compactLayout
        interactive: root.compactLayout
        width: Math.min(parent.width * 0.7, 260)
        height: parent.height
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: "#2d2d2d"
            opacity: root.backgroundEnabled ? 0.9 : 1.0
        }

        Flickable {
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: drawerNavColumn.implicitHeight + 40
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: drawerNavColumn
                x: 20
                y: 20
                width: sidebarDrawer.width - 40
                spacing: 15

                SidebarButton {
                    width: parent.width
                    text: "\u2190 Umbrel"
                    onClicked: {
                        Qt.openUrlExternally(root.umbrelHomeUrl)
                        sidebarDrawer.close()
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#4a4a4a"
                    opacity: 0.8
                }

                Repeater {
                    model: navigationModel
                    delegate: SidebarButton {
                        width: parent.width
                        text: i18n ? i18n.t(titleKey) : titleKey
                        onClicked: {
                            root.currentIndex = index
                            sidebarDrawer.close()
                        }
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Background image with soft gradient overlay
    // -----------------------------------------------------------------
    Image {
        visible: root.backgroundEnabled
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

    // -----------------------------------------------------------------
    // Main layout: left sidebar (desktop) + content stack
    // -----------------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        spacing: 0
        z: 1

        // Sidebar for non-compact layouts
        Rectangle {
            Layout.preferredWidth: root.compactLayout ? 0 : 200
            Layout.minimumWidth: root.compactLayout ? 0 : 200
            Layout.fillHeight: true
            visible: !root.compactLayout
            color: "#2d2d2d"
            opacity: root.backgroundEnabled ? 0.7 : 1.0

            Flickable {
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: desktopNavColumn.implicitHeight + 90
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                Column {
                    id: desktopNavColumn
                    x: 10
                    y: 80
                    width: parent.width - 20
                    spacing: 15

                    SidebarButton {
                        width: parent.width
                        text: "\u2190 Umbrel"
                        onClicked: Qt.openUrlExternally(root.umbrelHomeUrl)
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: "#4a4a4a"
                        opacity: 0.8
                    }

                    Repeater {
                        model: navigationModel
                        delegate: SidebarButton {
                            width: parent.width
                            text: i18n ? i18n.t(titleKey) : titleKey
                            onClicked: root.currentIndex = index
                        }
                    }
                }
            }
        }

        // Main content area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1e1e1e"
            // Slightly more transparent for Map page, darker for others
            opacity: root.backgroundEnabled
                     ? (root.currentIndex === 1 ? 0.85 : 0.7)
                     : 1.0

            StackLayout {
                id: stack
                anchors.fill: parent
                currentIndex: root.currentIndex

                // -----------------------------------------------------
                // Home page - node dashboard
                // -----------------------------------------------------
                Home {
                    id: homePage
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    compactLayout: root.compactLayout
                    settingsStore: appSettings
                    nodeManager: grinMgr
                    i18n: i18n
                }

                // -----------------------------------------------------
                // Map page - network visualization
                // -----------------------------------------------------
                Map {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    compactLayout: root.compactLayout
                    nodeManager: grinMgr
                    i18n: i18n
                }

                // -----------------------------------------------------
                // Peers page - connected peers list
                // -----------------------------------------------------
                Peers {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    nodeRunning: homePage.nodeRunning
                    compactLayout: root.compactLayout
                    nodeManager: grinMgr
                    i18n: i18n
                }

                // -----------------------------------------------------
                // Transaction page - mempool / unconfirmed transactions
                // -----------------------------------------------------
                Transaction {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    nodeRunning: homePage.nodeRunning
                    compactLayout: root.compactLayout
                    nodeManager: grinMgr
                    settingsStore: appSettings
                    i18n: i18n
                }

                // -----------------------------------------------------
                // Chain page - chain state / sync info
                // -----------------------------------------------------
                Chain {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    nodeRunning: homePage.nodeRunning
                    compactLayout: root.compactLayout
                    nodeManager: grinMgr
                    i18n: i18n
                }

                // -----------------------------------------------------
                // Explorer page - direct block/header/kernel lookups
                // -----------------------------------------------------
                Explorer {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    compactLayout: root.compactLayout
                    i18n: i18n
                }

                // -----------------------------------------------------
                // UTXO page - unspent output explorer
                // -----------------------------------------------------
                Utxo {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    compactLayout: root.compactLayout
                    i18n: i18n
                }

                // -----------------------------------------------------
                // Price page - grin price analysis
                // -----------------------------------------------------
                Price {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    compactLayout: root.compactLayout
                    priceSource: priceAnalysis
                    i18n: i18n
                    pageActive: root.currentIndex === 7
                }

                // -----------------------------------------------------
                // Wallet page - share controller credentials
                // -----------------------------------------------------
                Wallet {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    compactLayout: root.compactLayout
                    nodeManager: grinMgr
                    i18n: i18n
                }

                // -----------------------------------------------------
                // Settings page - controller URL, language, chain cleanup
                // -----------------------------------------------------
                Settings {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    compactLayout: root.compactLayout
                    settingsStore: appSettings
                    nodeManager: grinMgr
                    nodeRunning: homePage.nodeRunning
                    i18n: i18n
                    rustNodeRunning:  homePage.nodeState === "rust"
                    grinppNodeRunning: homePage.nodeState === "grinpp"
                }
            }
        }
    }
}
