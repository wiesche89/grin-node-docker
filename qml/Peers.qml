// Peers.qml
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 2.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // ---------------------------------------------------
    // Public state
    // ---------------------------------------------------
    property bool nodeRunning: false
    property var peers: []               // raw peers from backend
    property var filteredPeers: []       // peers after filtering
    property bool loading: false
    property string errorText: ""
    property var uaOptions: ["All"]      // gets rebuilt dynamically from peers
    property bool compactLayout: false
    property string peersStatusText: "Loading peers..."

    // Sizes
    readonly property int kCardH: 72
    readonly property int kBtnW: 96
    readonly property int kBtnH: 36
    readonly property int kPad: 10

    // ---------------------------------------------------
    // Helpers
    // ---------------------------------------------------
    function flagsToString(flags) {
        switch (flags) {
        case 0: return "Healthy"
        case 1: return "Banned"
        case 2: return "Defunct"
        default: return "Unknown"
        }
    }

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

    function isBanned(flags) { return parseFlags(flags) === 1 }

    function agoString(epochSecs) {
        if (!epochSecs || epochSecs <= 0) return ""
        var now = Math.floor(Date.now()/1000)
        var d = Math.max(0, now - epochSecs)
        if (d < 60) return d + "s ago"
        if (d < 3600) return Math.floor(d/60) + "m ago"
        if (d < 86400) return Math.floor(d/3600) + "h ago"
        return Math.floor(d/86400) + "d ago"
    }

    function addrFromPeer(p) {
        if (!p) return "(unknown address)"
        if (typeof p.addr === "string" && p.addr.length) return p.addr
        if (typeof p.address === "string" && p.address.length) return p.address
        if (typeof p.ip === "string" && p.port !== undefined) return p.ip + ":" + p.port
        return "(unknown address)"
    }

    function apiAddrFromPeer(p) {
        if (!p) return ""
        if (typeof p.addr === "string" && p.addr.length) return p.addr
        if (typeof p.address === "string" && p.address.length) return p.address
        if (typeof p.ip === "string" && p.port !== undefined) return p.ip + ":" + p.port
        return ""
    }

    // robust UA extraction across differently named fields
    function uaFromPeer(p) {
        if (!p) return ""
        if (typeof p.userAgent === "string" && p.userAgent.length) return p.userAgent
        if (typeof p.user_agent === "string" && p.user_agent.length) return p.user_agent
        if (typeof p.ua === "string" && p.ua.length) return p.ua
        if (typeof p.agent === "string" && p.agent.length) return p.agent
        if (p.capabilities && typeof p.capabilities.userAgent === "string" && p.capabilities.userAgent.length)
            return p.capabilities.userAgent
        return ""
    }

    function updatePeerArray(list) {
        var arr = Array.isArray(list) ? list : []
        peers.splice(0, peers.length)
        for (var i = 0; i < arr.length; ++i) {
            peers.push(arr[i])
        }
    }

    // ---------------------------------------------------
    // UA options (dropdown) builder
    // ---------------------------------------------------
    function rebuildUaOptions() {
        var set = {}
        for (var i = 0; i < peers.length; ++i) {
            var ua = uaFromPeer(peers[i])
            if (ua) set[ua] = true
        }
        var arr = Object.keys(set).sort()
        if (arr.length > 300) arr = arr.slice(0, 300)   // safety limit
        uaOptions = ["All"].concat(arr)
        if (uaFilter.currentIndex >= uaOptions.length) uaFilter.currentIndex = 0
    }

    // ---------------------------------------------------
    // Filtering
    // ---------------------------------------------------
    function applyFilter() {
        var stateSel = stateFilter.currentIndex     // 0 All, 1 Healthy, 2 Banned, 3 Defunct
        var banSel   = banFilter.currentIndex       // 0 All, 1 Banned, 2 Unbanned
        var uaSel    = uaFilter.currentIndex        // 0 All, >0 exact UA match
        var q = (searchField.text || "").toLowerCase().trim()

        var out = []
        for (var i = 0; i < peers.length; ++i) {
            var p = peers[i]
            var flags = parseFlags(p.flags)
            var ua = uaFromPeer(p)
            var banned = (flags === 1)

            // by state
            if (stateSel === 1 && flags !== 0) continue
            if (stateSel === 2 && flags !== 1) continue
            if (stateSel === 3 && flags !== 2) continue

            // by banned/unbanned
            if (banSel === 1 && !banned) continue
            if (banSel === 2 &&  banned) continue

            // by "only with UA"
            if (uaMustExist.checked && (!ua || ua.length === 0)) continue

            // by UA dropdown exact match
            if (uaSel > 0) {
                var want = uaOptions[uaSel]
                if (ua !== want) continue
            }

            // free-text search across address OR UA
            if (q.length) {
                var addr = addrFromPeer(p).toLowerCase()
                var uaLower = ua.toLowerCase()
                if (addr.indexOf(q) === -1 && uaLower.indexOf(q) === -1) continue
            }

            out.push(p)
        }
        filteredPeers = out
    }

    function updatePeersStatusText() {
        if (errorText.length) {
            peersStatusText = errorText
        } else if (loading) {
            peersStatusText = "Loading peers..."
        } else {
            peersStatusText = filteredPeers.length + " / " + peers.length + " peers"
        }
    }

    onLoadingChanged: updatePeersStatusText()
    onErrorTextChanged: updatePeersStatusText()
    onFilteredPeersChanged: updatePeersStatusText()
    // ---------------------------------------------------
    // Dark button component
    // ---------------------------------------------------
    Component {
        id: darkButton
        Button {
            id: control
            property color bg: hovered ? "#3a3a3a" : "#2b2b2b"
            property color fg: enabled ? "white" : "#777"
            flat: true
            padding: 10
            implicitWidth: root.kBtnW
            implicitHeight: root.kBtnH

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

    // ---------------------------------------------------
    // Layout
    // ---------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: compactLayout ? 12 : 20
        spacing: 14

        // Header
        GridLayout {
            Layout.fillWidth: true
            columns: compactLayout ? 1 : 2
            columnSpacing: 10
            rowSpacing: 6

            Label {
                text: "Peers"
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.fillWidth: true
            }

        }
        // Status line
        GridLayout {
            Layout.fillWidth: true
            columns: compactLayout ? 1 : 3
            columnSpacing: 8
            rowSpacing: 6

            BusyIndicator {
                running: loading
                visible: loading
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                Layout.preferredHeight: 22
                Layout.preferredWidth: 22
            }

            Label {
                text: peersStatusText
                color: errorText.length ? "#ff8080" : "#aaa"
                font.pixelSize: 13
                Layout.fillWidth: true
            }

        }

        // Filters row
        GridLayout {
            id: filterGrid
            Layout.fillWidth: true
            columns: compactLayout ? 1 : 4
            columnSpacing: compactLayout ? 8 : 16
            rowSpacing: compactLayout ? 8 : 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: "State"; color: "#bbb"; font.pixelSize: 12 }
                ComboBox {
                    id: stateFilter
                    model: ["All","Healthy","Banned","Defunct"]
                    Layout.fillWidth: true
                    onCurrentIndexChanged: applyFilter()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: "Banned"; color: "#bbb"; font.pixelSize: 12 }
                ComboBox {
                    id: banFilter
                    model: ["All","Banned","Unbanned"]
                    Layout.fillWidth: true
                    onCurrentIndexChanged: applyFilter()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: "User Agent"
                    color: "#bbb"
                    font.pixelSize: 12
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ComboBox {
                        id: uaFilter
                        model: uaOptions
                        Layout.fillWidth: true
                        onCurrentIndexChanged: applyFilter()
                    }

                    CheckBox {
                        id: uaMustExist
                        text: ""
                        checked: false
                        onCheckedChanged: applyFilter()
                        ToolTip {
                            text: "Only show peers with a user agent"
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: "Search"; color: "#bbb"; font.pixelSize: 12 }
                TextField {
                    id: searchField
                    placeholderText: "Search peers..."
                    Layout.fillWidth: true
                    onTextChanged: applyFilter()
                }
            }
        }

        // List
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: filteredPeers
            spacing: 6
            interactive: nodeRunning
            clip: true
            ScrollBar.vertical: ScrollBar { }

            delegate: Rectangle {
                width: list.width
                height: Math.max(root.kCardH, cardLayout.implicitHeight + root.kPad * 2)
                radius: 8
                color: hovered ? "#2e2e2e" : "#242424"
                border.color: isBanned(parseFlags(modelData.flags)) ? "#8a2f2f" : "#333"
                border.width: 1

                property bool hovered: false
                MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: parent.hovered = true; onExited: parent.hovered = false }

                GridLayout {
                    id: cardLayout
                    anchors.fill: parent
                    anchors.margins: root.kPad
                    columns: compactLayout ? 1 : 2
                    columnSpacing: 12
                    rowSpacing: 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Layout.columnSpan: 1
                        Label {
                            text: addrFromPeer(modelData)
                            color: "white"
                            font.pixelSize: 15
                            elide: Label.ElideRight
                        }
                        RowLayout {
                            spacing: 12
                            Label {
                                text: "State: " + flagsToString(parseFlags(modelData.flags))
                                color: "#aaa"
                                font.pixelSize: 12
                            }
                            Label {
                                property string uaStr: uaFromPeer(modelData)
                                text: uaStr ? "User-Agent: " + uaStr : ""
                                visible: uaStr.length > 0
                                color: "#aaa"
                                font.pixelSize: 12
                                elide: Label.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: (modelData.lastConnected > 0) ? "Seen: " + agoString(modelData.lastConnected) : ""
                                visible: modelData.lastConnected > 0
                                color: "#aaa"
                                font.pixelSize: 12
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Item { Layout.fillWidth: true; Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Layout.alignment: Qt.AlignRight

                            Button {
                                id: banButton
                                text: "Ban"
                                enabled: nodeRunning && typeof nodeOwnerApi !== "undefined" && nodeOwnerApi && apiAddrFromPeer(modelData) !== ""
                                implicitWidth: root.kBtnW
                                implicitHeight: root.kBtnH
                                onClicked: {
                                    var addr = apiAddrFromPeer(modelData)
                                    if (addr && nodeOwnerApi)
                                        nodeOwnerApi.banPeerAsync(addr)
                                }
                            }

                            Button {
                                id: unbanButton
                                text: "Unban"
                                enabled: nodeRunning && typeof nodeOwnerApi !== "undefined" && nodeOwnerApi && apiAddrFromPeer(modelData) !== ""
                                implicitWidth: root.kBtnW
                                implicitHeight: root.kBtnH
                                onClicked: {
                                    var addr = apiAddrFromPeer(modelData)
                                    if (addr && nodeOwnerApi)
                                        nodeOwnerApi.unbanPeerAsync(addr)
                                }
                            }
                        }
                    }
                }
            }
            footer: Item {
                width: list.width
                height: (filteredPeers.length === 0 && nodeRunning && !loading) ? 64 : 40

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Label {
                        text: peers.length > 0 ? "No peers match the current filters." : "No peers found."
                        color: "#777"
                        horizontalAlignment: Text.AlignHCenter
                        width: list.width   // damit der Text sauber umbrechen kann
                        wrapMode: Text.Wrap
                    }

                    Loader {
                        visible: peers.length > 0
                        sourceComponent: darkButton
                        onLoaded: {
                            item.text = "Reset filters"
                            item.onClicked.connect(function() {
                                stateFilter.currentIndex = 0
                                banFilter.currentIndex = 0
                                uaFilter.currentIndex = 0
                                uaMustExist.checked = false
                                searchField.text = ""
                            })
                        }
                    }
                }
            }

        }

    }

    // Backend connections
    // ---------------------------------------------------
    Connections {
        target: nodeOwnerApi

        function onGetPeersFinishedQml(list) {
            loading = false
            errorText = ""
            updatePeerArray(list)
            rebuildUaOptions()
            applyFilter()
        }

        function onBanPeerFinished(result) {
            if (!nodeRunning) return
            var ok = (typeof result === "object") ? !!result.ok : (typeof result === "boolean" ? result : false)
            if (ok) refresh()
            else { loading = false; errorText = "Ban failed" }
        }

        function onUnbanPeerFinished(result) {
            if (!nodeRunning) return
            var ok = (typeof result === "object") ? !!result.ok : (typeof result === "boolean" ? result : false)
            if (ok) refresh()
            else { loading = false; errorText = "Unban failed" }
        }
    }

    // ---------------------------------------------------
    // Actions
    // ---------------------------------------------------
    function refresh() {
        if (!nodeRunning) return
        loading = true
        errorText = ""
        nodeOwnerApi.getPeersAsync("")
    }

    onPeersChanged: { updatePeersStatusText(); rebuildUaOptions(); applyFilter() }

    onNodeRunningChanged: {
        if (nodeRunning) {
            rebuildUaOptions()
            applyFilter()
            refresh()
        } else {
            loading = false
            errorText = ""
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: nodeRunning
        onTriggered: refresh()
    }

    Component.onCompleted: {
        updatePeersStatusText()
        stateFilter.currentIndex = 0
        banFilter.currentIndex = 0
        uaFilter.currentIndex = 0
        uaMustExist.checked = false
        if (nodeRunning) refresh()
    }
}






