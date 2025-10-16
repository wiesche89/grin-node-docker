// Peers.qml
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 2.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // Daten (unverändert + neu: gefilterte Ansicht)
    property var peers: []              // volle Liste (vom Backend)
    property var filteredPeers: []      // gefilterte Ansicht
    property bool loading: false
    property string errorText: ""

    // UI-Konstanten (für saubere Button-Ausrichtung)
    readonly property int kCardH: 72
    readonly property int kBtnW: 96
    readonly property int kBtnH: 36
    readonly property int kPad: 10

    // --- Helpers (wie vorher) ---
    function flagsToString(flags) {
        switch (flags) {
        case 0: return "Healthy"
        case 1: return "Banned"
        case 2: return "Defunct"
        default: return "Unknown"
        }
    }
    function isBanned(flags) { return flags === 1 }
    function agoString(epochSecs) {
        if (!epochSecs || epochSecs <= 0) return ""
        var now = Math.floor(Date.now()/1000), d = Math.max(0, now - epochSecs)
        if (d < 60) return d + "s ago"
        if (d < 3600) return Math.floor(d/60) + "m ago"
        if (d < 86400) return Math.floor(d/3600) + "h ago"
        return Math.floor(d/86400) + "d ago"
    }
    function addrFromPeer(p) {
        if (!p) return "(unbekannte Adresse)"
        if (typeof p.addr === "string" && p.addr.length) return p.addr
        if (typeof p.address === "string" && p.address.length) return p.address
        if (typeof p.ip === "string" && p.port !== undefined) return p.ip + ":" + p.port
        return "(unbekannte Adresse)"
    }

    // flags kann Zahl oder String sein → in Zahl übersetzen für Filter/Anzeige
    function parseFlags(v) {
        if (v === undefined || v === null) return 0
        if (typeof v === "number") return v
        if (typeof v === "string") {
            var f = v.toLowerCase()
            if (f.indexOf("ban") !== -1) return 1
            if (f.indexOf("def") !== -1) return 2
            return 0
        }
        return 0
    }

    // --- Filter-Logik ---
    function applyFilter() {
        // 0=All,1=Healthy,2=Banned,3=Defunct
        var stateSel = stateFilter.currentIndex
        // 0=Alle,1=Banned,2=Unbanned
        var banSel   = banFilter.currentIndex
        var q = (searchField.text || "").toLowerCase().trim()

        var out = []
        for (var i=0; i<peers.length; ++i) {
            var p = peers[i]
            var flags = parseFlags(p.flags)

            // Status
            if (stateSel === 1 && flags !== 0) continue
            if (stateSel === 2 && flags !== 1) continue
            if (stateSel === 3 && flags !== 2) continue

            // Ban
            var banned = (flags === 1)
            if (banSel === 1 && !banned) continue
            if (banSel === 2 && banned) continue

            // Textsuche in addr / UA
            if (q.length) {
                var addr = addrFromPeer(p).toLowerCase()
                var ua = (p.userAgent ? String(p.userAgent) : "").toLowerCase()
                if (addr.indexOf(q) === -1 && ua.indexOf(q) === -1) continue
            }

            out.push(p)
        }
        filteredPeers = out
    }

    // --- Dark Button (wie vorher) ---
    Component {
        id: darkButton
        Button {
            id: control
            property color bg: hovered ? "#3a3a3a" : "#2b2b2b"
            property color fg: enabled ? "white" : "#777"
            flat: true
            padding: 10
            implicitWidth: kBtnW
            implicitHeight: kBtnH
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

    // --- Layout ---
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

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
                id: refreshBtn
                sourceComponent: darkButton
                onLoaded: {
                    item.text = loading ? "… Lädt" : "↻ Refresh"
                    item.enabled = !loading
                    item.onClicked.connect(refresh)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            BusyIndicator { running: loading; visible: loading; Layout.preferredHeight: 22; Layout.preferredWidth: 22 }
            Label {
                text: errorText.length
                      ? errorText
                      : (loading ? "Lade Peers …" : (filteredPeers.length + " / " + peers.length + " Peers"))
                color: errorText.length ? "#ff8080" : "#aaa"
                font.pixelSize: 13
                elide: Label.ElideRight
                Layout.fillWidth: true
            }
            Switch {
                id: autoRefresh
                text: "Auto"
                checked: false
                ToolTip.visible: hovered
                ToolTip.text: "Alle 10s aktualisieren"
            }
        }

        // ---------- Filterleiste ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label { text: "Status:"; color: "#bbb"; font.pixelSize: 12 }
            ComboBox {
                id: stateFilter
                model: ["All", "Healthy", "Banned", "Defunct"]
                implicitWidth: 140
                onCurrentIndexChanged: applyFilter()
            }

            Label { text: "Ban:"; color: "#bbb"; font.pixelSize: 12 }
            ComboBox {
                id: banFilter
                model: ["Alle", "Banned", "Unbanned"]
                implicitWidth: 140
                onCurrentIndexChanged: applyFilter()
            }

            Item { Layout.fillWidth: true } // Spacer

            TextField {
                id: searchField
                placeholderText: "Suche Adresse oder UA…"
                Layout.preferredWidth: 260
                onTextChanged: applyFilter()
            }
            Loader {
                sourceComponent: darkButton
                onLoaded: {
                    item.text = "✕ Clear"
                    item.onClicked.connect(function() { searchField.text = "" })
                }
            }
        }

        // ---------- Liste ----------
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                model: filteredPeers
                spacing: 6

                delegate: Rectangle {
                    width: parent ? parent.width : 800
                    height: kCardH
                    radius: 8
                    color: hovered ? "#2e2e2e" : "#242424"

                    // p ist der JSON-Eintrag aus PeerData::toJson()
                    property var p: modelData
                    property string addrStr: addrFromPeer(p)
                    property int flagsVal: {
                        if (p.flags === undefined || p.flags === null) return 0;
                        if (typeof p.flags === "number") return p.flags;
                        if (typeof p.flags === "string") {
                            var f = p.flags.toLowerCase();
                            if (f.indexOf("ban") !== -1) return 1;
                            if (f.indexOf("def") !== -1) return 2;
                            return 0;
                        }
                        return 0;
                    }
                    property bool banned: isBanned(flagsVal)
                    property string stateStr: flagsToString(flagsVal)

                    border.color: banned ? "#8a2f2f" : "#333"
                    border.width: 1

                    property bool hovered: false
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onEntered: parent.hovered = true
                        onExited: parent.hovered = false
                    }

                    // Inhalt: links Info, rechts fixer Button → keine Unebenheiten
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: kPad
                        spacing: 12

                        // Linke Spalte (füllt)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                text: addrStr.length ? addrStr : "(unbekannte Adresse)"
                                color: "white"
                                font.pixelSize: 15
                                elide: Label.ElideRight
                            }
                            RowLayout {
                                spacing: 12
                                Label { text: "State: " + stateStr; color: "#aaa"; font.pixelSize: 12 }
                                Label {
                                    text: p.userAgent ? ("UA: " + p.userAgent) : ""
                                    visible: !!p.userAgent
                                    color: "#aaa"; font.pixelSize: 12
                                }
                                Label {
                                    text: (p.lastConnected > 0) ? ("Seen: " + agoString(p.lastConnected)) : ""
                                    visible: p.lastConnected > 0
                                    color: "#aaa"; font.pixelSize: 12
                                }
                            }
                        }

                        // Fester Zwischenraum
                        Item { width: 8; height: 1 }

                        // Rechte Spalte: Button (fixe Breite/Höhe, rechtsbündig)
                        Loader {
                            Layout.preferredWidth: kBtnW
                            Layout.minimumWidth: kBtnW
                            Layout.maximumWidth: kBtnW
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            sourceComponent: darkButton
                            onLoaded: {
                                item.text = banned ? "Unban" : "Ban"
                                item.enabled = !loading && addrStr.length
                                item.width = kBtnW
                                item.height = kBtnH
                                item.Layout.preferredWidth = kBtnW
                                item.Layout.minimumWidth = kBtnW
                                item.Layout.maximumWidth = kBtnW
                                item.Layout.alignment = Qt.AlignRight | Qt.AlignVCenter
                                item.onClicked.connect(function() {
                                    item.enabled = false
                                    if (banned) nodeOwnerApi.unbanPeerAsync(addrStr)
                                    else        nodeOwnerApi.banPeerAsync(addrStr)
                                })
                            }
                        }
                    }
                }

                // Leerer Zustand + Filterhinweis
                footer: Item {
                    width: 1
                    height: (filteredPeers.length === 0 && !loading) ? 64 : 0
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Label {
                            text: peers.length > 0
                                  ? "Keine Peers für die aktuelle Filterung."
                                  : "Keine Peers gefunden."
                            color: "#777"
                        }
                        Loader {
                            visible: peers.length > 0
                            sourceComponent: darkButton
                            onLoaded: {
                                item.text = "Filter zurücksetzen"
                                item.onClicked.connect(function() {
                                    stateFilter.currentIndex = 0
                                    banFilter.currentIndex = 0
                                    searchField.text = ""
                                })
                            }
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 6; radius: 3; color: "#606060"; opacity: 0.4 }
            }
        }
    }

    // --- Verbindungen (dein Signal bleibt) ---
    Connections {
        target: nodeOwnerApi

        function onGetPeersFinishedQml(list) {
            loading = false
            errorText = ""
            // exakt wie bei dir (bewahrt das bisherige Verhalten):
            peers = Array.isArray(list) ? list : []
            applyFilter() // ← jetzt Filter anwenden
            if (refreshBtn.item) { refreshBtn.item.text = "↻ Refresh"; refreshBtn.item.enabled = true }
        }

        function onBanPeerFinished(result) {
            var ok = (typeof result === "object") ? !!result.ok
                   : (typeof result === "boolean") ? result : false
            if (ok) refresh(); else { loading = false; errorText = "Ban fehlgeschlagen" }
        }
        function onUnbanPeerFinished(result) {
            var ok = (typeof result === "object") ? !!result.ok
                   : (typeof result === "boolean") ? result : false
            if (ok) refresh(); else { loading = false; errorText = "Unban fehlgeschlagen" }
        }
    }

    // --- Aktionen (wie vorher) ---
    function refresh() {
        loading = true
        errorText = ""
        if (refreshBtn.item) { refreshBtn.item.text = "… Lädt"; refreshBtn.item.enabled = false }
        nodeOwnerApi.getPeersAsync("")   // optionaler Filter leer
    }

    // Filter neu anwenden wenn peers geändert werden (failsafe)
    onPeersChanged: applyFilter()

    Timer { interval: 10000; repeat: true; running: autoRefresh.checked; onTriggered: refresh() }
    Component.onCompleted: {
        // Filter definierter Startzustand
        if (stateFilter) stateFilter.currentIndex = 0
        if (banFilter)   banFilter.currentIndex = 0
        refresh()
    }
}
