import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 2.15
import QtQuick.Window 2.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true
    property bool useDummyData: true        // 🔹 zum Testen aktivieren
    property var peers: []                  // 🔹 Peer-Liste

    signal refreshRequested()
    signal banRequested(string addr)
    signal unbanRequested(string addr)

    // ---------------------------------------------
    // Custom Dark Components
    // ---------------------------------------------
    Component {
        id: darkButtonComponent
        Button {
            id: control
            property color bg: hovered ? "#3a3a3a" : "#2b2b2b"
            property color fg: enabled ? "white" : "#777"
            flat: true
            padding: 10

            background: Rectangle {
                radius: 6
                color: control.down ? "#2f2f2f" : control.bg
                border.color: control.down ? "#e0c045" : "#555"
                border.width: 1
            }
            contentItem: Text {
                text: control.text
                color: control.fg
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    // ---------------------------------------------
    // Layout
    // ---------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // 🔹 Titelzeile
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: "Peers"
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.fillWidth: true
            }

            Loader {
                id: refreshButton
                sourceComponent: darkButtonComponent
                onLoaded: {
                    item.text = "↻ Refresh"
                    item.onClicked.connect(function() {
                        if (root.useDummyData)
                            root.loadDummyPeers()
                        else
                            root.refreshRequested()
                    })
                }
            }
        }

        // 🔹 Scrollbare Peer-Liste
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: peerList
                model: peers
                spacing: 6
                delegate: Rectangle {
                    width: parent.width
                    height: 60
                    radius: 8
                    color: hovered ? "#2e2e2e" : "#242424"
                    border.color: "#333"
                    border.width: 1

                    property bool hovered: false
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.hovered = true
                        onExited: parent.hovered = false
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Label {
                            text: modelData.address
                            color: "white"
                            font.pixelSize: 15
                            Layout.fillWidth: true
                        }

                        Label {
                            text: "State: " + modelData.state
                            color: "#aaa"
                            font.pixelSize: 13
                        }

                        Loader {
                            sourceComponent: darkButtonComponent
                            onLoaded: {
                                item.text = modelData.banned ? "Unban" : "Ban"
                                item.onClicked.connect(function() {
                                    if (modelData.banned)
                                        root.unbanRequested(modelData.address)
                                    else
                                        root.banRequested(modelData.address)
                                })
                            }
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: "#606060"
                    opacity: 0.4
                }
            }
        }
    }

    // ---------------------------------------------
    // Dummy Daten laden
    // ---------------------------------------------
    function loadDummyPeers() {
        peers = [
            { address: "192.168.1.12:3414", state: "Connected", banned: false },
            { address: "88.99.23.42:3414",  state: "Banned",    banned: true },
            { address: "10.0.0.3:3414",     state: "Connected", banned: false },
            { address: "45.76.11.5:3414",   state: "Disconnected", banned: false },
            { address: "peer.grin.mw:3414", state: "Connected", banned: false }
        ]
    }

    // ---------------------------------------------
    // Externe Callbacks aus C++
    // ---------------------------------------------
    function onGetPeersFinished(result) {
        if (result.ok)
            peers = result.value
        else
            console.log("getPeers failed:", result.error)
    }

    function onBanPeerFinished(result) {
        if (result.ok) {
            console.log("Peer banned")
            if (root.useDummyData) root.loadDummyPeers()
        } else {
            console.log("banPeer failed:", result.error)
        }
    }

    function onUnbanPeerFinished(result) {
        if (result.ok) {
            console.log("Peer unbanned")
            if (root.useDummyData) root.loadDummyPeers()
        } else {
            console.log("unbanPeer failed:", result.error)
        }
    }

    // ---------------------------------------------
    // Initial
    // ---------------------------------------------
    Component.onCompleted: {
        if (useDummyData)
            loadDummyPeers()
        else
            refreshRequested()
    }
}
