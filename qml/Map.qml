import QtQuick 2.15
import QtQuick.Controls 2.15
import Geo 1.0   // unser C++-Typ GeoLookup

Item {
    id: peersRoot
    z: 1000   // liegt über dem Hintergrund

    // Zoomstufe für Europa
    property int zoomLevel: 3
    property int tileSize: 256
    property int tilesPerRow: Math.pow(2, zoomLevel)

    // Liste der Marker
    property var peerMarkers: []

    GeoLookup {
        id: geoLookup
        // wenn C++ fertig ist mit den Koordinaten:
        onLookupFinished: function(coords) {
            var markers = []
            for (var i = 0; i < coords.length; ++i) {
                var lat = coords[i].lat
                var lon = coords[i].lon
                var tileCount = Math.pow(2, peersRoot.zoomLevel)
                var x = (lon + 180.0) / 360.0 * tileCount * peersRoot.tileSize
                var y = (1.0 - Math.log(Math.tan(lat * Math.PI / 180.0) + 1.0 / Math.cos(lat * Math.PI / 180.0)) / Math.PI) / 2.0 * tileCount * peersRoot.tileSize
                markers.push({ "x": x, "y": y })
            }
            peersRoot.peerMarkers = markers
        }
    }

    Flickable {
        id: mapView
        anchors.fill: parent
        contentWidth: tileSize * tilesPerRow
        contentHeight: tileSize * tilesPerRow
        clip: true

        Component.onCompleted: {
            var centerLat = 80;   // Deutschland
            var centerLon = -50;   // Deutschland

            var latRad = centerLat * Math.PI / 180.0;
            var tileCount = Math.pow(2, peersRoot.zoomLevel);

            var centerX = (centerLon + 180.0) / 360.0 * tileCount * peersRoot.tileSize;
            var centerY = (1.0 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2.0 * tileCount * peersRoot.tileSize;

            console.log("Center X:", centerX, "Center Y:", centerY);

            contentX = centerX - width / 2;
            contentY = centerY - height / 2;
        }

        // Karten-Kacheln
        Repeater {
            model: tilesPerRow * tilesPerRow
            delegate: Image {
                width: tileSize
                height: tileSize
                x: (index % tilesPerRow) * tileSize
                y: Math.floor(index / tilesPerRow) * tileSize
                source: {
                    const xIndex = index % tilesPerRow
                    const yIndex = Math.floor(index / tilesPerRow)
                    return "https://a.tile.openstreetmap.de/"
                           + zoomLevel + "/" + xIndex + "/" + yIndex + ".png"
                }
                fillMode: Image.PreserveAspectFit
                cache: true
            }
        }

        // Marker
        Repeater {
            model: peersRoot.peerMarkers
            delegate: Rectangle {
                width: 10
                height: 10
                radius: 8
                color: "yellow"
                border.color: "black"
                border.width: 2
                x: modelData.x - width / 2
                y: modelData.y - height / 2
            }
        }
    }

    // Verbindung zu deiner Node API
    Connections {
        target: nodeOwnerApi
        function onConnectedPeersUpdated(peersArray) {
            var ipList = []
            for (var i = 0; i < peersArray.length; i++) {
                var peer = peersArray[i]
                if (peer.addr && peer.addr.asString) {
                    // Beispiel: "123.45.67.89:13414"
                    var ipOnly = peer.addr.asString.split(":")[0]
                    if (ipList.indexOf(ipOnly) === -1) {
                        ipList.push(ipOnly)
                    }
                }
            }
            if (ipList.length > 0) {
                geoLookup.lookupIPs(ipList)
            } else {
                peersRoot.peerMarkers = []
            }
        }
    }
}

