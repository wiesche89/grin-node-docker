import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ----------------------------------------------------------------------
// PeerListView
// Simple tabular list of connected peers with horizontal scrolling
// and vertical ListView. Fully i18n-aware via injected i18n object.
// ----------------------------------------------------------------------
Rectangle {
    id: root
    color: "#2b2b2b"
    radius: 6
    border.color: "#555"
    border.width: 1

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------
    property var peersModel: []     // array of peer objects from backend
    property string lastUpdated: "" // formatted timestamp of last update
    property var i18n: null         // injected from Main.qml

    // ------------------------------------------------------------------
    // Typography / layout
    // ------------------------------------------------------------------
    // Similar logic as in StatusView: adapt font size to width
    property int headingFontSize: root.width < 640 ? 16 : 20
    property int dataFontSize:    root.width < 640 ? 12 : 16

    readonly property int columnSpacing: 16
    readonly property int headerPadding: 12

    // Logical column widths (do not depend on actual window size)
    readonly property int uaColumnWidth:          170
    readonly property int heightColumnWidth:      90
    readonly property int addrColumnWidth:        220
    readonly property int versionColumnWidth:     90
    readonly property int capabilitiesColumnWidth:220

    readonly property int totalLogicalWidth:
        uaColumnWidth
        + heightColumnWidth
        + addrColumnWidth
        + versionColumnWidth
        + capabilitiesColumnWidth
        + (4 * columnSpacing)
        + (2 * headerPadding)

    // ------------------------------------------------------------------
    // Local i18n helper
    // ------------------------------------------------------------------
    function tr(key, fallback) {
        if (!i18n || typeof i18n.t !== "function")
            return fallback || key

        var _ = i18n.language
        return i18n.t(key)
    }



    // ------------------------------------------------------------------
    // Main content layout
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // --------------------------------------------------------------
        // Header row: title + last updated label
        // --------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: tr("peerlist_title", "Connected Peers")
                font.pixelSize: headingFontSize
                font.bold: true
                color: "white"
            }

            Item { Layout.fillWidth: true }

            Label {
                text: lastUpdated !== ""
                      ? tr("peerlist_last_update_prefix", "Last update: ") + lastUpdated
                      : ""
                font.pixelSize: dataFontSize
                color: "#aaaaaa"
            }
        }

        // Divider line
        Rectangle {
            height: 1
            color: "#555"
            Layout.fillWidth: true
        }

        // --------------------------------------------------------------
        // Horizontal Flickable that contains table header + ListView
        // --------------------------------------------------------------
        Flickable {
            id: tableFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Only horizontal flicking, vertical handled by ListView
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            // Content width = width of the table, height = header + list
            contentWidth: tableColumn.width
            contentHeight: tableHeader.height + peerList.height + tableColumn.spacing

            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: tableColumn
                width: Math.max(totalLogicalWidth, tableFlick.width)
                spacing: 12

                // ------------------------------------------------------
                // Table header row
                // ------------------------------------------------------
                Rectangle {
                    id: tableHeader
                    width: tableColumn.width
                    height: 34
                    color: "#444"
                    radius: 4

                    Row {
                        anchors.fill: parent
                        anchors.margins: headerPadding
                        spacing: columnSpacing

                        Label {
                            text: tr("peerlist_col_useragent", "UserAgent")
                            color: "white"
                            font.bold: true
                            font.pixelSize: dataFontSize
                            width: uaColumnWidth
                            elide: Text.ElideRight
                        }
                        Label {
                            text: tr("peerlist_col_height", "Height")
                            color: "white"
                            font.bold: true
                            font.pixelSize: dataFontSize
                            width: heightColumnWidth
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Label {
                            text: tr("peerlist_col_addr", "Addr")
                            color: "white"
                            font.bold: true
                            font.pixelSize: dataFontSize
                            width: addrColumnWidth
                            elide: Text.ElideRight
                        }
                        Label {
                            text: tr("peerlist_col_version", "Version")
                            color: "white"
                            font.bold: true
                            font.pixelSize: dataFontSize
                            width: versionColumnWidth
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Label {
                            text: tr("peerlist_col_capabilities", "Capabilities")
                            color: "white"
                            font.bold: true
                            font.pixelSize: dataFontSize
                            width: capabilitiesColumnWidth
                            elide: Text.ElideRight
                        }
                    }
                }

                // ------------------------------------------------------
                // Peer list rows
                // ------------------------------------------------------
                ListView {
                    id: peerList
                    width: tableColumn.width
                    height: tableFlick.height - tableHeader.height - tableColumn.spacing
                    model: root.peersModel
                    clip: true
                    spacing: 2

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        width: peerList.width
                        height: 32
                        color: index % 2 === 0 ? "#3a3a3a" : "#333333"

                        Row {
                            anchors.fill: parent
                            anchors.margins: headerPadding
                            spacing: columnSpacing

                            Label {
                                text: modelData.userAgent
                                color: "#ffffff"
                                font.pixelSize: dataFontSize
                                width: uaColumnWidth
                                elide: Text.ElideRight
                            }
                            Label {
                                text: modelData.height
                                color: "#cccccc"
                                font.pixelSize: dataFontSize
                                width: heightColumnWidth
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Label {
                                text: modelData.addr.asString
                                color: "#cccccc"
                                font.pixelSize: dataFontSize
                                width: addrColumnWidth
                                elide: Text.ElideRight
                            }
                            Label {
                                text: modelData.version.asString
                                color: "#cccccc"
                                font.pixelSize: dataFontSize
                                width: versionColumnWidth
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Label {
                                text: modelData.capabilities.asString
                                color: "#cccccc"
                                font.pixelSize: dataFontSize
                                width: capabilitiesColumnWidth
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Backend connection: updates table content + lastUpdated label
    // ------------------------------------------------------------------
    Connections {
        target: nodeOwnerApi

        // Emitted by backend with full array of connected peers
        function onConnectedPeersUpdated(peersArray) {
            root.peersModel = peersArray
            var now = new Date()
            root.lastUpdated = now.toLocaleTimeString(Qt.locale(), "hh:mm:ss")
        }
    }
}
