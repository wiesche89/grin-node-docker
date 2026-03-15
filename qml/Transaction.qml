import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // Global i18n object from Main.qml
    property var i18n: null

    // Whether the node is currently running (controls polling)
    property bool nodeRunning: false

    // Compact layout flag from Main.qml
    property bool compactLayout: false

    // Foreign API (set as context property in C++)
    readonly property var foreignApi: nodeForeignApi

    // Poll interval for mempool updates (ms)
    property int mempoolPollIntervalMs: 8000

    // Node manager from C++ (GrinNodeManager)
    property var nodeManager: null
    property var settingsStore: null

    // ------------------------------------------------------------------
    // UI STATE
    // ------------------------------------------------------------------
    property int poolSize: 0
    property int stempoolSize: 0
    property var tip: ({ height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 })
    property var entries: []   // only pool transactions
    property var historyEntries: []
    property int historyLimit: 50
    property var selectedTransaction: null

    // ------------------------------------------------------------------
    // Helper: Robust tip mapping from arbitrary payload
    // ------------------------------------------------------------------
    function toTip(obj) {
        if (!obj)
            return { height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 }

        var h  = obj.height
        var lb = obj.lastBlockPushed || obj.last_block_pushed || obj.last_block_h
        var pv = obj.prevBlockToLast || obj.prev_block_to_last || obj.prev_block_h
        var td = obj.totalDifficulty  || obj.total_difficulty

        function pick(o, keys) {
            for (var i = 0; i < keys.length; ++i) {
                var k = keys[i]
                if (o.hasOwnProperty(k) && o[k] !== undefined && o[k] !== null)
                    return o[k]

                var lc = k.toLowerCase()
                for (var p in o) {
                    if (String(p).toLowerCase() === lc && o[p] !== undefined && o[p] !== null)
                        return o[p]
                }
            }
            return undefined
        }

        if (h  === undefined) h  = pick(obj, ["height"])
        if (lb === undefined) lb = pick(obj, ["lastBlockPushed", "last_block_pushed", "last_block_h"])
        if (pv === undefined) pv = pick(obj, ["prevBlockToLast", "prev_block_to_last", "prev_block_h"])
        if (td === undefined) td = pick(obj, ["totalDifficulty", "total_difficulty"])

        return {
            height: Number(h || 0),
            lastBlockPushed: lb ? String(lb) : "",
            prevBlockToLast: pv ? String(pv) : "",
            totalDifficulty: Number(td || 0)
        }
    }

    // ------------------------------------------------------------------
    // Helper: Map raw pool entries to a flat model
    // ------------------------------------------------------------------
    function stableHash(text) {
        var hash = 2166136261
        var input = String(text || "")
        for (var i = 0; i < input.length; ++i) {
            hash ^= input.charCodeAt(i)
            hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24)
        }
        return (hash >>> 0).toString(16)
    }

    function normalizeSource(value) {
        if (value === undefined || value === null || value === "")
            return ""

        if (typeof value === "number") {
            switch (value) {
            case 0: return "PushApi"
            case 1: return "Broadcast"
            case 2: return "Fluff"
            case 3: return "EmbargoExpired"
            case 4: return "Deaggregate"
            default: return String(value)
            }
        }

        var text = String(value)
        if (text === "0") return "PushApi"
        if (text === "1") return "Broadcast"
        if (text === "2") return "Fluff"
        if (text === "3") return "EmbargoExpired"
        if (text === "4") return "Deaggregate"
        return text
    }

    function deriveTransactionId(entry, tx, body, fallbackIndex) {
        var directId = entry.id || entry.tx_id || tx.txId || tx.tx_id || tx.id
        if (directId !== undefined && directId !== null && String(directId).length > 0)
            return String(directId)

        if (body && body.kernels && body.kernels.length > 0) {
            var firstKernel = body.kernels[0]
            if (firstKernel && firstKernel.excess && String(firstKernel.excess).length > 0)
                return String(firstKernel.excess)
        }

        var txAt = entry.txAt || entry.tx_at || ""
        var source = normalizeSource(entry.src)
        var fee = tx.fee || entry.fee || 0
            var kernelData = body && body.kernels ? JSON.stringify(body.kernels) : ""
            var outputData = body && body.outputs ? JSON.stringify(body.outputs) : ""
            var inputData = body && body.inputs ? JSON.stringify(body.inputs) : ""
            var fingerprint = JSON.stringify(tx)

        if (!fingerprint || fingerprint === "{}") {
            fingerprint = [
                txAt,
                source,
                fee,
                inputData,
                outputData,
                kernelData,
                fallbackIndex
            ].join("|")
        }

        return "tx-" + stableHash(fingerprint)
    }

    function totalKernelFee(body) {
        if (!body || !body.kernels || body.kernels.length === 0)
            return 0

        var total = 0
        for (var i = 0; i < body.kernels.length; ++i) {
            var kernel = body.kernels[i]
            var fee = Number(kernel && kernel.fee !== undefined ? kernel.fee : 0)
            total += fee
        }
        return total
    }

    function kernelExcesses(body) {
        var out = []
        if (!body || !body.kernels)
            return out
        for (var i = 0; i < body.kernels.length; ++i) {
            var kernel = body.kernels[i]
            if (kernel && kernel.excess)
                out.push(String(kernel.excess))
        }
        return out
    }

    function kernelSignatures(body) {
        var out = []
        if (!body || !body.kernels)
            return out
        for (var i = 0; i < body.kernels.length; ++i) {
            var kernel = body.kernels[i]
            if (kernel && kernel.excessSig)
                out.push(String(kernel.excessSig))
        }
        return out
    }

    function kernelFeatureNames(body) {
        var out = []
        if (!body || !body.kernels)
            return out
        for (var i = 0; i < body.kernels.length; ++i) {
            var kernel = body.kernels[i]
            if (kernel && kernel.features)
                out.push(String(kernel.features))
        }
        return out
    }

    function commitList(items) {
        var out = []
        if (!items)
            return out
        for (var i = 0; i < items.length; ++i) {
            var item = items[i]
            if (item && item.commit) {
                if (item.commit.hex)
                    out.push(String(item.commit.hex))
                else
                    out.push(String(item.commit))
            }
        }
        return out
    }

    function mapPoolEntries(listLike) {
        var out = []
        if (!listLike)
            return out

        for (var i = 0; i < listLike.length; ++i) {
            var e    = listLike[i] || {}
            var tx   = e.tx || {}
            var body = tx.body || {}

            var fee    = Number(tx.fee || e.fee || totalKernelFee(body) || 0)
            var inputs  = (body.inputs  && body.inputs.length)  || e.inputs  || 0
            var outputs = (body.outputs && body.outputs.length) || e.outputs || 0
            var kernels = (body.kernels && body.kernels.length) || e.kernels || 0
            var id      = deriveTransactionId(e, tx, body, i)
            var txAt    = e.txAt || e.tx_at || ""
            var source  = normalizeSource(e.src)

            out.push({
                id: id,
                fee: fee,
                inputs: inputs,
                outputs: outputs,
                kernels: kernels,
                txAt: txAt ? String(txAt) : "",
                source: source ? String(source) : "",
                offset: tx && tx.offset && tx.offset.hex ? String(tx.offset.hex) : "",
                kernelExcesses: kernelExcesses(body),
                kernelSignatures: kernelSignatures(body),
                kernelFeatures: kernelFeatureNames(body),
                inputCommits: commitList(body.inputs),
                outputCommits: commitList(body.outputs)
            })
        }
        return out
    }

    function normalizeHistoryEntry(entry, fallbackIndex) {
        var item = entry || {}
        return {
            id: item.id ? String(item.id) : ("tx-" + fallbackIndex),
            fee: Number(item.fee || 0),
            inputs: Number(item.inputs || 0),
            outputs: Number(item.outputs || 0),
            kernels: Number(item.kernels || 0),
            txAt: item.txAt ? String(item.txAt) : "",
            source: normalizeSource(item.source),
            offset: item.offset ? String(item.offset) : "",
            kernelExcesses: item.kernelExcesses || [],
            kernelSignatures: item.kernelSignatures || [],
            kernelFeatures: item.kernelFeatures || [],
            inputCommits: item.inputCommits || [],
            outputCommits: item.outputCommits || [],
            observedAt: item.observedAt ? String(item.observedAt) : new Date().toISOString()
        }
    }

    function openTransactionDetails(entry) {
        selectedTransaction = normalizeHistoryEntry(entry, 0)
        transactionDetailsDialog.open()
    }

    function joinLines(values) {
        if (!values || values.length === 0)
            return "-"
        return values.join("\n")
    }

    function copyToClipboard(text) {
        if (text === undefined || text === null)
            return

        if (typeof text === "string")
            text = text.trim()

        if (!text || text === "-")
            return

        if (typeof Clipboard !== "undefined" && Clipboard)
            Clipboard.text = String(text)
    }

    function loadHistoryFromStore() {
        if (!settingsStore || typeof settingsStore.transactionHistoryJson !== "string") {
            historyEntries = []
            return
        }

        try {
            var parsed = JSON.parse(settingsStore.transactionHistoryJson)
            if (!Array.isArray(parsed)) {
                historyEntries = []
                return
            }

            var normalized = []
            for (var i = 0; i < parsed.length; ++i)
                normalized.push(normalizeHistoryEntry(parsed[i], i))

            historyEntries = normalized.slice(0, historyLimit)
        } catch (err) {
            console.warn("Transaction history parse failed:", err)
            historyEntries = []
        }
    }

    function saveHistoryToStore() {
        if (!settingsStore)
            return

        settingsStore.transactionHistoryJson = JSON.stringify(historyEntries.slice(0, historyLimit))
    }

    function clearHistory() {
        historyEntries = []
        saveHistoryToStore()
    }

    function rememberTransactions(newEntries) {
        if (!Array.isArray(newEntries) || newEntries.length === 0)
            return

        var known = {}
        for (var i = 0; i < historyEntries.length; ++i)
            known[historyEntries[i].id] = true

        var additions = []
        for (var j = 0; j < newEntries.length; ++j) {
            var candidate = normalizeHistoryEntry(newEntries[j], j)
            if (!candidate.id || known[candidate.id])
                continue

            known[candidate.id] = true
            additions.push(candidate)
        }

        if (additions.length === 0)
            return

        historyEntries = additions.concat(historyEntries).slice(0, historyLimit)
        saveHistoryToStore()
    }

    // ------------------------------------------------------------------
    // Helper: alles leeren (keine alten Artefakte)
    // ------------------------------------------------------------------
    function clearTransactionsView() {
        poolSize = 0
        stempoolSize = 0
        tip = { height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 }
        entries = []

        // Statusbar-Text zurücksetzen, falls vorhanden
        if (status) {
            status.message = ""
        }
    }

    // ------------------------------------------------------------------
    // API: Start/stop mempool polling
    // ------------------------------------------------------------------
    function startMempoolPolling() {
        if (!foreignApi)
            return
        foreignApi.startMempoolPolling(mempoolPollIntervalMs)
    }

    function stopMempoolPolling() {
        if (!foreignApi)
            return
        foreignApi.stopMempoolPolling()
    }

    function updatePollingState() {
        if (!foreignApi)
            return
        if (nodeRunning)
            startMempoolPolling()
        else
            stopMempoolPolling()
    }

    Component.onCompleted: {
        updatePollingState()
        loadHistoryFromStore()
    }
    onForeignApiChanged: updatePollingState()
    onNodeRunningChanged: {
        updatePollingState()
        if (!nodeRunning) {
            clearTransactionsView()
        }
    }
    Component.onDestruction: stopMempoolPolling()

    Connections {
        target: settingsStore
        ignoreUnknownSignals: true

        function onTransactionHistoryJsonChanged() {
            loadHistoryFromStore()
        }
    }

    // ------------------------------------------------------------------
    // Foreign API signals
    // ------------------------------------------------------------------
    Connections {
        target: (typeof foreignApi === "object" && foreignApi) ? foreignApi : null
        ignoreUnknownSignals: true

        function onPoolSizeUpdated(size) {
            poolSize = Number(size || 0)
        }

        function onStempoolSizeUpdated(size) {
            stempoolSize = Number(size || 0)
        }

        function onTipUpdated(payload) {
            tip = toTip(payload)
        }

        function onUnconfirmedTransactionsUpdated(list) {
            var mapped = mapPoolEntries(list)
            entries = mapped
            rememberTransactions(mapped)
        }
    }

    // ------------------------------------------------------------------
    // Shared dark button style (not heavily used here yet)
    // ------------------------------------------------------------------
    Component {
        id: darkButtonComponent
        Button {
            id: control
            property color bg: hovered ? "#3a3a3a" : "#2b2b2b"
            property color fg: enabled ? "white" : "#777"

            flat: true
            padding: 10

            background: Rectangle {
                radius: 6
                color: control.down ? "#2f2f2f" : control.bg
                border.color: control.down ? "#66aaff" : "#555"
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

    // ------------------------------------------------------------------
    // Main layout
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignTop
        anchors.margins: compactLayout ? 12 : 20
        spacing: 16

        // Header
        GridLayout {
            Layout.fillWidth: true
            columns: 1
            columnSpacing: 12
            rowSpacing: 6

            Label {
                text: i18n ? i18n.t("tx_title") : "Transactions"
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.fillWidth: true
            }
        }

        // Tip summary card (current chain tip)
        TipCard {
            Layout.fillWidth: true
            tipHeight: tip.height
            lastBlockPushed: tip.lastBlockPushed
            prevBlockToLast: tip.prevBlockToLast
            totalDifficulty: tip.totalDifficulty
            compactLayout: root.compactLayout
            i18n: root.i18n
        }

        // Info chips for pool and stempool sizes
        RowLayout {
            Layout.fillWidth: true
            spacing: compactLayout ? 8 : 12

            InfoChip {
                label: i18n ? i18n.t("tx_pool") : "Pool"
                value: poolSize
            }

            InfoChip {
                label: i18n ? i18n.t("tx_stempool") : "Stempool"
                value: stempoolSize
            }
        }

        // Content: pool transactions as small visual blocks
        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 12
            background: Rectangle {
                color: "#101010"
                radius: 12
                border.color: "#252525"
            }

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(flow.implicitWidth, width)
                contentHeight: Math.max(flow.implicitHeight, height)

                Flow {
                    id: flow
                    width: flick.width
                    spacing: 10
                    padding: 6

                    Repeater {
                        id: rep
                        model: Array.isArray(entries) ? entries.length : 0

                        delegate: PoolBlock {
                            width: 150
                            height: 100
                            txId:    entries[index].id
                            fee:     entries[index].fee
                            inputs:  entries[index].inputs
                            outputs: entries[index].outputs
                            kernels: entries[index].kernels
                            i18n:    root.i18n
                            onBlockClicked: openTransactionDetails(entries[index])
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    background: Rectangle { color: "transparent" }
                }
                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    background: Rectangle { color: "transparent" }
                }
            }
        }

        Frame {
            Layout.fillWidth: true
            Layout.preferredHeight: compactLayout ? 260 : 300
            padding: 12
            background: Rectangle {
                color: "#101010"
                radius: 12
                border.color: "#252525"
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: i18n ? i18n.t("tx_history_title") : "Transaction history"
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Label {
                        text: i18n
                              ? String(i18n.t("tx_history_limit")).replace("%1", historyLimit)
                              : ("Last " + historyLimit)
                        color: "#9a9a9a"
                        font.pixelSize: 12
                    }

                    Button {
                        text: i18n ? i18n.t("tx_history_clear") : "Clear"
                        flat: true
                        onClicked: clearHistory()

                        background: Rectangle {
                            radius: 6
                            color: parent.down ? "#2f2f2f" : (parent.hovered ? "#3a3a3a" : "#242424")
                            border.color: "#555"
                            border.width: 1
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: Array.isArray(historyEntries) ? historyEntries.length : 0

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: detailsColumn.implicitHeight + 20
                        radius: 10
                        color: "#171717"
                        border.color: "#2a2a2a"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: openTransactionDetails(historyEntries[index])
                        }

                        ColumnLayout {
                            id: detailsColumn
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Label {
                                    Layout.fillWidth: true
                                    text: historyEntries[index].id
                                    color: "white"
                                    font.pixelSize: 13
                                    elide: Text.ElideMiddle
                                }

                                Label {
                                    text: historyEntries[index].observedAt
                                    color: "#9a9a9a"
                                    font.pixelSize: 12
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                text: String(i18n ? i18n.t("tx_history_stats") : "Fee %1 | I/O/K %2/%3/%4")
                                      .replace("%1", historyEntries[index].fee)
                                      .replace("%2", historyEntries[index].inputs)
                                      .replace("%3", historyEntries[index].outputs)
                                      .replace("%4", historyEntries[index].kernels)
                                color: "#d0d0d0"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: historyEntries.length === 0
                        text: i18n ? i18n.t("tx_history_empty") : "No recent transactions stored yet."
                        color: "#8c8c8c"
                        font.pixelSize: 14
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }
                }
            }
        }

        StatusBar {
            id: status
            Layout.fillWidth: true
            i18n: root.i18n
        }
    }

    Dialog {
        id: transactionDetailsDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(root.width - 32, 720)
        height: Math.min(root.height - 32, detailsContent.implicitHeight + 140)
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 8
            color: "#2b2b2b"
            border.color: "#555"
            border.width: 1
        }

        header: Label {
            text: i18n ? i18n.t("tx_details_title") : "Transaction details"
            color: "white"
            font.bold: true
            font.pixelSize: 20
            padding: 16
        }

        contentItem: ScrollView {
            clip: true
            implicitHeight: Math.min(detailsContent.implicitHeight, root.height - 180)

            ColumnLayout {
                id: detailsContent
                width: transactionDetailsDialog.availableWidth
                spacing: 10

                Repeater {
                    model: [
                        { label: "ID", value: selectedTransaction ? selectedTransaction.id : "-" },
                        { label: "Observed", value: selectedTransaction ? selectedTransaction.observedAt : "-" },
                        { label: "Source", value: selectedTransaction ? (selectedTransaction.source || "-") : "-" },
                        { label: i18n ? i18n.t("tx_details_tx_at") : "Timestamp", value: selectedTransaction ? (selectedTransaction.txAt || "-") : "-" },
                        { label: "Fee", value: selectedTransaction ? selectedTransaction.fee : 0 },
                        { label: "Offset", value: selectedTransaction ? (selectedTransaction.offset || "-") : "-" },
                        { label: "Kernel features", value: selectedTransaction ? joinLines(selectedTransaction.kernelFeatures) : "-" },
                        { label: "Kernel excess", value: selectedTransaction ? joinLines(selectedTransaction.kernelExcesses) : "-" },
                        { label: "Kernel signature", value: selectedTransaction ? joinLines(selectedTransaction.kernelSignatures) : "-" },
                        { label: "Input commits", value: selectedTransaction ? joinLines(selectedTransaction.inputCommits) : "-" },
                        { label: "Output commits", value: selectedTransaction ? joinLines(selectedTransaction.outputCommits) : "-" }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        color: "transparent"
                        border.color: "#3a3a3a"
                        border.width: 1
                        radius: 6
                        implicitHeight: contentColumn.implicitHeight + 16

                        ColumnLayout {
                            id: contentColumn
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true

                                Label {
                                    text: modelData.label
                                    color: "white"
                                    font.bold: true
                                    Layout.fillWidth: true
                                }
                            }

                            TextArea {
                                Layout.fillWidth: true
                                readOnly: true
                                text: String(modelData.value)
                                wrapMode: TextEdit.WrapAnywhere
                                selectByMouse: true
                                color: "#cccccc"
                                background: Rectangle {
                                    color: "#1f1f1f"
                                    radius: 4
                                    border.color: "#2f2f2f"
                                }
                            }
                        }
                    }
                }
            }
        }

        footer: DialogButtonBox {
            Button {
                text: i18n ? i18n.t("app_close", "Close") : "Close"
                onClicked: transactionDetailsDialog.close()
            }
        }
    }

    // ==================================================================
    // Component definitions
    // ==================================================================

    // ------------------------------------------------------------------
    // TipCard: shows chain tip height and hashes
    // ------------------------------------------------------------------
    component TipCard: Rectangle {
        id: tipCard

        property int tipHeight: 0
        property string lastBlockPushed: ""
        property string prevBlockToLast: ""
        property var totalDifficulty: 0
        property bool compactLayout: false
        property var i18n: null

        property int layoutBreakpoint: 520
        readonly property bool stackedLayout: compactLayout || width < layoutBreakpoint
        property int contentSpacing: compactLayout ? 10 : 16

        radius: 12
        color: "#141414"
        border.color: "#2a2a2a"
        border.width: 1

        Flow {
            id: tipFlow
            anchors.fill: parent
            anchors.margins: 14
            Layout.fillWidth: true
            spacing: contentSpacing
            flow: Flow.LeftToRight

            ColumnLayout {
                width: columnWidth
                Layout.fillHeight: true
                spacing: 2

                Label {
                    text: i18n ? i18n.t("tx_tip_height") : "Tip height"
                    color: "#bbbbbb"
                    font.pixelSize: 12
                }

                Label {
                    text: tipCard.tipHeight > 0
                          ? tipCard.tipHeight.toLocaleString(Qt.locale(), "f", 0)
                          : "-"
                    color: "#ffd46a"
                    font.pixelSize: 18
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                    height: stackedLayout ? 14 : 8
                }
            }

            ColumnLayout {
                width: columnWidth
                Layout.fillHeight: true
                spacing: 6

                RowLayout {
                    spacing: 8

                    Label {
                        text: i18n ? i18n.t("tx_tip_last") : "Last:"
                        color: "#bbbbbb"
                        font.pixelSize: 12
                    }

                    Label {
                        text: tipCard.lastBlockPushed && tipCard.lastBlockPushed.length >= 8
                              ? tipCard.lastBlockPushed.substr(0, 8) + "..." +
                                tipCard.lastBlockPushed.substr(-8)
                              : (tipCard.lastBlockPushed || "-")
                        color: "#eaeaea"
                        font.family: "Consolas"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    spacing: 8

                    Label {
                        text: i18n ? i18n.t("tx_tip_prev") : "Prev:"
                        color: "#bbbbbb"
                        font.pixelSize: 12
                    }

                    Label {
                        text: tipCard.prevBlockToLast && tipCard.prevBlockToLast.length >= 8
                              ? tipCard.prevBlockToLast.substr(0, 8) + "..." +
                                tipCard.prevBlockToLast.substr(-8)
                              : (tipCard.prevBlockToLast || "-")
                        color: "#cfcfcf"
                        font.family: "Consolas"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            ColumnLayout {
                width: columnWidth
                Layout.fillHeight: true
                spacing: 2

                Label {
                    text: i18n ? i18n.t("tx_tip_total_difficulty") : "Total difficulty"
                    color: "#bbbbbb"
                    font.pixelSize: 12
                }

                Label {
                    text: Number(tipCard.totalDifficulty || 0)
                              .toLocaleString(Qt.locale(), "f", 0)
                    color: "#ffd46a"
                    font.pixelSize: 18
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                    height: stackedLayout ? 14 : 8
                }
            }
        }

        property real columnWidth: stackedLayout
            ? Math.max(0, width - 28)
            : Math.max(140, (width - 2 * contentSpacing - 28) / 3)

        implicitHeight: tipFlow.implicitHeight + 8
        height: implicitHeight
    }

    // ------------------------------------------------------------------
    // InfoChip
    // ------------------------------------------------------------------
    component InfoChip: Rectangle {
        id: chip
        property string label: ""
        property var value: ""
        property int labelWidth: 78

        radius: 10
        color: "#161616"
        border.color: "#2a2a2a"
        height: 32
        width: Math.max(180, row.implicitWidth + 20)

        Row {
            id: row
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            height: parent.height - 20

            Label {
                text: label + ":"
                color: "#bbbbbb"
                font.pixelSize: 12
                width: chip.labelWidth
                height: parent.height
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
            }

            Label {
                text: "" + value
                color: "white"
                font.bold: true
                width: Math.max(40, chip.width - chip.labelWidth - 30)
                height: parent.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ------------------------------------------------------------------
    // LegendChip
    // ------------------------------------------------------------------
    component LegendChip: Rectangle {
        id: chipLegend

        property string label: ""
        property bool invert: false
        property string colorMode: "fee"

        radius: 12
        implicitHeight: 28
        implicitWidth: innerRow.implicitWidth + 16
        color: "transparent"
        border.color: "#2a2a2a"

        Row {
            id: innerRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Rectangle {
                width: 16
                height: 16
                radius: 4
                color: colorMode === "src-pool"
                       ? "#ffa657"
                       : (invert ? "#65d365" : "#ffa657")
                border.color: "#111"
            }

            Label {
                text: chipLegend.label
                color: "#ddd"
            }
        }
    }

    // ------------------------------------------------------------------
    // PoolBlock
    // ------------------------------------------------------------------
    component PoolBlock: Rectangle {
        id: block

        property string txId: ""
        property real fee: 0
        property int inputs: 0
        property int outputs: 0
        property int kernels: 0
        property var i18n: null
        signal blockClicked()

        radius: 12
        border.color: "#2a2a2a"
        border.width: 1
        color: feeColor()

        function feeColor() {
            var f = Math.max(0, Math.min(1, fee / 100000000.0))
            var alpha = 0.25 + 0.55 * f
            var r = 0.95 - 0.30 * (1 - f)
            var g = 0.58
            var b = 0.34
            return Qt.rgba(r, g, b, alpha)
        }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Row {
                spacing: 6

                Label {
                    text: txId && txId.length ? txId.substr(0, 10) : (i18n ? i18n.t("tx_block_tx_short") : "Tx")
                    font.bold: true
                    color: "#eee"
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: "#ffa657"
                }

                Label {
                    text: i18n ? i18n.t("tx_block_pool") : "pool"
                    color: "#bbb"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Row {
                spacing: 10

                Label {
                    text: i18n ? i18n.t("tx_block_fee") : "Fee"
                    color: "#bbb"
                    font.pixelSize: 11
                }

                Label {
                    text: fee.toLocaleString(Qt.locale(), "f", 0)
                    color: "#eee"
                    font.pixelSize: 12
                }
            }

            Row {
                spacing: 12

                Label {
                    text: (i18n ? i18n.t("tx_block_inputs_short") : "in:") + inputs
                    color: "#ddd"
                    font.pixelSize: 12
                }

                Label {
                    text: (i18n ? i18n.t("tx_block_outputs_short") : "out:") + outputs
                    color: "#ddd"
                    font.pixelSize: 12
                }

                Label {
                    text: (i18n ? i18n.t("tx_block_kernels_short") : "kern:") + kernels
                    color: "#ddd"
                    font.pixelSize: 12
                }
            }
        }

        ToolTip.visible: hover.containsMouse
        ToolTip.delay: 180
        ToolTip.text:
            (i18n ? i18n.t("tx_block_tooltip_tx") : "Tx") + ": " + (txId || "") +
            "\n" + (i18n ? i18n.t("tx_block_tooltip_fee") : "Fee") + ": " + fee +
            "\n" + (i18n ? i18n.t("tx_block_tooltip_io") : "I/O/K") + ": " +
            inputs + "/" + outputs + "/" + kernels

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: block.blockClicked()
        }
    }

    // ------------------------------------------------------------------
    // StatusBar
    // ------------------------------------------------------------------
    component StatusBar: Rectangle {
        id: sb

        property string message: ""
        property color bgOk: "#173022"
        property color fgOk: "#b6ffd1"
        property color bgErr: "#3a1616"
        property color fgErr: "#ffb6b6"
        property var i18n: null

        height: implicitHeight
        radius: 10
        color: message.length ? bgOk : "transparent"
        border.color: message.length ? "#2a2a2a" : "transparent"
        opacity: message.length ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }

        function show(msg) {
            message = msg
            color = bgOk
            label.color = fgOk
            hideTimer.restart()
        }

        function showError(msg) {
            message = msg
            color = bgErr
            label.color = fgErr
            hideTimer.restart()
        }

        width: parent.width

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Label {
                id: label
                text: sb.message
                color: sb.fgOk
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Button {
                text: "\u00D7"
                onClicked: sb.message = ""
            }
        }

        Timer {
            id: hideTimer
            interval: 4000
            running: false
            onTriggered: sb.message = ""
        }
    }

    // -----------------------------------------------------------------
    // Listen to GrinNodeManager (nodeManager) and clear on stop/restart
    // -----------------------------------------------------------------
    Connections {
        target: nodeManager

        function onNodeStopped(kind) {
            clearTransactionsView()
            stopMempoolPolling()
        }

        function onNodeRestarted(kind) {
            clearTransactionsView()
            updatePollingState()
        }
    }
}
