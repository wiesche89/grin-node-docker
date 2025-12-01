import QtQuick 2.15
import QtQuick.Controls 2.15
import Geo 1.0   // our C++ type GeoLookup

// =====================================================================
// Map page
// - Renders OpenStreetMap tiles
// - Shows markers for connected peers (via GeoLookup)
// - Language aware title via i18n.t(...)
// =====================================================================
Item {
    id: peersRoot

    // passed from Main.qml
    property bool compactLayout: false

    // i18n object from Main.qml (QtObject { id: i18n })
    property var i18n: null

    // Node manager from C++ (GrinNodeManager)
    property var nodeManager: null

    // draw above background image in Main.qml
    z: 1000

    // Zoom level for Europe/world
    property int zoomLevel: compactLayout ? 2 : 3

    // OSM tile size in pixels
    property int tileSize: 256

    // Number of tiles per row at this zoom level (2^zoom)
    property int tilesPerRow: Math.pow(2, zoomLevel)

    // Marker list: array of { x, y }
    property var peerMarkers: []

    // Lookup-Tabelle für IPs → wird bei Stop/Restart geleert
    property var ipList: []

    // Small helper for translated strings
    function tr(key, fallback) {
        return i18n ? i18n.t(key) : fallback
    }

    // -----------------------------------------------------------------
    // Geo lookup: converts IPs to lat/lon (C++ backend)
    // -----------------------------------------------------------------
    GeoLookup {
        id: geoLookup

        // C++ finished with coordinates
        onLookupFinished: function(coords) {
            var markers = []
            for (var i = 0; i < coords.length; ++i) {
                var lat = coords[i].lat
                var lon = coords[i].lon

                var tileCount = Math.pow(2, peersRoot.zoomLevel)

                // Web Mercator projection → tile pixel coordinates
                var x = (lon + 180.0) / 360.0 * tileCount * peersRoot.tileSize
                var y = (1.0 - Math.log(Math.tan(lat * Math.PI / 180.0)
                          + 1.0 / Math.cos(lat * Math.PI / 180.0)) / Math.PI)
                          / 2.0 * tileCount * peersRoot.tileSize

                markers.push({ "x": x, "y": y })
            }
            peersRoot.peerMarkers = markers
        }
    }

    // -----------------------------------------------------------------
    // Main map view (scrollable Flickable)
    // -----------------------------------------------------------------
    Flickable {
        id: mapView
        anchors.fill: parent
        contentWidth: tileSize * tilesPerRow
        contentHeight: tileSize * tilesPerRow
        clip: true

        // Center map roughly on Europe when component is ready
        Component.onCompleted: {
            var centerLat = 50.0      // ~central Europe
            var centerLon = 10.0      // ~Germany

            var latRad    = centerLat * Math.PI / 180.0
            var tileCount = Math.pow(2, peersRoot.zoomLevel)

            var centerX = (centerLon + 180.0) / 360.0 * tileCount * peersRoot.tileSize
            var centerY = (1.0 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI)
                          / 2.0 * tileCount * peersRoot.tileSize

            contentX = centerX - width  / 2
            contentY = centerY - height / 2
        }

        // -------------------- Map tiles (OSM) -------------------------
        Repeater {
            model: tilesPerRow * tilesPerRow

            delegate: Image {
                width: tileSize
                height: tileSize
                x: (index % tilesPerRow) * tileSize
                y: Math.floor(index / tilesPerRow) * tileSize
                source: {
                    var xIndex = index % tilesPerRow
                    var yIndex = Math.floor(index / tilesPerRow)
                    return "https://a.tile.openstreetmap.de/"
                           + zoomLevel + "/" + xIndex + "/" + yIndex + ".png"
                }
                fillMode: Image.PreserveAspectFit
                cache: true
            }
        }

        // -------------------- Peer markers ----------------------------
        Repeater {
            model: peersRoot.peerMarkers

            delegate: Rectangle {
                width: 10
                height: 10
                radius: 8
                color: "yellow"
                border.color: "black"
                border.width: 2

                // center marker on projected coordinate
                x: modelData.x - width  / 2
                y: modelData.y - height / 2
            }
        }
    }

    // -----------------------------------------------------------------
    // Overlay title (translated) – fixed in top-left corner
    // -----------------------------------------------------------------
    Rectangle {
        id: titleOverlay
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: compactLayout ? 8 : 16
        color: "#00000080"
        radius: 8
        border.color: "#333333"
        border.width: 1

        Text {
            id: titleLabel
            anchors.fill: parent
            anchors.margins: 6
            text: tr("map_title", "Network map")
            color: "white"
            font.pixelSize: compactLayout ? 14 : 16
            font.bold: true
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
        }
    }

    // -----------------------------------------------------------------
    // Connection to nodeOwnerApi: transform peers → IPs → geo lookup
    // -----------------------------------------------------------------
    Connections {
        target: nodeOwnerApi

        function onConnectedPeersUpdated(peersArray) {
            // Lookup-Tabelle neu aufbauen
            peersRoot.ipList = []
            var tmp = []

            for (var i = 0; i < peersArray.length; i++) {
                var peer = peersArray[i]
                if (peer.addr && peer.addr.asString) {
                    // Example: "123.45.67.89:13414"
                    var ipOnly = peer.addr.asString.split(":")[0]
                    if (tmp.indexOf(ipOnly) === -1) {
                        tmp.push(ipOnly)
                    }
                }
            }

            peersRoot.ipList = tmp

            if (peersRoot.ipList.length > 0) {
                geoLookup.lookupIPs(peersRoot.ipList)
            } else {
                peersRoot.peerMarkers = []
            }
        }
    }

    // -----------------------------------------------------------------
    // Listen to GrinNodeManager (nodeManager) and clear on stop/restart
    // -----------------------------------------------------------------
    Connections {
        target: nodeManager

        function onNodeStopped(kind) {
            peersRoot.ipList = []
            peersRoot.peerMarkers = []
        }


        function onNodeRestarted(kind) {
            peersRoot.ipList = []
            peersRoot.peerMarkers = []
        }
    }
}
