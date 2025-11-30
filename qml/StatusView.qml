// StatusView.qml
// -----------------------------------------------------------------------------
// Card-like view that displays:
//   - basic node status (chain, protocol, user agent, sync status)
//   - detailed sync progress (headers, PIBD, TxHashset, validation steps)
//   - chain tip info (height, hashes, total difficulty)
//
// The view consumes a rich C++ status object via `currentStatus` and an
// injected i18n helper object via `i18n`.
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

    // Drop shadow for a subtle 3D card effect
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 3
        shadowBlur: 0.6
        shadowColor: "#80000000"
    }

    // =========================================================================
    // Public API
    // =========================================================================

    // Full status object from C++ (exposed by nodeOwnerApi)
    property var currentStatus: null

    // Formatted last-update time (HH:MM:SS)
    property string lastUpdated: ""

    // Font sizes & layout behavior depending on card width
    property int headingFontSize: root.width < 640 ? 16 : 20
    property int dataFontSize:    root.width < 640 ? 12 : 16
    property bool compactLayout:  root.width < 640

    // Injected translation object (QtObject from Main.qml)
    // Must expose:
    //   property string language
    //   function t(key: string) -> string
    property var i18n: null

    // =========================================================================
    // Local i18n helper
    // =========================================================================

    // Small wrapper around the global i18n helper. Fallback text is used when
    // no i18n object is present or the key does not exist. The dummy read of
    // `i18n.language` establishes a binding so that all texts react to
    // language changes.
    function tr(key, fallback) {
        if (!i18n || typeof i18n.t !== "function")
            return fallback || key

        // Make the binding dependency explicit
        var _ = i18n.language

        return i18n.t(key)
    }

    // =========================================================================
    // Utility helpers
    // =========================================================================

    // Safely read a field from the sync-info structure.
    // Supports:
    //   - direct JS object: obj[key]
    //   - QVariantMap-like: obj.value(key)
    //   - JSON string in obj.jsonString or obj.toString()
    function readInfo(key) {
        var obj = currentStatus ? (currentStatus.syncInfo || currentStatus.sync_info) : null
        if (!obj)
            return undefined

        if (obj[key] !== undefined)
            return obj[key]

        // QVariantMap / QJsonObject-like API
        try {
            if (typeof obj.value === "function") {
                var v = obj.value(key)
                if (v !== undefined && v !== null)
                    return v
            }
        } catch (e) {}

        // As a last resort try to parse an embedded JSON string
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

    // Normalize various timestamp representations to epoch millis
    //  - number as seconds or millis
    //  - ISO-8601 string
    //  - { secs, nanos } struct
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

        // Rust-style timespec { secs, nanos }
        try {
            if (typeof ts.secs === "number" && typeof ts.nanos === "number")
                return ts.secs * 1000 + Math.floor(ts.nanos / 1e6)
        } catch (e) {}

        return NaN
    }

    // Convert bytes to MB with one decimal place
    function bytesToMB(n) {
        var v = Number(n)
        if (!isFinite(v))
            return "0.0"
        return (v / 1000000).toFixed(1)
    }

    // Middle-elide a long string (used for block hashes)
    function midElide(text, maxLen) {
        if (text === null || text === undefined)
            return ""

        var s = String(text)
        if (s.length <= maxLen)
            return s

        var keep = maxLen - 3 // space for "..."
        if (keep <= 0)
            return "..."

        var left = Math.ceil(keep / 2)
        var right = Math.floor(keep / 2)
        return s.substring(0, left) + "..." + s.substring(s.length - right)
    }

    // =========================================================================
    // Raw sync status & derived values
    // =========================================================================

    // Raw sync status string from C++
    // Typical values:
    //   "initial", "no_sync", "awaiting_peers", "header_sync",
    //   "txhashsetpibd_download", "txhashset_download", "txhashset_setup",
    //   "txhashset_rangeproofs_validation", "txhashset_kernels_validation",
    //   "txhashset_save", "txhashset_done", "body_sync", "shutdown", ...
    property string _syncStatus: currentStatus
                                  ? (currentStatus.syncStatus
                                     || currentStatus.sync_status
                                     || "")
                                  : ""

    // ---------------------- Header sync (1/7) --------------------------------
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

    // ------------------------ PIBD download (2/7) ----------------------------
    // Fields: { completed_leaves, leaves_required }
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

    // ---------------- TxHashset download (2/7 fallback) ----------------------
    // Fields: { downloaded_size, total_size, prev_downloaded_size,
    //           prev_update_time, start_time }
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

    // Approximate speed based on previous update snapshot
    //   - returns B/ms, which roughly equals kB/s
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

    // Waiting time in seconds until a peer starts the transfer
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

    // -------------------- TxHashset setup (3/7) ------------------------------
    // Fields: { headers, headers_total, kernel_pos, kernel_pos_total }
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

    // ---------------- Rangeproofs validation (4/7) ---------------------------
    // Fields: { rproofs, rproofs_total }
    property var  _rpCount: readInfo("rproofs")
    property var  _rpTotal: readInfo("rproofs_total")
    property bool _showRangeProofs: _syncStatus === "txhashset_rangeproofs_validation"

    property string _rpPct: {
        var rt  = Number(_rpTotal)
        var r   = Number(_rpCount)
        var pct = (isFinite(rt) && rt > 0 && isFinite(r)) ? Math.floor(r * 100 / rt) : 0
        return String(pct) + "%"
    }

    // ---------------- Kernels validation (5/7) -------------------------------
    // Fields: { kernels, kernels_total }
    property var  _kvCount: readInfo("kernels")
    property var  _kvTotal: readInfo("kernels_total")
    property bool _showKernels: _syncStatus === "txhashset_kernels_validation"

    property string _kvPct: {
        var kt  = Number(_kvTotal)
        var k   = Number(_kvCount)
        var pct = (isFinite(kt) && kt > 0 && isFinite(k)) ? Math.floor(k * 100 / kt) : 0
        return String(pct) + "%"
    }

    // ----------------------- Body sync (7/7) ---------------------------------
    // Fields: { current_height, highest_height }
    property var  _bodyCur: readInfo("current_height")
    property var  _bodyMax: readInfo("highest_height")
    property bool _showBody: _syncStatus === "body_sync"

    property string _bodyPct: {
        var cur = Number(_bodyCur)
        var max = Number(_bodyMax)
        var pct = (isFinite(max) && max > 0 && isFinite(cur)) ? Math.floor(cur * 100 / max) : 0
        return String(pct) + "%"
    }

    // =========================================================================
    // Human readable labels
    // =========================================================================

    // Sync status → human-readable, localized label
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

    // Chain identifier → localized display name.
    // Add matching keys to i18n:
    //   "status_chain_main": "mainnet" / "Hauptnetz"
    //   "status_chain_test": "testnet" / "Testnetz"
    property string _chainDisplay: {
        if (!currentStatus)
            return ""

        var c = currentStatus.chain || ""
        if (c === "main")
            return tr("status_chain_main", "mainnet")
        if (c === "test")
            return tr("status_chain_test", "testnet")

        // Fallback: show unknown chains as-is
        return c
    }

    // =========================================================================
    // Main layout
    // =========================================================================

    ColumnLayout {
        anchors.top:    parent.top
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.margins: 16
        spacing: 12

        // ---------------------------------------------------------------------
        // Header line: title + last update time
        // ---------------------------------------------------------------------
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
            }
        }

        // Thin divider between header and content
        Rectangle {
            height: 1
            color: "#555"
            Layout.fillWidth: true
        }

        // ---------------------------------------------------------------------
        // Scrollable content: left column = chain/sync, right = connections/tip
        // ---------------------------------------------------------------------
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

                    // Minimum width so horizontal scrolling can kick in
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

                        // Chain (main/test)
                        RowLayout {
                            Label {
                                text: tr("status_chain", "Chain:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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
                            Label {
                                text: tr("status_protocol_version", "Protocol Version:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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
                            Label {
                                text: tr("status_user_agent", "User Agent:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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
                            Label {
                                text: tr("status_sync_status", "Sync Status:")
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

                        // ---------------- Header sync progress -----------------
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showHeaderSync

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
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

                        // ------------------- PIBD progress ---------------------
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showPibd

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
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

                        // ------- TxHashset download with known total size -----
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showTxdlActive && _txdlHasTotal

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
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
                                        text: "("
                                              + bytesToMB(_txdlDone)
                                              + " / "
                                              + bytesToMB(_txdlTotal)
                                              + " MB)"
                                        font.pixelSize: dataFontSize
                                        color: "#999"
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
                                }
                            }
                        }

                        // ------- TxHashset download waiting for peer ----------
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showTxdlActive && !_txdlHasTotal

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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

                        // --------------------- TxHashset setup -----------------
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showSetup

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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

                        // ---------------- Rangeproofs validation --------------
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showRangeProofs

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
                            }

                            RowLayout {
                                spacing: 8

                                Label {
                                    text: tr(
                                              "status_rp_progress",
                                              "Sync step 4/7: Validating chain state - range proofs: %1"
                                          ).replace("%1", _rpPct)
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

                        // ------------------ Kernels validation ----------------
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showKernels

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
                            }

                            RowLayout {
                                spacing: 8

                                Label {
                                    text: tr(
                                              "status_kv_progress",
                                              "Sync step 5/7: Validating chain state - kernels: %1"
                                          ).replace("%1", _kvPct)
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

                        // ------------------------ Body sync -------------------
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: _showBody

                            Label {
                                text: tr("status_sync_info", "Sync Info:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Label {
                                    text: tr(
                                              "status_body_progress",
                                              "Sync step 7/7: Downloading blocks: %1"
                                          ).replace("%1", _bodyPct)
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

                    // ==========================================================
                    // RIGHT COLUMN: connections + tip info
                    // ==========================================================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Connections
                        RowLayout {
                            Label {
                                text: tr("status_connections", "Connections:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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

                        // Height (tip height)
                        RowLayout {
                            Label {
                                text: tr("status_height", "Height:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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

                        // Last block hash
                        RowLayout {
                            Label {
                                text: tr("status_last_block", "Last Block:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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
                                wrapMode: Text.NoWrap
                                elide: Text.ElideNone
                            }
                        }

                        // Previous block hash
                        RowLayout {
                            Label {
                                text: tr("status_prev_block", "Prev Block:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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
                                wrapMode: Text.NoWrap
                                elide: Text.ElideNone
                            }
                        }

                        // Total difficulty
                        RowLayout {
                            Label {
                                text: tr("status_total_difficulty", "Total Difficulty:")
                                font.pixelSize: dataFontSize
                                font.bold: true
                                color: "#ddd"
                                Layout.preferredWidth: 130
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

    // =========================================================================
    // Backend connection: subscribe to nodeOwnerApi status updates
    // =========================================================================
    Connections {
        target: nodeOwnerApi

        // Called from C++ when a new status object is available
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
