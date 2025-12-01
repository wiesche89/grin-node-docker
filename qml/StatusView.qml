// StatusView.qml
// -----------------------------------------------------------------------------
// Card-like view that displays:
//   - basic node status (chain, protocol, user agent, sync status)
//   - detailed sync progress (headers, PIBD, TxHashset, validation steps)
//   - chain tip info (height, hashes, total difficulty)
//
// Expects:
//   - currentStatus: status object from C++ (nodeOwnerApi)
//   - i18n: translation helper with .language and .t(key)
// -----------------------------------------------------------------------------

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: root

    // Basic card styling
    width: parent ? parent.width : 600
    height: childrenRect.height + 32
    color: "#2b2b2b"
    radius: 6
    border.color: "#555"
    border.width: 1

    // Subtle 3D shadow
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 3
        shadowBlur: 0.6
        shadowColor: "#80000000"
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    property var currentStatus: null
    property string lastUpdated: ""

    // Layout behavior depending on overall width
    property bool compactLayout:  root.width < 640
    property int headingFontSize: compactLayout ? 16 : 20
    property int dataFontSize:    compactLayout ? 12 : 16

    // Label column width is derived from the widest translated label
    // (see labelProbe Item below). A bit of extra padding is added.
    property real labelColumnWidth: labelProbe.maxWidth + 8

    // Injected translation helper from Main.qml
    property var i18n: null

    // -------------------------------------------------------------------------
    // i18n helper
    // -------------------------------------------------------------------------

    function tr(key, fallback) {
        if (!i18n || typeof i18n.t !== "function")
            return fallback || key

        // Bind to language changes
        var _ = i18n.language
        return i18n.t(key)
    }

    // -------------------------------------------------------------------------
    // Utility helpers
    // -------------------------------------------------------------------------

    function readInfo(key) {
        var obj = currentStatus ? (currentStatus.syncInfo || currentStatus.sync_info) : null
        if (!obj)
            return undefined

        if (obj[key] !== undefined)
            return obj[key]

        // QVariantMap-like API
        try {
            if (typeof obj.value === "function") {
                var v = obj.value(key)
                if (v !== undefined && v !== null)
                    return v
            }
        } catch (e) {}

        // Embedded JSON string
        try {
            var s = obj.jsonString || (obj.toString && obj.toString())
            if (s && s.length && s.trim().charAt(0) === "{") {
                var parsed = JSON.parse(s)
                if (parsed && parsed[key] !== undefined)
                    return parsed[key]
            }
        } catch (e2) {}

        return undefined
    }

    function toEpochMillis(ts) {
        if (ts === null || ts === undefined)
            return NaN

        if (typeof ts === "number") {
            if (ts > 1e15)  // nano
                return ts / 1e6
            if (ts > 1e12)  // milli
                return ts
            return ts * 1000 // seconds
        }

        if (typeof ts === "string") {
            var t = Date.parse(ts)
            return isNaN(t) ? NaN : t
        }

        // Rust-style { secs, nanos }
        try {
            if (typeof ts.secs === "number" && typeof ts.nanos === "number")
                return ts.secs * 1000 + Math.floor(ts.nanos / 1e6)
        } catch (e) {}

        return NaN
    }

    function bytesToMB(n) {
        var v = Number(n)
        if (!isFinite(v))
            return "0.0"
        return (v / 1000000).toFixed(1)
    }

    // Middle-elide long strings (hashes)
    function midElide(text, maxLen) {
        if (text === null || text === undefined)
            return ""

        var s = String(text)
        if (s.length <= maxLen)
            return s

        var keep = maxLen - 3
        if (keep <= 0)
            return "..."

        var left = Math.ceil(keep / 2)
        var right = Math.floor(keep / 2)
        return s.substring(0, left) + "..." + s.substring(s.length - right)
    }

    // -------------------------------------------------------------------------
    // Sync status & derived values
    // -------------------------------------------------------------------------

    property string _syncStatus: currentStatus
                                  ? (currentStatus.syncStatus
                                     || currentStatus.sync_status
                                     || "")
                                  : ""

    // Header sync (1/7)
    property var  _hdrCur:  readInfo("current_height")
    property var  _hdrMax:  readInfo("highest_height")
    property bool _showHeaderSync: {
        if (_syncStatus !== "header_sync")
            return false
        var cur = Number(_hdrCur)
        var max = Number(_hdrMax)
        return isFinite(cur) && isFinite(max) && max > 0 && cur >= 0
    }
    property real  _hdrRatio: _showHeaderSync
                              ? Math.max(0, Math.min(1, Number(_hdrCur) / Number(_hdrMax)))
                              : 0
    property string _hdrPct:  (_hdrRatio * 100).toFixed(2) + "%"

    // PIBD download (2/7)
    property var  _pibdDone:  readInfo("completed_leaves")
    property var  _pibdTotal: readInfo("leaves_required")
    property bool _isPibd: (_syncStatus === "txhashsetpibd_download"
                            || _syncStatus === "txhashsetPibd_download")
    property bool _showPibd: {
        if (!_isPibd)
            return false
        var total = Number(_pibdTotal)
        var done  = Number(_pibdDone)
        return isFinite(total) && isFinite(done) && total > 0 && done >= 0
    }
    property real  _pibdRatio: _showPibd
                               ? Math.max(0, Math.min(1, Number(_pibdDone) / Number(_pibdTotal)))
                               : 0
    property string _pibdPct:  (_pibdRatio * 100).toFixed(2) + "%"

    // TxHashset download
    property var _txdlDone:       readInfo("downloaded_size")
    property var _txdlTotal:      readInfo("total_size")
    property var _txdlPrevDone:   readInfo("prev_downloaded_size")
    property var _txdlPrevUpdate: readInfo("prev_update_time")
    property var _txdlStartTime:  readInfo("start_time")

    property bool _showTxdlActive: _syncStatus === "txhashset_download"

    property bool _txdlHasTotal: {
        var tot = Number(_txdlTotal)
        return isFinite(tot) && tot > 0
    }

    property string _txdlPct: {
        if (!_showTxdlActive || !_txdlHasTotal)
            return ""
        var done = Number(_txdlDone)
        var tot  = Number(_txdlTotal)
        if (!isFinite(done) || !isFinite(tot) || tot <= 0)
            return ""
        return (done * 100 / tot).toFixed(2) + "%"
    }

    property string _txdlSpeedText: {
        if (!_showTxdlActive || !_txdlHasTotal)
            return ""
        var prevMs = toEpochMillis(_txdlPrevUpdate)
        var nowMs  = Date.now()
        var durMs  = (isFinite(prevMs) ? (nowMs - prevMs) : NaN)
        var done   = Number(_txdlDone)
        var prev   = Number(_txdlPrevDone)
        if (!isFinite(done) || !isFinite(prev) || !isFinite(durMs) || durMs <= 1)
            return "0.0"
        var bytesPerMs = Math.max(0, done - prev) / durMs
        return bytesPerMs.toFixed(1)
    }

    property string _txdlWaitingSecs: {
        if (!_showTxdlActive || _txdlHasTotal)
            return ""
        var start = toEpochMillis(_txdlStartTime)
        var now   = Date.now()
        if (!isFinite(start))
            return "0"
        var secs = Math.max(0, Math.floor((now - start) / 1000))
        return String(secs)
    }

    // TxHashset setup (3/7)
    property var _setupHeaders:        readInfo("headers")
    property var _setupHeadersTotal:   readInfo("headers_total")
    property var _setupKernelPos:      readInfo("kernel_pos")
    property var _setupKernelPosTotal: readInfo("kernel_pos_total")

    property bool _showSetup: _syncStatus === "txhashset_setup"

    property bool _setupHasHeaders: {
        var h  = Number(_setupHeaders)
        var ht = Number(_setupHeadersTotal)
        return isFinite(h) && isFinite(ht) && ht > 0 && h >= 0
    }

    property bool _setupHasKernelPos: {
        var k  = Number(_setupKernelPos)
        var kt = Number(_setupKernelPosTotal)
        return isFinite(k) && isFinite(kt) && kt > 0 && k >= 0
    }

    // Rangeproofs validation (4/7)
    property var  _rpCount: readInfo("rproofs")
    property var  _rpTotal: readInfo("rproofs_total")
    property bool _showRangeProofs: _syncStatus === "txhashset_rangeproofs_validation"

    property string _rpPct: {
        var rt  = Number(_rpTotal)
        var r   = Number(_rpCount)
        var pct = (isFinite(rt) && rt > 0 && isFinite(r)) ? Math.floor(r * 100 / rt) : 0
        return String(pct) + "%"
    }

    // Kernels validation (5/7)
    property var  _kvCount: readInfo("kernels")
    property var  _kvTotal: readInfo("kernels_total")
    property bool _showKernels: _syncStatus === "txhashset_kernels_validation"

    property string _kvPct: {
        var kt  = Number(_kvTotal)
        var k   = Number(_kvCount)
        var pct = (isFinite(kt) && kt > 0 && isFinite(k)) ? Math.floor(k * 100 / kt) : 0
        return String(pct) + "%"
    }

    // Body sync (7/7)
    property var  _bodyCur: readInfo("current_height")
    property var  _bodyMax: readInfo("highest_height")
    property bool _showBody: _syncStatus === "body_sync"

    property string _bodyPct: {
        var cur = Number(_bodyCur)
        var max = Number(_bodyMax)
        var pct = (isFinite(max) && max > 0 && isFinite(cur)) ? Math.floor(cur * 100 / max) : 0
        return String(pct) + "%"
    }

    // -------------------------------------------------------------------------
    // Human readable labels
    // -------------------------------------------------------------------------

    property string _syncStatusDisplay: {
        switch (_syncStatus) {

        case "initial":
            return tr("status_sync_initial", "Initializing")

        case "no_sync":
            return tr("status_sync_running", "Running")

        case "awaiting_peers":
            return tr("status_sync_awaiting_peers", "Waiting for peers")

        case "header_sync":
            return tr("status_sync_header", "1/7: Downloading\nheaders")

        case "txhashsetpibd_download":
        case "txhashsetPibd_download":
            return tr("status_sync_pibd", "2/7: Downloading\nTx state (PIBD)")

        case "txhashset_download":
            if (_txdlHasTotal)
                return tr("status_sync_txhashset_download",
                          "2/7: Downloading\nchain state")
            else
                return tr("status_sync_txhashset_waiting",
                          "2/7: Downloading\nchain state.\nWaiting peer…")

        case "txhashset_setup":
            if (_setupHasHeaders)
                return tr("status_sync_setup_headers",
                          "3/7: Preparing for\nvalidation\n(kernel history)")
            else if (_setupHasKernelPos)
                return tr("status_sync_setup_pos",
                          "3/7: Preparing for\nvalidation\n(kernel position)")
            else
                return tr("status_sync_setup_generic",
                          "3/7: Preparing chain\nstate for validation")

        case "txhashset_rangeproofs_validation":
            return tr("status_sync_rproofs",
                      "4/7: Validating\nrange proofs")

        case "txhashset_kernels_validation":
            return tr("status_sync_kernels",
                      "5/7: Validating\nkernels")

        case "txhashset_save":
        case "TxHashsetSave":
            return tr("status_sync_save",
                      "6/7: Finalizing\nchain state")

        case "txhashset_done":
        case "TxHashsetDone":
            return tr("status_sync_done",
                      "6/7: Chain state\nfinalized")

        case "body_sync":
            return tr("status_sync_body",
                      "7/7: Downloading\nblocks")

        case "shutdown":
        case "Shutdown":
            return tr("status_sync_shutdown",
                      "Shutting down\nclosing connections")

        default:
            return _syncStatus
        }
    }

    property string _chainDisplay: {
        if (!currentStatus)
            return ""
        var c = currentStatus.chain || ""
        if (c === "main")
            return tr("status_chain_main", "mainnet")
        if (c === "test")
            return tr("status_chain_test", "testnet")
        return c
    }

    // -------------------------------------------------------------------------
    // Hidden label-width probe (computes widest translated label)
    // -------------------------------------------------------------------------
    Item {
        id: labelProbe
        visible: false

        // Maximum implicitWidth of all label texts we use
        property real maxWidth: Math.max(
                                   chainLabelProbe.implicitWidth,
                                   protocolLabelProbe.implicitWidth,
                                   userAgentLabelProbe.implicitWidth,
                                   syncStatusLabelProbe.implicitWidth,
                                   syncInfoLabelProbe.implicitWidth,
                                   connectionsLabelProbe.implicitWidth,
                                   heightLabelProbe.implicitWidth,
                                   lastBlockLabelProbe.implicitWidth,
                                   prevBlockLabelProbe.implicitWidth,
                                   totalDiffLabelProbe.implicitWidth
                               )

        Text {
            id: chainLabelProbe
            text: tr("status_chain", "Chain:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: protocolLabelProbe
            text: tr("status_protocol_version", "Protocol Version:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: userAgentLabelProbe
            text: tr("status_user_agent", "User Agent:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: syncStatusLabelProbe
            text: tr("status_sync_status", "Sync Status:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: syncInfoLabelProbe
            text: tr("status_sync_info", "Sync Info:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: connectionsLabelProbe
            text: tr("status_connections", "Connections:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: heightLabelProbe
            text: tr("status_height", "Height:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: lastBlockLabelProbe
            text: tr("status_last_block", "Last Block:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: prevBlockLabelProbe
            text: tr("status_prev_block", "Prev Block:")
            font.pixelSize: dataFontSize
        }
        Text {
            id: totalDiffLabelProbe
            text: tr("status_total_difficulty", "Total Difficulty:")
            font.pixelSize: dataFontSize
        }
    }

    // -------------------------------------------------------------------------
    // Main layout
    // -------------------------------------------------------------------------
    ColumnLayout {
        anchors.top:    parent.top
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.margins: 16
        spacing: 12

        // Header: title + last update
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: tr("status_title", "Node Status")
                font.pixelSize: headingFontSize
                font.bold: true
                color: "#ffffff"
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Label {
                text: lastUpdated !== ""
                      ? tr("status_last_update_prefix", "Last Update: ") + lastUpdated
                      : ""
                font.pixelSize: dataFontSize
                color: "#aaaaaa"
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }

        // Divider line
        Rectangle {
            height: 1
            color: "#555"
            Layout.fillWidth: true
        }

        // Scrollable main content
        ScrollView {
            id: statusScrollView

            Layout.fillWidth: true
            Layout.preferredHeight: 360
            clip: true

            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.vertical:   ScrollBar { policy: ScrollBar.AsNeeded }

            Flickable {
                id: statusFlick
                anchors.fill: parent
                clip: true

                contentWidth:  statusGrid.width
                contentHeight: statusGrid.height
                flickableDirection: Flickable.HorizontalAndVerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                    id: statusGrid

                    width: Math.max(statusScrollView.width, 900)
                    columns: compactLayout ? 1 : 2
                    columnSpacing: compactLayout ? 0 : 40
                    rowSpacing: 12

                    // ==========================================================
                    // LEFT COLUMN: chain + sync info
                    // ==========================================================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Chain
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_chain", "Chain:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: _chainDisplay
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Protocol version
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_protocol_version", "Protocol Version:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus
                                      ? String(currentStatus.protocolVersion
                                               || currentStatus.protocol_version
                                               || "")
                                      : ""
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // User agent
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_user_agent", "User Agent:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus
                                      ? (currentStatus.userAgent
                                         || currentStatus.user_agent
                                         || "")
                                      : ""
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Sync status
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_sync_status", "Sync Status:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus ? _syncStatusDisplay : ""
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Header sync progress
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showHeaderSync

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

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
                                        wrapMode: Text.NoWrap
                                    }
                                }
                            }
                        }

                        // PIBD progress
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showPibd

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

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
                                        wrapMode: Text.NoWrap
                                    }
                                }
                            }
                        }

                        // TxHashset download (known total)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showTxdlActive && _txdlHasTotal

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Label {
                                        text: _txdlPct
                                        font.pixelSize: dataFontSize
                                        font.bold: true
                                        color: "white"
                                    }
                                    Label {
                                        text: "("
                                              + bytesToMB(_txdlDone)
                                              + " / "
                                              + bytesToMB(_txdlTotal)
                                              + " MB)"
                                        font.pixelSize: dataFontSize
                                        color: "#999"
                                        wrapMode: Text.NoWrap
                                    }
                                }

                                Label {
                                    text: tr(
                                              "status_txdl_progress",
                                              "Downloading chain state: %1 at %2 (kB/s)"
                                          )
                                          .replace("%1", _txdlPct)
                                          .replace("%2", _txdlSpeedText)
                                    font.pixelSize: dataFontSize
                                    color: "#bbb"
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // TxHashset download (waiting)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showTxdlActive && !_txdlHasTotal

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            Label {
                                text: tr(
                                          "status_txdl_waiting",
                                          "Downloading chain state for state sync. "
                                          + "Waiting remote peer to start: %1s"
                                      ).replace("%1", _txdlWaitingSecs)
                                font.pixelSize: dataFontSize
                                color: "#bbb"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // TxHashset setup
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showSetup

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            Label {
                                text: _setupHasHeaders
                                      ? tr("status_setup_headers",
                                           "Sync step 3/7: Preparing for validation (kernel history)")
                                      : (_setupHasKernelPos
                                         ? tr("status_setup_pos",
                                              "Sync step 3/7: Preparing for validation (kernel position)")
                                         : tr("status_setup_generic",
                                              "Sync step 3/7: Preparing chain state for validation"))
                                font.pixelSize: dataFontSize
                                color: "#bbb"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Rangeproofs validation
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showRangeProofs

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: tr(
                                              "status_rp_progress",
                                              "Sync step 4/7: Validating chain state - range proofs: %1"
                                          ).replace("%1", _rpPct)
                                    font.pixelSize: dataFontSize
                                    color: "#bbb"
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    visible: isFinite(Number(_rpTotal)) && Number(_rpTotal) > 0
                                    text: "(" + String(_rpCount) + " / " + String(_rpTotal) + ")"
                                    font.pixelSize: dataFontSize
                                    color: "#999"
                                    wrapMode: Text.NoWrap
                                }
                            }
                        }

                        // Kernels validation
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showKernels

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: tr(
                                              "status_kv_progress",
                                              "Sync step 5/7: Validating chain state - kernels: %1"
                                          ).replace("%1", _kvPct)
                                    font.pixelSize: dataFontSize
                                    color: "#bbb"
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    visible: isFinite(Number(_kvTotal)) && Number(_kvTotal) > 0
                                    text: "(" + String(_kvCount) + " / " + String(_kvTotal) + ")"
                                    font.pixelSize: dataFontSize
                                    color: "#999"
                                    wrapMode: Text.NoWrap
                                }
                            }
                        }

                        // Body sync
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showBody

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: tr(
                                              "status_body_progress",
                                              "Sync step 7/7: Downloading blocks: %1"
                                          ).replace("%1", _bodyPct)
                                    font.pixelSize: dataFontSize
                                    color: "#bbb"
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                                Label {
                                    visible: isFinite(Number(_bodyMax)) && Number(_bodyMax) > 0
                                    text: "(" + String(_bodyCur) + " / " + String(_bodyMax) + ")"
                                    font.pixelSize: dataFontSize
                                    color: "#999"
                                    wrapMode: Text.NoWrap
                                }
                            }
                        }
                    }

                    // ==========================================================
                    // RIGHT COLUMN: connections + tip info
                    // ==========================================================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Connections
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_connections", "Connections:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus
                                      ? String(currentStatus.connections || 0)
                                      : ""
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Height
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_height", "Height:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus && currentStatus.tip
                                      ? String(currentStatus.tip.height || 0)
                                      : ""
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Last block
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_last_block", "Last Block:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus && currentStatus.tip
                                      ? midElide(
                                            currentStatus.tip.lastBlockPushed
                                            || currentStatus.tip.last_block_pushed
                                            || "",
                                            25
                                        )
                                      : ""
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Previous block
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_prev_block", "Prev Block:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus && currentStatus.tip
                                      ? midElide(
                                            currentStatus.tip.prevBlockToLast
                                            || currentStatus.tip.prev_block_to_last
                                            || "",
                                            25
                                        )
                                      : ""
                                font.pixelSize: dataFontSize
                                color: "white"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Total difficulty
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: tr("status_total_difficulty", "Total Difficulty:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.minimumWidth: labelColumnWidth
                                Layout.maximumWidth: labelColumnWidth
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: currentStatus && currentStatus.tip
                                      ? String(currentStatus.tip.totalDifficulty
                                               || currentStatus.tip.total_difficulty
                                               || "")
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
        }
    }

    // -------------------------------------------------------------------------
    // Connection to C++ backend (nodeOwnerApi)
    // -------------------------------------------------------------------------
    Connections {
        target: nodeOwnerApi

        // Called when a new status object is available
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
