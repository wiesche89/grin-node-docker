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

            Loader {
                id: refreshBtn
                Layout.fillWidth: compactLayout
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                sourceComponent: darkButton
                onLoaded: {
                    item.text = loading ? "Loading..." : "Refresh"
                    item.enabled = !loading && nodeRunning
                    item.onClicked.connect(refresh)
                }
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
                text: !nodeRunning ? "Node is not running - no peers." : (errorText.length ? errorText : (loading ? "Loading peers..." : (filteredPeers.length + " / " + peers.length + " peers")))
                color: !nodeRunning ? "#ffcc66" : (errorText.length ? "#ff8080" : "#aaa")
                font.pixelSize: 13
                Layout.fillWidth: true
            }

            Switch {
                id: autoRefresh
                text: "Auto"
                checked: false
                enabled: nodeRunning
                Layout.alignment: compactLayout ? Qt.AlignLeft : Qt.AlignRight
            }
        }

        // Filters row
        Flow {
            id: filterFlow
            width: parent.width
            spacing: compactLayout ? 10 : 16
            enabled: nodeRunning
            opacity: nodeRunning ? 1.0 : 0.5

            Column {
                width: compactLayout ? filterFlow.width : 180
                spacing: 4
                Label { text: "State"; color: "#bbb"; font.pixelSize: 12 }
                ComboBox {
                    id: stateFilter
                    model: ["All","Healthy","Banned","Defunct"]
                    width: parent.width
                    onCurrentIndexChanged: applyFilter()
                }
            }

            Column {
                width: compactLayout ? filterFlow.width : 180
                spacing: 4
                Label { text: "Ban"; color: "#bbb"; font.pixelSize: 12 }
                ComboBox {
                    id: banFilter
                    model: ["All","Banned","Unbanned"]
                    width: parent.width
                    onCurrentIndexChanged: applyFilter()
                }
            }

            Column {
                width: compactLayout ? filterFlow.width : 220
                spacing: 4
                Label { text: "User-Agent"; color: "#bbb"; font.pixelSize: 12 }
                ComboBox {
                    id: uaFilter
                    model: uaOptions
                    width: parent.width
                    onCurrentIndexChanged: applyFilter()
                }
            }

            Item {
                width: compactLayout ? filterFlow.width : 200
                implicitHeight: uaMustExist.implicitHeight
                CheckBox {
                    id: uaMustExist
                    text: "Only with User-Agent"
                    anchors.left: parent.left
                    width: parent.width
                    onToggled: applyFilter()
                }
            }

            Column {
                width: compactLayout ? filterFlow.width : 260
                spacing: 4
                Label { text: "Search"; color: "#bbb"; font.pixelSize: 12 }
                TextField {
                    id: searchField
                    placeholderText: "Search address or User-Agent..."
                    width: parent.width
                    onTextChanged: applyFilter()
                }
            }

            Loader {
                width: compactLayout ? filterFlow.width : 120
                sourceComponent: darkButton
                onLoaded: {
                    item.text = "Clear"
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

            // Non-running overlay
            Rectangle {
                anchors.fill: parent
                visible: !nodeRunning
                color: "transparent"
                z: 10
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Label { text: "Node is not running."; color: "#bbb"; font.pixelSize: 16 }
                    Label { text: "Start Rust or Grin++ from the Home view."; color: "#777"; font.pixelSize: 12 }
                }
            }

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

                    Loader {
                        id: actionBtn
                        Layout.alignment: compactLayout ? (Qt.AlignLeft | Qt.AlignVCenter) : (Qt.AlignRight | Qt.AlignVCenter)
                        Layout.fillWidth: compactLayout
                        Layout.preferredWidth: root.kBtnW
                        Layout.minimumWidth: compactLayout ? 0 : root.kBtnW
                        Layout.maximumWidth: compactLayout ? filterFlow.width : root.kBtnW
                        sourceComponent: darkButton
                        onLoaded: {
                            var banned = isBanned(parseFlags(modelData.flags))
                            var addrStr = addrFromPeer(modelData)
                            item.text = banned ? "Unban" : "Ban"
                            item.enabled = nodeRunning && !loading && addrStr.length
                            item.onClicked.connect(function() {
                                if (!nodeRunning) return
                                item.enabled = false
                                if (banned) nodeOwnerApi.unbanPeerAsync(addrStr)
                                else nodeOwnerApi.banPeerAsync(addrStr)
                            })
                        }
                    }
                }
            }
            // Footer (empty state for active filters)
            footer: Item {
                width: 1
                height: (filteredPeers.length === 0 && nodeRunning && !loading) ? 64 : 0
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Label {
                        text: peers.length > 0 ? "No peers match the current filters." : "No peers found."
                        color: "#777"
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

    // ---------------------------------------------------
    // Backend connections
    // ---------------------------------------------------
    Connections {
        target: nodeOwnerApi

        function onGetPeersFinishedQml(list) {
            loading = false
            errorText = ""
            peers = Array.isArray(list) ? list : []
            rebuildUaOptions()
            applyFilter()
            if (refreshBtn.item) {
                refreshBtn.item.text = "â†» Refresh"
                refreshBtn.item.enabled = nodeRunning
            }
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
        if (refreshBtn.item) {
            refreshBtn.item.text = "â€¦ Loading"
            refreshBtn.item.enabled = false
        }
        nodeOwnerApi.getPeersAsync("")
    }

    onPeersChanged: { rebuildUaOptions(); applyFilter() }

    onNodeRunningChanged: {
        if (nodeRunning) {
            rebuildUaOptions()
            applyFilter()
            refresh()
        } else {
            loading = false
            errorText = ""
            if (refreshBtn.item) {
                refreshBtn.item.text = "â†» Refresh"
                refreshBtn.item.enabled = false
            }
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: autoRefresh.checked && nodeRunning
        onTriggered: refresh()
    }

    Component.onCompleted: {
        stateFilter.currentIndex = 0
        banFilter.currentIndex = 0
        uaFilter.currentIndex = 0
        uaMustExist.checked = false
        if (nodeRunning) refresh()
    }
}






