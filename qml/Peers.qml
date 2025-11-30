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
    property string peersStatusText: ""
    property var i18n: null    // injected from Main.qml for translations

    // Sizes
    readonly property int kCardH: 72
    readonly property int kBtnW: 96
    readonly property int kBtnH: 36
    readonly property int kPad: 10

    // ---------------------------------------------------
    // Local translation helper
    // (uses global i18n if available, falls back to given default)
    // ---------------------------------------------------
    function tr(key, fallback) {
        if (typeof i18n !== "undefined" && i18n && i18n.t)
            return i18n.t(key)
        return fallback || key
    }

    // ---------------------------------------------------
    // Helpers
    // ---------------------------------------------------
    function flagsToString(flags) {
        // Map internal flags to localized human-readable state
        switch (flags) {
        case 0: return tr("peers_state_healthy", "Healthy")
        case 1: return tr("peers_state_banned", "Banned")
        case 2: return tr("peers_state_defunct", "Defunct")
        default: return tr("peers_state_unknown", "Unknown")
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

    // Build "time ago" string in a localized way
    function agoString(epochSecs) {
        if (!epochSecs || epochSecs <= 0) return ""
        var now = Math.floor(Date.now() / 1000)
        var d = Math.max(0, now - epochSecs)

        if (d < 60)
            return tr("time_seconds_ago", "%1s ago").replace("%1", d)
        if (d < 3600)
            return tr("time_minutes_ago", "%1m ago").replace("%1", Math.floor(d / 60))
        if (d < 86400)
            return tr("time_hours_ago", "%1h ago").replace("%1", Math.floor(d / 3600))
        return tr("time_days_ago", "%1d ago").replace("%1", Math.floor(d / 86400))
    }

    function addrFromPeer(p) {
        if (!p) return tr("peers_unknown_addr", "(unknown address)")
        if (typeof p.addr === "string" && p.addr.length) return p.addr
        if (typeof p.address === "string" && p.address.length) return p.address
        if (typeof p.ip === "string" && p.port !== undefined) return p.ip + ":" + p.port
        return tr("peers_unknown_addr", "(unknown address)")
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

        uaOptions = [tr("peers_filter_all", "All")].concat(arr)
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
            peersStatusText = tr("peers_loading", "Loading peers...")
        } else {
            // "X / Y peers"
            var tmpl = tr("peers_status_count", "%1 / %2 peers")
            peersStatusText = tmpl.replace("%1", filteredPeers.length)
                                   .replace("%2", peers.length)
        }
    }

    onLoadingChanged: updatePeersStatusText()
    onErrorTextChanged: updatePeersStatusText()
    onFilteredPeersChanged: updatePeersStatusText()

    // ---------------------------------------------------
    // Result helper for async owner API calls
    // ---------------------------------------------------
    function isResultOk(result) {
        // Most owner APIs are very relaxed – we treat "no explicit error" as success.
        if (result === undefined || result === null)
            return true

        if (typeof result === "boolean")
            return result

        if (typeof result === "object") {
            if ("ok" in result)
                return !!result.ok
            if ("success" in result)
                return !!result.success
            if ("error" in result && result.error)
                return false
            // No obvious error field -> assume success
            return true
        }

        if (typeof result === "string") {
            var s = result.toLowerCase()
            if (s.indexOf("error") !== -1 || s.indexOf("fail") !== -1)
                return false
            return true
        }

        return true
    }

    // ---------------------------------------------------
    // Dark button component (reusable styled button)
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

        // ------------------------------------------------
        // Header
        // ------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: compactLayout ? 1 : 2
            columnSpacing: 10
            rowSpacing: 6

            Label {
                text: tr("peers_title", "Connected Peers")
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.fillWidth: true
            }
        }

        // ------------------------------------------------
        // Status line (loading / count / error)
        // ------------------------------------------------
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

        // ------------------------------------------------
        // Filters row
        // ------------------------------------------------
        GridLayout {
            id: filterGrid
            Layout.fillWidth: true
            columns: compactLayout ? 1 : 4
            columnSpacing: compactLayout ? 8 : 16
            rowSpacing: compactLayout ? 8 : 12

            // State filter
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: tr("peers_state", "State"); color: "#bbb"; font.pixelSize: 12 }
                ComboBox {
                    id: stateFilter
                    model: [
                        tr("peers_filter_all", "All"),
                        tr("peers_state_healthy", "Healthy"),
                        tr("peers_state_banned", "Banned"),
                        tr("peers_state_defunct", "Defunct")
                    ]
                    Layout.fillWidth: true
                    onCurrentIndexChanged: applyFilter()
                }
            }

            // Banned filter
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: tr("peers_banned", "Banned"); color: "#bbb"; font.pixelSize: 12 }
                ComboBox {
                    id: banFilter
                    model: [
                        tr("peers_filter_all", "All"),
                        tr("peers_filter_banned", "Banned"),
                        tr("peers_filter_unbanned", "Unbanned")
                    ]
                    Layout.fillWidth: true
                    onCurrentIndexChanged: applyFilter()
                }
            }

            // User agent filter + checkbox
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: tr("peers_user_agent", "User-Agent")
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
                            text: tr("peers_only_with_ua", "Only show peers with a user agent")
                        }
                    }
                }
            }

            // Free text search
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label { text: tr("peers_search", "Search"); color: "#bbb"; font.pixelSize: 12 }
                TextField {
                    id: searchField
                    placeholderText: tr("peers_search_placeholder", "Search peers...")
                    Layout.fillWidth: true
                    onTextChanged: applyFilter()
                }
            }
        }

        // ------------------------------------------------
        // Peers list
        // ------------------------------------------------
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

                    // Left column: address, state, UA, last seen
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
                                text: tr("peers_state_prefix", "State: ") + flagsToString(parseFlags(modelData.flags))
                                color: "#aaa"
                                font.pixelSize: 12
                            }

                            Label {
                                property string uaStr: uaFromPeer(modelData)
                                text: uaStr ? tr("peers_user_agent_prefix", "User-Agent: ") + uaStr : ""
                                visible: uaStr.length > 0
                                color: "#aaa"
                                font.pixelSize: 12
                                elide: Label.ElideRight
                                Layout.fillWidth: true
                            }

                            Label {
                                text: (modelData.lastConnected > 0)
                                      ? tr("peers_seen_prefix", "Seen: ") + agoString(modelData.lastConnected)
                                      : ""
                                visible: modelData.lastConnected > 0
                                color: "#aaa"
                                font.pixelSize: 12
                            }
                        }
                    }

                    // Right column: ban/unban actions
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
                                text: tr("peers_btn_ban", "Ban")
                                enabled: nodeRunning && typeof nodeOwnerApi !== "undefined" && nodeOwnerApi && apiAddrFromPeer(modelData) !== ""
                                implicitWidth: root.kBtnW
                                implicitHeight: root.kBtnH
                                onClicked: {
                                    var addr = apiAddrFromPeer(modelData)
                                    if (addr && nodeOwnerApi) {
                                        // show spinner while ban is in progress
                                        loading = true
                                        errorText = ""
                                        nodeOwnerApi.banPeerAsync(addr)
                                    }
                                }
                            }

                            Button {
                                id: unbanButton
                                text: tr("peers_btn_unban", "Unban")
                                enabled: nodeRunning && typeof nodeOwnerApi !== "undefined" && nodeOwnerApi && apiAddrFromPeer(modelData) !== ""
                                implicitWidth: root.kBtnW
                                implicitHeight: root.kBtnH
                                onClicked: {
                                    var addr = apiAddrFromPeer(modelData)
                                    if (addr && nodeOwnerApi) {
                                        // show spinner while unban is in progress
                                        loading = true
                                        errorText = ""
                                        nodeOwnerApi.unbanPeerAsync(addr)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------
            // Footer (shown only when list is empty)
            // ------------------------------------------------
            footer: Item {
                width: list.width
                // Only show footer with text when there are no filtered peers,
                // node is running and not loading. Otherwise keep it minimal.
                height: (filteredPeers.length === 0 && nodeRunning && !loading) ? 64 : 0

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: (filteredPeers.length === 0 && nodeRunning && !loading)

                    Label {
                        text: peers.length > 0
                              ? tr("peers_no_match_filters", "No peers match the current filters.")
                              : tr("peers_no_data", "No peers connected")
                        color: "#777"
                        horizontalAlignment: Text.AlignHCenter
                        width: list.width   // allow wrapping
                        wrapMode: Text.Wrap
                    }

                    Loader {
                        visible: peers.length > 0
                        sourceComponent: darkButton
                        onLoaded: {
                            item.text = tr("peers_reset_filters", "Reset filters")
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

        // Called when peers have been loaded from backend
        function onGetPeersFinishedQml(list) {
            loading = false
            errorText = ""
            updatePeerArray(list)
            rebuildUaOptions()
            applyFilter()
        }

        // Ban result handling
        function onBanPeerFinished(result) {
            if (!nodeRunning) return
            if (isResultOk(result)) {
                // Keep spinner running until getPeersAsync finishes
                errorText = ""
                refresh()
            } else {
                loading = false
                errorText = tr("peers_ban_failed", "Ban failed")
            }
        }

        // Unban result handling
        function onUnbanPeerFinished(result) {
            if (!nodeRunning) return
            if (isResultOk(result)) {
                errorText = ""
                refresh()
            } else {
                loading = false
                errorText = tr("peers_unban_failed", "Unban failed")
            }
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

    onPeersChanged: {
        updatePeersStatusText()
        rebuildUaOptions()
        applyFilter()
    }

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
