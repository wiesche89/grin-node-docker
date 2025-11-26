// StatusView.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: root
    width: parent ? parent.width : 600
    height: childrenRect.height + 32
    color: "#2b2b2b"
    radius: 6
    border.color: "#555"
    border.width: 1

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 3
        shadowBlur: 0.6
        shadowColor: "#80000000"
    }

    // komplette Datenstruktur aus C++
    property var currentStatus: null
    property string lastUpdated: ""
    property int headingFontSize: 20
    property int dataFontSize: 16
    property bool compactLayout: root.width < 640
    property string nodeUptimeLabel: ""
    property int nodeUptimeSeconds: -1
    property bool hasNodeUptime: nodeUptimeSeconds >= 0 && nodeUptimeLabel !== ""

    // ---------- Helper ----------
    function readInfo(key) {
        var obj = currentStatus ? (currentStatus.syncInfo || currentStatus.sync_info) : null
        if (!obj) return undefined
        if (obj[key] !== undefined) return obj[key]
        try {
            if (typeof obj.value === "function") {
                var v = obj.value(key)
                if (v !== undefined && v !== null) return v
            }
        } catch(e) {}
        try {
            var s = obj.jsonString || (obj.toString && obj.toString())
            if (s && s.length && s.trim().charAt(0) === "{") {
                var parsed = JSON.parse(s)
                if (parsed && parsed[key] !== undefined) return parsed[key]
            }
        } catch(e) {}
        return undefined
    }

    function toEpochMillis(ts) {
        if (ts === null || ts === undefined) return NaN
        if (typeof ts === "number") {
            if (ts > 1e15) return ts / 1e6
            if (ts > 1e12) return ts
            return ts * 1000
        }
        if (typeof ts === "string") {
            var t = Date.parse(ts)
            return isNaN(t) ? NaN : t
        }
        try {
            if (typeof ts.secs === "number" && typeof ts.nanos === "number") {
                return ts.secs * 1000 + Math.floor(ts.nanos / 1e6)
            }
        } catch(e) {}
        return NaN
    }

    function bytesToMB(n) {
        var v = Number(n)
        if (!isFinite(v)) return "0.0"
        return (v / 1000000).toFixed(1)
    }

    function formatUptime(seconds) {
        var total = Number(seconds)
        if (!isFinite(total) || total < 0)
            return ""
        total = Math.floor(total)
        var days = Math.floor(total / 86400)
        total -= days * 86400
        var hours = Math.floor(total / 3600)
        total -= hours * 3600
        var minutes = Math.floor(total / 60)
        var secs = total - minutes * 60
        var parts = []
        if (days > 0)
            parts.push(days + "d")
        if (hours > 0 || parts.length > 0)
            parts.push(hours + "h")
        if (minutes > 0 || parts.length > 0)
            parts.push(minutes + "m")
        parts.push(secs + "s")
        return parts.join(" ")
    }

    // ---------- Status-Rohwert ----------
    property string _syncStatus: currentStatus ? (currentStatus.syncStatus || currentStatus.sync_status || "") : ""

    // ---- header_sync (für Info/Prozent) ----
    property var _hdrCur:  readInfo("current_height")
    property var _hdrMax:  readInfo("highest_height")
    property bool _showHeaderSync: {
        if (_syncStatus !== "header_sync") return false
        var cur = Number(_hdrCur), max = Number(_hdrMax)
        return isFinite(cur) && isFinite(max) && max > 0 && cur >= 0
    }
    property real  _hdrRatio: _showHeaderSync ? Math.max(0, Math.min(1, Number(_hdrCur) / Number(_hdrMax))) : 0
    property string _hdrPct:  (_hdrRatio * 100).toFixed(2) + "%"

    // ---- txhashsetpibd_download (PIBD) Info (completed_leaves / leaves_required) ----
    // Unterstütze beide Schreibweisen: txhashsetpibd_download & txhashsetPibd_download
    property var _pibdDone:  readInfo("completed_leaves")
    property var _pibdTotal: readInfo("leaves_required")
    property bool _isPibd: (_syncStatus === "txhashsetpibd_download" || _syncStatus === "txhashsetPibd_download")
    property bool _showPibd: {
        if (!_isPibd) return false
        var total = Number(_pibdTotal), done = Number(_pibdDone)
        return isFinite(total) && isFinite(done) && total > 0 && done >= 0
    }
    property real  _pibdRatio: _showPibd ? Math.max(0, Math.min(1, Number(_pibdDone) / Number(_pibdTotal))) : 0
    property string _pibdPct:  (_pibdRatio * 100).toFixed(2) + "%"

    // ---- txhashset_download (Download / Waiting) ----
    // { downloaded_size, total_size, prev_downloaded_size, prev_update_time, start_time }
    property var _txdlDone:        readInfo("downloaded_size")
    property var _txdlTotal:       readInfo("total_size")
    property var _txdlPrevDone:    readInfo("prev_downloaded_size")
    property var _txdlPrevUpdate:  readInfo("prev_update_time")
    property var _txdlStartTime:   readInfo("start_time")
    property bool _showTxdlActive: _syncStatus === "txhashset_download"
    property bool _txdlHasTotal: {
        var tot = Number(_txdlTotal)
        return isFinite(tot) && tot > 0
    }
    property string _txdlPct: {
        if (!_showTxdlActive || !_txdlHasTotal) return ""
        var done = Number(_txdlDone), tot = Number(_txdlTotal)
        if (!isFinite(done) || !isFinite(tot) || tot <= 0) return ""
        return (done * 100 / tot).toFixed(2) + "%"
    }
    property string _txdlSpeedText: {
        if (!_showTxdlActive || !_txdlHasTotal) return ""
        var prevMs = toEpochMillis(_txdlPrevUpdate)
        var nowMs  = Date.now()
        var durMs  = (isFinite(prevMs) ? (nowMs - prevMs) : NaN)
        var done   = Number(_txdlDone)
        var prev   = Number(_txdlPrevDone)
        if (!isFinite(done) || !isFinite(prev) || !isFinite(durMs) || durMs <= 1) return "0.0"
        var bytesPerMs = Math.max(0, done - prev) / durMs
        return bytesPerMs.toFixed(1) // B/ms ≙ kB/s
    }
    property string _txdlWaitingSecs: {
        if (!_showTxdlActive || _txdlHasTotal) return ""
        var start = toEpochMillis(_txdlStartTime)
        var now   = Date.now()
        if (!isFinite(start)) return "0"
        var secs = Math.max(0, Math.floor((now - start) / 1000))
        return String(secs)
    }

    // ---- txhashset_setup ----
    // { headers, headers_total, kernel_pos, kernel_pos_total }
    property var _setupHeaders:        readInfo("headers")
    property var _setupHeadersTotal:   readInfo("headers_total")
    property var _setupKernelPos:      readInfo("kernel_pos")
    property var _setupKernelPosTotal: readInfo("kernel_pos_total")

    property bool _showSetup: _syncStatus === "txhashset_setup"
    property bool _setupHasHeaders: {
        var h = Number(_setupHeaders), ht = Number(_setupHeadersTotal)
        return isFinite(h) && isFinite(ht) && ht > 0 && h >= 0
    }
    property bool _setupHasKernelPos: {
        var k = Number(_setupKernelPos), kt = Number(_setupKernelPosTotal)
        return isFinite(k) && isFinite(kt) && kt > 0 && k >= 0
    }

    // ---- txhashset_rangeproofs_validation ----
    // { rproofs, rproofs_total }
    property var _rpCount: readInfo("rproofs")
    property var _rpTotal: readInfo("rproofs_total")
    property bool _showRangeProofs: _syncStatus === "txhashset_rangeproofs_validation"
    property string _rpPct: {
        var rt = Number(_rpTotal)
        var r  = Number(_rpCount)
        var pct = (isFinite(rt) && rt > 0 && isFinite(r)) ? Math.floor(r * 100 / rt) : 0
        return String(pct) + "%"
    }

    // ---- txhashset_kernels_validation ----
    // { kernels, kernels_total }
    property var _kvCount: readInfo("kernels")
    property var _kvTotal: readInfo("kernels_total")
    property bool _showKernels: _syncStatus === "txhashset_kernels_validation"
    property string _kvPct: {
        var kt = Number(_kvTotal)
        var k  = Number(_kvCount)
        var pct = (isFinite(kt) && kt > 0 && isFinite(k)) ? Math.floor(k * 100 / kt) : 0
        return String(pct) + "%"
    }

    // ---- body_sync (7/7) ----
    // { current_height, highest_height }
    property var _bodyCur: readInfo("current_height")
    property var _bodyMax: readInfo("highest_height")
    property bool _showBody: _syncStatus === "body_sync"
    property string _bodyPct: {
        var cur = Number(_bodyCur), max = Number(_bodyMax)
        var pct = (isFinite(max) && max > 0 && isFinite(cur)) ? Math.floor(cur * 100 / max) : 0
        return String(pct) + "%"
    }

    // ---- Mapping der Sync-Status-Zeile (genau nach Vorgabe) ----
    property string _syncStatusDisplay: {
        switch (_syncStatus) {
        case "initial":
            return "Initializing"
        case "no_sync":
            return "Running"
        case "awaiting_peers":
            return "Waiting for peers"
        case "header_sync":
            return "Sync step 1/7: Downloading headers"
        case "txhashsetpibd_download":
        case "txhashsetPibd_download":
            return "Sync step 2/7: Downloading Tx state (PIBD)"
        case "txhashset_download":
            // Download aktiv vs. Waiting (wie gefordert)
            if (_txdlHasTotal)
                return "Sync step 2/7: Downloading chain state for state sync"
            else
                return "Sync step 2/7: Downloading chain state for state sync. Waiting remote peer to start"
        case "txhashset_setup":
            if (_setupHasHeaders)
                return "Sync step 3/7: Preparing for validation (kernel history)"
            else if (_setupHasKernelPos)
                return "Sync step 3/7: Preparing for validation (kernel position)"
            else
                return "Sync step 3/7: Preparing chain state for validation"
        case "txhashset_rangeproofs_validation":
            return "Sync step 4/7: Validating chain state - range proofs"
        case "txhashset_kernels_validation":
            return "Sync step 5/7: Validating chain state - kernels"
        case "txhashset_save":
        case "TxHashsetSave":
            return "Sync step 6/7: Finalizing chain state for state sync"
        case "txhashset_done":
        case "TxHashsetDone":
            return "Sync step 6/7: Finalized chain state for state sync"
        case "body_sync":
            return "Sync step 7/7: Downloading blocks"
        case "shutdown":
        case "Shutdown":
            return "Shutting down, closing connections"
        default:
            // Fallback: Rohstatus anzeigen, falls unbekannt
            return _syncStatus
        }
    }

    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label {
                text: "Node Status"
                font.pixelSize: headingFontSize
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }
            Label {
                visible: hasNodeUptime
                text: hasNodeUptime ? nodeUptimeLabel + " uptime: " + formatUptime(nodeUptimeSeconds) : ""
                font.pixelSize: dataFontSize
                color: "#aaaaaa"
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true }
            Label {
                text: lastUpdated !== "" ? "Last Update: " + lastUpdated : ""
                font.pixelSize: dataFontSize
                color: "#aaaaaa"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
        }

        Rectangle { height: 1; color: "#555"; Layout.fillWidth: true }

        // Zwei Spalten
        ScrollView {
            id: statusScrollView
            Layout.fillWidth: true
            Layout.preferredHeight: 360
            clip: true
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            GridLayout {
                id: statusGrid
                width: Math.max(statusScrollView.width, 640)
                Layout.fillWidth: true
                columns: compactLayout ? 1 : 2
                columnSpacing: compactLayout ? 0 : 40
                rowSpacing: 12

                // Linke Spalte
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Label {
                            text: "Chain:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus ? (currentStatus.chain || "") : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Label {
                            text: "Protocol Version:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus ? String(currentStatus.protocolVersion || currentStatus.protocol_version || "") : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Label {
                            text: "User Agent:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus ? (currentStatus.userAgent || currentStatus.user_agent || "") : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Label {
                            text: "Sync Status:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus ? _syncStatusDisplay : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showHeaderSync
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Label {
                                text: _hdrPct
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "white"
                            }
                            Label {
                                text: "(" + String(_hdrCur) + " / " + String(_hdrMax) + ")"
                                font.pixelSize: dataFontSize
                                color: "#999"
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showPibd
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Label {
                                text: _pibdPct
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "white"
                            }
                            Label {
                                text: "(" + String(_pibdDone) + " / " + String(_pibdTotal) + ")"
                                font.pixelSize: dataFontSize
                                color: "#999"
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showTxdlActive && _txdlHasTotal
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        ColumnLayout {
                            spacing: 2
                            RowLayout {
                                spacing: 10
                                Label {
                                    text: _txdlPct
                                    font.pixelSize: dataFontSize
                                    font.bold: true
                                    color: "white"
                                }
                                Label {
                                    text: "(" + bytesToMB(_txdlDone) + " / " + bytesToMB(_txdlTotal) + " MB)"
                                    font.pixelSize: dataFontSize
                                    color: "#999"
                                }
                            }
                            Label {
                                text: "Downloading chain state: " + _txdlPct + " at " + _txdlSpeedText + " (kB/s)"
                                font.pixelSize: dataFontSize
                                color: "#bbb"
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showTxdlActive && !_txdlHasTotal
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: "Downloading chain state for state sync. Waiting remote peer to start: " + _txdlWaitingSecs + "s"
                            font.pixelSize: dataFontSize
                            color: "#bbb"
                            Layout.fillWidth: true
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showSetup
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: "Sync step 3/7: " + (
                                  _setupHasHeaders
                                ? "Preparing for validation (kernel history)"
                                : _setupHasKernelPos
                                    ? "Preparing for validation (kernel position)"
                                    : "Preparing chain state for validation"
                              )
                            font.pixelSize: dataFontSize
                            color: "#bbb"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showRangeProofs
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        RowLayout {
                            spacing: 8
                            Label {
                                text: "Sync step 4/7: Validating chain state - range proofs: " + _rpPct
                                font.pixelSize: dataFontSize
                                color: "#bbb"
                            }
                            Label {
                                visible: isFinite(Number(_rpTotal)) && Number(_rpTotal) > 0
                                text: "(" + String(_rpCount) + " / " + String(_rpTotal) + ")"
                                font.pixelSize: dataFontSize
                                color: "#999"
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showKernels
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        RowLayout {
                            spacing: 8
                            Label {
                                text: "Sync step 5/7: Validating chain state - kernels: " + _kvPct
                                font.pixelSize: dataFontSize
                                color: "#bbb"
                            }
                            Label {
                                visible: isFinite(Number(_kvTotal)) && Number(_kvTotal) > 0
                                text: "(" + String(_kvCount) + " / " + String(_kvTotal) + ")"
                                font.pixelSize: dataFontSize
                                color: "#999"
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: _showBody
                        Label {
                            text: "Sync Info:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Label {
                                text: "Sync step 7/7: Downloading blocks: " + _bodyPct
                                font.pixelSize: dataFontSize
                                color: "#bbb"
                            }
                            Label {
                                visible: isFinite(Number(_bodyMax)) && Number(_bodyMax) > 0
                                text: "(" + String(_bodyCur) + " / " + String(_bodyMax) + ")"
                                font.pixelSize: dataFontSize
                                color: "#999"
                            }
                        }
                    }
                }

                // Rechte Spalte
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Label {
                            text: "Connections:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus ? String(currentStatus.connections || 0) : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Label {
                            text: "Height:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus && currentStatus.tip ? String(currentStatus.tip.height || 0) : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    RowLayout {
                        Label {
                            text: "Last Block:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus && currentStatus.tip
                                  ? (currentStatus.tip.lastBlockPushed || currentStatus.tip.last_block_pushed || "")
                                  : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }
                    }
                    RowLayout {
                        Label {
                            text: "Prev Block:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus && currentStatus.tip
                                  ? (currentStatus.tip.prevBlockToLast || currentStatus.tip.prev_block_to_last || "")
                                  : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }
                    }
                    RowLayout {
                        Label {
                            text: "Total Difficulty:"
                            font.pixelSize: dataFontSize
                            font.bold: true
                            color: "#ddd"
                            Layout.preferredWidth: 130
                        }
                        Label {
                            text: currentStatus && currentStatus.tip
                                  ? String(currentStatus.tip.totalDifficulty || currentStatus.tip.total_difficulty || "")
                                  : ""
                            font.pixelSize: dataFontSize
                            color: "white"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

    // Verbindung zum C++-Signal
    Connections {
        target: nodeOwnerApi
        function onStatusUpdated(statusObj) {
            root.currentStatus = statusObj
            var now = new Date()
            var h = now.getHours().toString().padStart(2, "0")
            var m = now.getMinutes().toString().padStart(2, "0")
            var s = now.getSeconds().toString().padStart(2, "0")
            root.lastUpdated = h + ":" + m + ":" + s
        }
    }
  }
}
