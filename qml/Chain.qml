import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // ---------------------------------------------------
    // Public state
    // ---------------------------------------------------
    property bool nodeRunning: false
    property bool compactLayout: false
    property var i18n: null        // injected from Main.qml

    // Node manager from C++ (GrinNodeManager)
    property var nodeManager: null

    // Foreign API (set in main.cpp as nodeForeignApi context property)
    readonly property var foreignApi: nodeForeignApi

    // Settings
    property int lastCount: 100
    property int refreshIntervalMs: 5000

    // Chain state
    property var tip: ({ height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 })
    property var blocksRaw: []        // full objects including inputs/outputs/kernels
    property var blocks: []           // simplified tile data (height/hash/tx counts)

    // Selection / details
    property int selectedIndex: -1
    property bool hasUserSelection: false
    readonly property int chainNodeWidth: 220
    readonly property int chainConnectorWidth: 48
    readonly property int detailsMinimumHeight: compactLayout ? 520 : 320
    property string blockSearchText: ""
    property int pendingSearchHeight: -1
    property bool pendingScrollToLeft: false
    property bool dummySelected: false
    property int blockCadenceMs: 60000
    property double nowMs: Date.now()
    readonly property double dummyProgress: blockCadenceMs > 0 ? ((nowMs % blockCadenceMs) / blockCadenceMs) : 0

    // ---------------------------------------------------
    // i18n helper
    // ---------------------------------------------------
    function tr(key, fallback) {
        var res

        if (i18n && typeof i18n.t === "function") {
            res = i18n.t(key)
        }

        if (res === undefined || res === null || res === "") {
            res = (fallback !== undefined) ? fallback : key
        }

        return String(res)
    }

    // ---------------------------------------------------
    // Generic helpers
    // ---------------------------------------------------
    function get(o, k, dflt) {
        if (o === null || o === undefined)
            return dflt

        if (typeof o === "object") {
            if (o.hasOwnProperty && o.hasOwnProperty(k) && o[k] !== undefined)
                return o[k]
        }

        if (o[k] !== undefined)
            return o[k]

        return dflt
    }

    function toNum(x) {
        if (typeof x === "number" && isFinite(x)) return x
        var n = Number(x)
        return isFinite(n) ? n : 0
    }
    function toTs(x)  {
        if (typeof x === "number" && isFinite(x)) return x
        var ms = Date.parse(x || "")
        return isNaN(ms) ? 0 : Math.floor(ms / 1000)
    }

    Timer {
        id: dummyCycleTimer
        interval: 33
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
    }
    function copyToClipboard(text) {
        if (text === undefined || text === null)
            return
        if (typeof text === "string")
            text = text.trim()
        if (!text)
            return
        if (typeof Clipboard !== "undefined" && Clipboard)
            Clipboard.text = String(text)
    }
    function headerOf(rb) {
        var h = get(rb,"header",null)
        if (!h) h = get(rb,"block_header",null)
        return h || {}
    }

    function commitmentHex(value) {
        if (value === null || value === undefined)
            return ""
        if (typeof value === "string")
            return value
        if (value.hex !== undefined && value.hex !== null)
            return String(value.hex)
        if (value.commitment !== undefined && value.commitment !== null)
            return String(value.commitment)
        return String(value)
    }

    function featureName(value) {
        if (value === null || value === undefined || value === "")
            return ""
        if (typeof value === "number") {
            if (value === 1)
                return "Coinbase"
            return "Plain"
        }
        var text = String(value)
        if (text === "1")
            return "Coinbase"
        if (text === "0")
            return "Plain"
        return text
    }

    // ---------------------------------------------------
    // Mapping: full block -> row tile
    // ---------------------------------------------------
    function simplifyBlockForRow(rb) {
        var h = headerOf(rb)
        function count(x){ return Array.isArray(x) ? x.length : (x && typeof x.length === "number" ? x.length : 0) }
        return {
            isDummy: false,
            height: toNum(get(h,"height",0)),
            hash: String(get(h,"hash","")),
            timestamp: toTs(get(h,"timestamp",0)),
            inputs: count(get(rb,"inputs",[])),
            outputs: count(get(rb,"outputs",[])),
            kernels: count(get(rb,"kernels",[])),
            difficulty: toNum(get(h,"total_difficulty", get(h,"totalDifficulty",0)))
        }
    }

    function latestDummyBlock() {
        return {
            isDummy: true,
            rawIndex: -1,
            height: tip.height > 0 ? (tip.height + 1) : 0,
            hash: "",
            timestamp: 0,
            inputs: 0,
            outputs: 0,
            kernels: 0,
            difficulty: 0
        }
    }

    function mapHeaderFromRaw(rb) {
        var h = headerOf(rb)
        return {
            height: toNum(get(h,"height",0)),
            hash: String(get(h,"hash","")),
            previous: String(get(h,"previous","")),
            timestamp: toTs(get(h,"timestamp",0)),
            total_difficulty: toNum(get(h,"total_difficulty", get(h,"totalDifficulty",0))),
            kernel_root: String(get(h,"kernel_root","")),
            output_root: String(get(h,"output_root",""))
        }
    }

    function mapInputsFromRaw(rb) {
        var arr = get(rb,"inputs",[]) || []
        var out = []
        for (var i=0;i<arr.length;i++) {
            var it = arr[i]
            if (typeof it === "string") {
                out.push({
                    commit: it,
                    features: "",
                    height: 0,
                    spent: false
                })
                continue
            }
            it = it || {}
            out.push({
                commit: commitmentHex(get(it,"commit",get(it,"commitment",""))),
                features: featureName(get(it,"features","")),
                height: toNum(get(it,"height",get(it,"block_height",0))),
                spent: !!get(it,"spent",false)
            })
        }
        return out
    }

    function findSelectedIndex(rawBlocks, previousRaw) {
        if (!rawBlocks || rawBlocks.length === 0)
            return -1
        if (!previousRaw)
            return 0

        var previousHeader = headerOf(previousRaw)
        var previousHash = String(get(previousHeader, "hash", ""))
        var previousHeight = toNum(get(previousHeader, "height", 0))

        for (var i = 0; i < rawBlocks.length; ++i) {
            var candidateHeader = headerOf(rawBlocks[i])
            if (previousHash.length > 0 && String(get(candidateHeader, "hash", "")) === previousHash)
                return i
        }

        for (var j = 0; j < rawBlocks.length; ++j) {
            var header = headerOf(rawBlocks[j])
            if (toNum(get(header, "height", 0)) === previousHeight)
                return j
        }

        return 0
    }

    function findVisibleBlockIndex(query) {
        var text = String(query || "").trim().toLowerCase()
        if (!text)
            return -1

        var numericHeight = /^[0-9]+$/.test(text) ? Number(text) : -1
        for (var i = 0; i < root.blocks.length; ++i) {
            var blk = root.blocks[i]
            var hash = String(blk.hash || "").toLowerCase()
            if ((numericHeight >= 0 && blk.height === numericHeight)
                    || (hash.length > 0 && (hash === text || hash.indexOf(text) === 0))) {
                return i
            }
        }
        return -1
    }

    function scrollToVisibleIndex(visibleIndex) {
        if (visibleIndex < 0)
            return
        var itemX = visibleIndex * (chainNodeWidth + chainConnectorWidth)
        var targetX = Math.max(0, itemX - Math.max(16, Math.floor((flick.width - chainNodeWidth) / 2)))
        flick.contentX = Math.min(targetX, Math.max(0, flick.contentWidth - flick.width))
    }

    function loadBlocksAroundHeight(centerHeight) {
        if (!foreignApi || centerHeight < 0)
            return

        var halfWindow = Math.floor(lastCount / 2)
        var start = Math.max(0, centerHeight - halfWindow)
        var end = start + lastCount - 1

        if (tip.height > 0 && end > tip.height) {
            end = tip.height
            start = Math.max(0, end - lastCount + 1)
        }

        foreignApi.getBlocksAsync(start, end, lastCount, false)
    }

    function searchBlock() {
        var query = String(blockSearchText || "").trim()
        if (!query) {
            showLatestBlocks()
            status.show(tr("chain_search_found", "Block selected."))
            return
        }

        var visibleIndex = findVisibleBlockIndex(query)
        if (visibleIndex < 0) {
            if (/^[0-9]+$/.test(query)) {
                pendingSearchHeight = Number(query)
                root.hasUserSelection = true
                loadBlocksAroundHeight(pendingSearchHeight)
                status.show(tr("chain_search_loading", "Loading block..."))
                return
            }

            if (foreignApi && query.length > 0) {
                pendingSearchHeight = -1
                root.hasUserSelection = true
                foreignApi.getBlockAsync(0, query, "")
                status.show(tr("chain_search_loading", "Loading block..."))
                return
            }

            status.showError(tr("chain_search_not_found", "Block not found in the loaded range."))
            return
        }

        root.hasUserSelection = true
        root.dummySelected = false
        root.selectedIndex = root.blocks[visibleIndex].rawIndex
        tabsBar.currentIndex = 0
        Qt.callLater(function() { scrollToVisibleIndex(visibleIndex) })
        status.show(tr("chain_search_found", "Block selected."))
    }

    function showLatestBlocks() {
        pendingSearchHeight = -1
        pendingScrollToLeft = true
        hasUserSelection = false
        selectedIndex = -1
        dummySelected = true
        tabsBar.currentIndex = 0
        if (tip.height > 0)
            loadBlocksForTip(tip.height)
    }

    function mapOutputsFromRaw(rb) {
        var arr = get(rb,"outputs",[]) || []
        var out = []
        for (var i=0;i<arr.length;i++) {
            var o = arr[i] || {}
            out.push({
                commitment: get(o,"commit",get(o,"commitment","")),
                output_type: get(o,"output_type", get(o,"is_coinbase",false) ? "Coinbase" : "Plain"),
                height: toNum(get(o,"block_height",get(o,"height",0))),
                mmr_index: toNum(get(o,"mmr_index",0)),
                spent: !!get(o,"spent",false),
                proof_hash: get(o,"proof_hash","")
            })
        }
        return out
    }

    function mapKernelsFromRaw(rb) {
        var arr = get(rb,"kernels",[]) || []
        var out = []
        for (var i=0;i<arr.length;i++) {
            var k = arr[i] || {}
            out.push({
                features: get(k,"features",""),
                fee: toNum(get(k,"fee",0)),
                lock_height: toNum(get(k,"lock_height",0)),
                excess: get(k,"excess",""),
                excess_sig: get(k,"excess_sig","")
            })
        }
        return out
    }

    // ---------------------------------------------------
    // Derived data from selection
    // ---------------------------------------------------
    property var selectedRaw: (!dummySelected && selectedIndex >= 0 && selectedIndex < blocksRaw.length) ? blocksRaw[selectedIndex] : null
    property var hdrData:     selectedRaw ? mapHeaderFromRaw(selectedRaw)  : null
    property var inputsData:  selectedRaw ? mapInputsFromRaw(selectedRaw)  : []
    property var outputsData: selectedRaw ? mapOutputsFromRaw(selectedRaw) : []
    property var kernelsData: selectedRaw ? mapKernelsFromRaw(selectedRaw) : []
    property int detailsHeight: hdrData ? hdrData.height : -1

    // ---------------------------------------------------
    // Helper: alles leeren (keine alten Artefakte)
    // ---------------------------------------------------
    function clearChainView() {
        tip = { height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 }
        blocksRaw = []
        blocks = []
        selectedIndex = -1
        hasUserSelection = false
        dummySelected = false

        if (status)
            status.message = ""

        if (tabsBar)
            tabsBar.currentIndex = 0
    }

    // ---------------------------------------------------
    // API calls
    // ---------------------------------------------------
    function refreshTip() {
        if (!foreignApi) {
            status.showError(tr("chain_err_foreign_api", "Foreign API not set."))
            return
        }
        try {
            foreignApi.getTipAsync()
        } catch(e) {
            status.showError(tr("chain_err_get_tip", "getTipAsync failed: %1").replace("%1", e))
        }
    }

    function loadBlocksForTip(h) {
        if (!foreignApi) return
        var start = Math.max(0, h - (lastCount - 1))
        try {
            foreignApi.getBlocksAsync(start, h, lastCount, false)
        } catch(e) {
            status.showError(tr("chain_err_get_blocks", "getBlocksAsync failed: %1").replace("%1", e))
        }
    }

    // ---------------------------------------------------
    // Lifecycle / timers
    // ---------------------------------------------------
    Component.onCompleted: if (nodeRunning && foreignApi) refreshTip()
    onForeignApiChanged: if (foreignApi && nodeRunning) refreshTip()

    Timer {
        id: autoTimer
        interval: refreshIntervalMs
        repeat: true
        running: nodeRunning && !!foreignApi
        onTriggered: if (nodeRunning) refreshTip()
    }

    onNodeRunningChanged: {
        if (nodeRunning && foreignApi) {
            refreshTip()
        } else {
            // Node aus -> UI leeren
            clearChainView()
        }
    }

    // ---------------------------------------------------
    // Signals from foreign API
    // ---------------------------------------------------
    Connections {
        target: (typeof foreignApi === "object" && foreignApi) ? foreignApi : null
        ignoreUnknownSignals: true

        function onTipUpdated(payload) {
            var t = payload || {}
            var h  = get(t,"height",0)
            var lb = get(t,"lastBlockPushed", get(t,"last_block_pushed",""))
            var pv = get(t,"prevBlockToLast", get(t,"prev_block_to_last",""))
            var td = get(t,"totalDifficulty", get(t,"total_difficulty",0))
            tip = {
                height: toNum(h),
                lastBlockPushed: String(lb || ""),
                prevBlockToLast: String(pv || ""),
                totalDifficulty: toNum(td)
            }

            if (tip.height > 0) {
                Qt.callLater(function() {
                    var selectedHeight = hasUserSelection && selectedRaw
                            ? toNum(get(headerOf(selectedRaw), "height", 0))
                            : -1
                    if (selectedHeight > 0)
                        loadBlocksAroundHeight(selectedHeight)
                    else
                        loadBlocksForTip(tip.height)
                })
            } else {
                blocksRaw = []
                blocks = []
                selectedIndex = -1
            }
        }

        function onBlocksUpdated(blockList, lastRetrievedHeight) {
            var previousRaw = selectedRaw

            blocksRaw = blockList || []

            var simple = []
            for (var i = 0; i < blocksRaw.length; ++i) {
                var s = simplifyBlockForRow(blocksRaw[i])
                s.rawIndex = i
                simple.push(s)
            }
            simple.sort(function(a,b){ return b.height - a.height })
            root.blocks = [latestDummyBlock()].concat(simple)

            Qt.callLater(function() {
                if (pendingSearchHeight >= 0) {
                    var searchedIndex = -1
                    for (var i = 0; i < root.blocks.length; ++i) {
                        if (root.blocks[i].height === pendingSearchHeight) {
                            searchedIndex = i
                            break
                        }
                    }

                    if (searchedIndex >= 0) {
                        dummySelected = false
                        selectedIndex = root.blocks[searchedIndex].rawIndex
                        tabsBar.currentIndex = 0
                        scrollToVisibleIndex(searchedIndex)
                        status.show(tr("chain_search_found", "Block selected."))
                    } else {
                        selectedIndex = findSelectedIndex(blocksRaw, previousRaw)
                        status.showError(tr("chain_search_not_found", "Block not found in the loaded range."))
                    }
                    pendingSearchHeight = -1
                } else {
                    selectedIndex = findSelectedIndex(blocksRaw, previousRaw)
                }
                if (pendingScrollToLeft) {
                    flick.contentX = 0
                    pendingScrollToLeft = false
                }
            })
        }

        function onBlockUpdated(block) {
            var blockHeight = toNum(get(headerOf(block), "height", 0))
            if (blockHeight <= 0) {
                status.showError(tr("chain_search_not_found", "Block not found in the loaded range."))
                return
            }

            pendingSearchHeight = blockHeight
            loadBlocksAroundHeight(blockHeight)
        }

        function onBlockLookupFailed(message) {
            pendingSearchHeight = -1
            status.showError(message && String(message).length > 0
                             ? String(message)
                             : tr("chain_search_not_found", "Block not found in the loaded range."))
        }
    }

    // ---------------------------------------------------
    // UI layout
    // ---------------------------------------------------
    ScrollView {
        id: chainPageScroll
        anchors.fill: parent
        anchors.margins: compactLayout ? 12 : 20
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: chainPageScroll.availableWidth
            height: Math.max(implicitHeight, chainPageScroll.availableHeight)
            spacing: 20

        // ----------------------- Header row -----------------------
        GridLayout {
            Layout.fillWidth: true
            columns: compactLayout ? 1 : 3
            columnSpacing: 12
            rowSpacing: 10

            Label {
                text: tr("chain_title", "Chain")
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.columnSpan: compactLayout ? 1 : 1
                Layout.preferredWidth: compactLayout ? parent.width : 520
                Layout.preferredHeight: compactLayout ? 72 : 36
                radius: 10
                color: "#161616"
                border.color: "#2a2a2a"

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 14

                    Label {
                        text: tr("chain_tip_label", "Tip:")
                        color: "#bbbbbb"
                    }

                    Label {
                        text: tip.height > 0
                              ? (tip.height + " | " + (tip.lastBlockPushed && tip.lastBlockPushed.length
                                                       ? tip.lastBlockPushed.substr(0,10) + "..."
                                                       : "-"))
                              : "-"
                        color: "white"
                        font.bold: true
                    }

                    Rectangle {
                        width: 1
                        height: parent.height * 0.7
                        color: "#333"
                        visible: !compactLayout
                    }

                    Label {
                        text: tr("chain_blocks_label", "Blocks:")
                        color: "#bbbbbb"
                    }

                    Label {
                        text: blocks.length
                        color: "white"
                        font.bold: true
                    }
                }
            }
        }

        // Small hint text
        Label {
            Layout.fillWidth: true
            text: tr("chain_hint_tap_block", "Tap a block for details.")
            color: "#bbbbbb"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            DarkTextField {
                Layout.fillWidth: true
                text: root.blockSearchText
                placeholderText: tr("chain_search_placeholder", "Search by block height or hash")
                onTextChanged: root.blockSearchText = text
                onAccepted: searchBlock()
            }

            DarkButton {
                text: tr("chain_search_button", "Search")
                onClicked: searchBlock()
            }
        }

        // ----------------------- Chain tiles row -----------------------
        Frame {
            Layout.fillWidth: true
            Layout.preferredHeight: 190
            padding: 12
            background: Rectangle {
                color: "transparent"
                radius: 12
                border.color: "transparent"
            }

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: true

                contentWidth: Math.max(chainContent.width, width)
                contentHeight: height

                Item {
                    id: chainContent
                    width: Array.isArray(root.blocks) && root.blocks.length > 0
                           ? (root.blocks.length * root.chainNodeWidth)
                             + ((root.blocks.length - 1) * root.chainConnectorWidth)
                           : flick.width
                    height: parent.height

                    Row {
                        id: chainRow
                        spacing: 0
                        height: parent.height

                        Repeater {
                            model: Array.isArray(root.blocks) ? root.blocks.length : 0
                            delegate: ChainNode {
                                nodeWidth: root.chainNodeWidth
                                nodeHeight: 120
                                connectorWidth: root.chainConnectorWidth
                                depthProgress: root.blocks.length > 1
                                               ? (index / Math.max(1, root.blocks.length - 1))
                                               : 0
                                blk: root.blocks[index]
                                showConnector: index < (root.blocks.length - 1)
                                onClickedBlock: {
                                    if (blk.isDummy) {
                                        showLatestBlocks()
                                    } else {
                                        root.hasUserSelection = true
                                        root.dummySelected = false
                                        root.selectedIndex = blk.rawIndex
                                    }
                                }
                            }
                        }
                    }
                }

                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }

        // ----------------------- Details area -----------------------
        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: !compactLayout
            Layout.minimumHeight: detailsMinimumHeight
            Layout.preferredHeight: detailsMinimumHeight
            padding: 12
            background: Rectangle {
                color: "#121212"
                radius: 12
                border.color: "#303030"
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 10

                // Details header: "Block details #123"
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label {
                        text: tr("chain_block_details_title", "Block details")
                        color: "#bbb"
                    }
                    Label {
                        text: detailsHeight >= 0 ? ("#" + detailsHeight) : ""
                        color: "white"
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                }

                // Tabs
                TabBar {
                    id: tabsBar
                    Layout.fillWidth: true
                    currentIndex: 0
                    background: Rectangle {
                        radius: 8
                        color: "#151515"
                        border.color: "#2a2a2a"
                        height: parent.height
                    }

                    DarkTabButton { text: tr("chain_tab_header",  "Header") }
                    DarkTabButton { text: tr("chain_tab_inputs",  "Inputs") }
                    DarkTabButton { text: tr("chain_tab_outputs", "Outputs") }
                    DarkTabButton { text: tr("chain_tab_kernels", "Kernels") }
                }

                // Tab content
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Math.max(0, detailsMinimumHeight - tabsBar.implicitHeight - 48)
                    currentIndex: tabsBar.currentIndex

                    // ---- Header tab ----
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ScrollView {
                            anchors.fill: parent
                            contentWidth: width
                            clip: true

                            Column {
                                width: parent.width - 20
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 6
                                DetailField {
                                    width: parent.width
                                    label: tr("chain_hdr_hash_prefix", "Hash: ")
                                    value: hdrData ? (hdrData.hash || "") : ""
                                }
                                DetailField {
                                    width: parent.width
                                    label: tr("chain_hdr_prev_prefix", "Previous: ")
                                    value: hdrData ? (hdrData.previous || "") : ""
                                }
                                DetailField {
                                    width: parent.width
                                    label: tr("chain_hdr_total_diff_prefix", "Total difficulty: ")
                                    value: hdrData ? String(hdrData.total_difficulty) : ""
                                }
                                DetailField {
                                    width: parent.width
                                    label: tr("chain_hdr_time_prefix", "Time: ")
                                    value: hdrData && hdrData.timestamp
                                           ? new Date(hdrData.timestamp * 1000).toLocaleString()
                                           : ""
                                }
                                DetailField {
                                    width: parent.width
                                    label: tr("chain_hdr_kernel_root_prefix", "Kernel root: ")
                                    value: hdrData ? (hdrData.kernel_root || "") : ""
                                }
                                DetailField {
                                    width: parent.width
                                    label: tr("chain_hdr_output_root_prefix", "Output root: ")
                                    value: hdrData ? (hdrData.output_root || "") : ""
                                }
                            }
                        }
                    }

                    // ---- Inputs tab ----
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Frame {
                            anchors.fill: parent
                            background: Rectangle {
                                color: "#141414"
                                radius: 10
                                border.color: "#2a2a2a"
                            }
                            padding: 10

                            Flickable {
                                anchors.fill: parent
                                clip: true
                                contentWidth: parent.width
                                contentHeight: inputsColumn.implicitHeight

                                Column {
                                    id: inputsColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 8

                                    Label {
                                        text: tr("chain_inputs_count", "%1 Inputs")
                                                  .replace("%1", inputsData.length)
                                        color: "#ddd"
                                    }

                                    Repeater {
                                        model: inputsData
                                        delegate: Rectangle {
                                            radius: 8
                                            color: "#1a1a1a"
                                            border.color: "#2a2a2a"
                                            width: parent.width
                                            implicitHeight: inputCol.implicitHeight + 12
                                            height: implicitHeight

                                            Column {
                                                id: inputCol
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4

                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_input_commit_prefix", "Commit: ")
                                                    value: modelData.commit || ""
                                                }
                                                DetailField {
                                                    visible: !!(modelData.features || "")
                                                    width: parent.width
                                                    label: tr("chain_output_type_prefix", "Type: ")
                                                    value: modelData.features || ""
                                                }
                                                DetailField {
                                                    visible: (modelData.height || 0) > 0
                                                    width: parent.width
                                                    label: tr("chain_input_height_prefix", "Height: ")
                                                    value: String(modelData.height)
                                                }
                                                DetailField {
                                                    visible: modelData.spent !== undefined
                                                    width: parent.width
                                                    label: tr("chain_input_spent_prefix", "Spent: ")
                                                    value: modelData.spent
                                                           ? tr("common_yes", "yes")
                                                           : tr("common_no", "no")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Outputs tab ----
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Frame {
                            anchors.fill: parent
                            background: Rectangle {
                                color: "#141414"
                                radius: 10
                                border.color: "#2a2a2a"
                            }
                            padding: 10

                            Flickable {
                                anchors.fill: parent
                                clip: true
                                contentWidth: parent.width
                                contentHeight: outputsColumn.implicitHeight

                                Column {
                                    id: outputsColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 8

                                    Label {
                                        text: tr("chain_outputs_count", "%1 Outputs")
                                                  .replace("%1", outputsData.length)
                                        color: "#ddd"
                                    }

                                    Repeater {
                                        model: outputsData
                                        delegate: Rectangle {
                                            radius: 8
                                            color: "#1a1a1a"
                                            border.color: "#2a2a2a"
                                            width: parent.width
                                            implicitHeight: outputCol.implicitHeight + 12
                                            height: implicitHeight

                                            Column {
                                                id: outputCol
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4

                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_output_type_prefix", "Type: ")
                                                    value: get(modelData, "output_type", "")
                                                }

                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_output_height_prefix", "Height: ")
                                                    value: String(get(modelData, "height", ""))
                                                }

                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_output_mmr_index_prefix", "MMR index: ")
                                                    value: String(get(modelData, "mmr_index", ""))
                                                }

                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_output_spent_prefix", "Spent: ")
                                                    value: get(modelData, "spent", false)
                                                           ? tr("common_yes", "yes")
                                                           : tr("common_no", "no")
                                                }

                                                DetailField {
                                                    visible: !!get(modelData, "proof_hash", "")
                                                    width: parent.width
                                                    label: tr("chain_output_proof_hash_prefix", "Proof hash: ")
                                                    value: get(modelData, "proof_hash", "")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Kernels tab ----
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Frame {
                            anchors.fill: parent
                            background: Rectangle {
                                color: "#141414"
                                radius: 10
                                border.color: "#2a2a2a"
                            }
                            padding: 10

                            Flickable {
                                anchors.fill: parent
                                clip: true
                                contentWidth: parent.width
                                contentHeight: kernelsColumn.implicitHeight

                                Column {
                                    id: kernelsColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 8

                                    Label {
                                        text: tr("chain_kernels_count", "%1 Kernels")
                                                  .replace("%1", kernelsData.length)
                                        color: "#ddd"
                                    }

                                    Repeater {
                                        model: kernelsData
                                        delegate: Rectangle {
                                            radius: 8
                                            color: "#1a1a1a"
                                            border.color: "#2a2a2a"
                                            width: parent.width
                                            implicitHeight: kernelCol.implicitHeight + 12
                                            height: implicitHeight

                                            Column {
                                                id: kernelCol
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4

                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_kernel_features_prefix", "Features: ")
                                                    value: modelData.features || ""
                                                }
                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_kernel_fee_prefix", "Fee: ")
                                                    value: String(modelData.fee)
                                                }
                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_kernel_lock_height_prefix", "Lock height: ")
                                                    value: String(modelData.lock_height)
                                                }
                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_kernel_excess_prefix", "Excess: ")
                                                    value: modelData.excess || ""
                                                }
                                                DetailField {
                                                    width: parent.width
                                                    label: tr("chain_kernel_excess_sig_prefix", "Excess sig: ")
                                                    value: modelData.excess_sig || ""
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Loading hint at startup
        Label {
            visible: blocks.length === 0 && tip.height === 0
            text: tr("chain_loading_tip", "Loading tip...")
            color: "#888"
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

            StatusBar {
                id: status
                Layout.fillWidth: true
            }
        }
    }

    // ---------------------------------------------------
    // Dark UI helper components
    // ---------------------------------------------------

    component DarkButton: Button {
        id: darkBtnCtrl
        property color bg: hovered ? "#3a3a3a" : "#2b2b2b"
        property color fg: enabled ? "white" : "#777"
        flat: true
        padding: 10
        background: Rectangle {
            radius: 6
            color: darkBtnCtrl.down ? "#2f2f2f" : darkBtnCtrl.bg
            border.color: darkBtnCtrl.down ? "#66aaff" : "#555"
            border.width: 1
        }
        contentItem: Text {
            text: darkBtnCtrl.text
            color: darkBtnCtrl.fg
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    component DarkTabButton: TabButton {
        id: darkTabCtrl
        property color bgNormal: hovered ? "#3a3a3a" : "#2b2b2b"
        property color bgChecked: hovered ? "#4a4a4a" : "#3b3b3b"
        property color fg: enabled ? "white" : "#777"

        implicitHeight: 36
        implicitWidth: Math.max(90, contentItem.implicitWidth + 20)
        padding: 10
        checkable: true

        background: Rectangle {
            radius: 6
            color: darkTabCtrl.checked
                   ? (darkTabCtrl.down ? "#353535" : "#3b3b3b")
                   : (darkTabCtrl.down ? "#2f2f2f" : "#2b2b2b")
            border.color: darkTabCtrl.checked ? "#66aaff" : "#555"
            border.width: 1
        }

        contentItem: Text {
            text: darkTabCtrl.text
            color: darkTabCtrl.fg
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    component DarkTextField: TextField {
        color: "white"
        placeholderTextColor: "#777"
        selectionColor: "#3a6df0"
        selectedTextColor: "white"
        background: Rectangle {
            radius: 6
            color: "#2b2b2b"
            border.color: "#555"
            border.width: 1
        }
        padding: 8
        font.pixelSize: 14
    }

    component DetailField: Rectangle {
        id: detailField
        property string label: ""
        property string value: ""

        width: parent ? parent.width : implicitWidth
        color: "#1a1a1a"
        border.color: "#2a2a2a"
        border.width: 1
        radius: 8
        implicitHeight: fieldColumn.implicitHeight + 12

        ColumnLayout {
            id: fieldColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            Label {
                Layout.fillWidth: true
                text: detailField.label
                color: "#bbb"
                font.bold: true
                elide: Text.ElideRight
            }

            TextArea {
                Layout.fillWidth: true
                readOnly: true
                text: detailField.value ? String(detailField.value) : ""
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: "#ddd"
                background: Rectangle {
                    color: "#141414"
                    radius: 6
                    border.color: "#222"
                }
            }
        }
    }

    component ChainNode: Item {
        property var blk
        property bool showConnector: true
        property int nodeWidth: 220
        property int nodeHeight: 120
        property int connectorWidth: 48
        property real depthProgress: 0.0
        readonly property int connectorDepth: 4
        readonly property real nodeScale: 1.0 - (0.22 * depthProgress)
        readonly property real nodeLift: -20 * depthProgress
        readonly property real nodeInset: -10 * depthProgress
        readonly property real nodeFade: 1.0 - (0.28 * depthProgress)
        signal clickedBlock()

        width: nodeWidth + (showConnector ? connectorWidth : 0)
        height: nodeHeight + connectorDepth
        z: Math.round((1.0 - depthProgress) * 1000)

        BlockTile {
            id: blockTile
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (-parent.connectorDepth / 2) + parent.nodeLift
            width: nodeWidth
            height: nodeHeight
            blk: parent.blk
            depthProgress: parent.depthProgress
            opacity: parent.nodeFade
            layer.enabled: true
            transform: [
                Translate { x: blockTile.parent.nodeInset },
                Scale {
                    origin.x: blockTile.width / 2
                    origin.y: blockTile.height / 2
                    xScale: blockTile.parent.nodeScale
                    yScale: blockTile.parent.nodeScale
                }
            ]
            onClicked: parent.clickedBlock()
        }

        Item {
            anchors.left: blockTile.right
            anchors.leftMargin: -8 * parent.depthProgress
            anchors.verticalCenter: blockTile.verticalCenter
            anchors.verticalCenterOffset: 4 * parent.depthProgress
            width: parent.connectorWidth
            height: 10
            visible: parent.showConnector
            opacity: 0.95 - (0.40 * parent.depthProgress)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 14
                height: 10
                radius: 4
                color: Qt.rgba(0.42, 0.56, 0.88, 0.08)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 14
                height: 4
                radius: 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.61, 0.72, 0.88, 0.75) }
                    GradientStop { position: 0.5; color: Qt.rgba(0.86, 0.91, 0.98, 0.95) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.46, 0.58, 0.78, 0.78) }
                }
                opacity: 0.95
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 14
                height: 1
                radius: 1
                color: Qt.rgba(1, 1, 1, 0.35)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                width: 14
                height: 14
                radius: 7
                color: "#dbe6f7"
                border.color: "#f4f8ff"
                border.width: 1
                opacity: 0.95

                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: "#87a1c7"
                }
            }
        }
    }

    component BlockTile: Rectangle {
        id: tileRect
        property var blk
        property real depthProgress: 0.0
        signal clicked()
        readonly property bool isDummyBlock: !!(blk && blk.isDummy)
        readonly property real phase: blk ? ((Math.max(0, Number(blk.height || 0)) % 7) / 7.0) : 0
        readonly property real glowPulse: 0.5 + 0.5 * Math.sin((root.nowMs / 1900.0) + (phase * 6.28318))
        readonly property real accentPulse: 0.5 + 0.5 * Math.sin((root.nowMs / 2200.0) + (phase * 6.28318))
        readonly property real depthX: compactLayout ? 7 : 12
        readonly property real depthY: compactLayout ? 5 : 8
        readonly property color frontColor: isDummyBlock
                                           ? Qt.rgba(0.20, 0.36, 0.31, 0.88)
                                           : ((blk && (blk.height % 2) === 0) ? "#2b3544" : "#313d4f")
        readonly property color sideColor: isDummyBlock ? "#1a2823" : "#212a38"
        readonly property color topColor: isDummyBlock ? "#39584b" : "#445268"
        readonly property color edgeColor: isDummyBlock ? "#77b292" : "#86a0c4"

        radius: 12
        border.color: isDummyBlock ? "#6fa88a" : "#6680a6"
        color: frontColor

        Rectangle {
            x: tileRect.depthX * 0.8
            y: tileRect.height - 12 + tileRect.depthY
            width: tileRect.width - 14
            height: 16
            radius: 8
            color: Qt.rgba(0, 0, 0, tileRect.isDummyBlock ? 0.18 : 0.26)
            opacity: 0.72 - (0.20 * tileRect.depthProgress)
            z: -4
        }

        Rectangle {
            x: tileRect.depthX
            y: tileRect.depthY
            width: tileRect.width - tileRect.depthX
            height: tileRect.height - tileRect.depthY
            radius: tileRect.radius - 2
            color: sideColor
            opacity: 0.96
            z: -3
        }

        Rectangle {
            x: tileRect.depthX * 0.55
            y: tileRect.depthY * 0.55
            width: tileRect.width - tileRect.depthX * 0.55
            height: 16
            radius: 8
            color: topColor
            opacity: 0.92
            z: -2
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: tileRect.isDummyBlock
            color: "transparent"
            border.color: Qt.rgba(0.70, 0.90, 0.82, 0.22 + 0.26 * (1 - root.dummyProgress))
            border.width: 1
            opacity: 0.9
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: !tileRect.isDummyBlock
            color: Qt.rgba(0.45, 0.58, 0.86, 0.06 + 0.03 * tileRect.glowPulse)
            border.color: Qt.rgba(0.76, 0.86, 0.98, 0.24 + 0.08 * tileRect.accentPulse)
            border.width: 1
        }

        Rectangle {
            visible: !tileRect.isDummyBlock
            x: 1
            y: 1
            width: parent.width - 2
            height: Math.max(26, parent.height * 0.34)
            radius: parent.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.96, 0.98, 1.0, 0.16) }
                GradientStop { position: 0.35; color: Qt.rgba(0.96, 0.98, 1.0, 0.05) }
                GradientStop { position: 1.0; color: Qt.rgba(0.96, 0.98, 1.0, 0.01) }
            }
        }

        Rectangle {
            visible: !tileRect.isDummyBlock
            width: parent.width * 0.42
            height: 4
            radius: 2
            x: 12
            y: 8
            color: Qt.rgba(0.82, 0.88, 0.98, 0.28 + 0.12 * tileRect.accentPulse)
        }

        Rectangle {
            visible: !tileRect.isDummyBlock
            x: parent.width - 14
            y: 14
            width: 3
            height: parent.height - 28
            radius: 1.5
            color: Qt.rgba(1.0, 1.0, 1.0, 0.12)
        }

        Rectangle {
            visible: !tileRect.isDummyBlock
            x: 16
            y: parent.height - 16
            width: parent.width - 34
            height: 2
            radius: 1
            color: Qt.rgba(0.10, 0.12, 0.18, 0.48)
        }

        Rectangle {
            visible: !tileRect.isDummyBlock
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            radius: parent.radius
            color: "transparent"
            border.color: edgeColor
            border.width: 1
            opacity: 0.55
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: parent.width - 20
            height: 7
            radius: 4
            visible: tileRect.isDummyBlock
            color: Qt.rgba(0.10, 0.20, 0.14, 0.90)
            border.color: "#2f5b40"
            border.width: 1

            Rectangle {
                width: Math.max(10, (parent.width - 2) * root.dummyProgress)
                height: parent.height - 2
                anchors.left: parent.left
                anchors.leftMargin: 1
                anchors.verticalCenter: parent.verticalCenter
                radius: 3
                color: Qt.rgba(0.54, 0.95, 0.62, 0.75)
                opacity: 0.78 + 0.16 * Math.sin(root.nowMs / 900.0)
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Row {
                spacing: 8
                Label {
                    text: tileRect.isDummyBlock
                          ? "+"
                          : ("#" + (blk ? blk.height : ""))
                    color: tileRect.isDummyBlock ? "#d9ffd8" : "white"
                    font.bold: true
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: tileRect.isDummyBlock ? "#7ee38f" : "#7aa2ff"
                }
                Label {
                    text: tileRect.isDummyBlock
                          ? tr("chain_dummy_title", "Next block")
                          : ((blk && blk.hash) ? blk.hash.substr(0,10) : "")
                    color: tileRect.isDummyBlock ? "#c8f5cf" : "#cfcfcf"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Label {
                text: tileRect.isDummyBlock
                      ? tr("chain_dummy_info", "Click to return to latest blocks")
                      : (blk
                      ? (tr("chain_tile_stats", "In:%1  Out:%2  Ker:%3")
                         .replace("%1", blk.inputs)
                         .replace("%2", blk.outputs)
                         .replace("%3", blk.kernels))
                      : ""
)
                color: "#dddddd"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Label {
                text: tileRect.isDummyBlock
                      ? tr("chain_dummy_height", "Builds on #%1").replace("%1", Math.max(0, tip.height))
                      : ((blk && blk.timestamp)
                      ? new Date(blk.timestamp*1000).toLocaleTimeString()
                      : ""
)
                color: tileRect.isDummyBlock ? "#a7dcb1" : "#aaaaaa"
                font.pixelSize: 11
            }

            Item { Layout.fillHeight: true }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()

            Rectangle {
                anchors.fill: parent
                radius: tileRect.radius
                color: Qt.rgba(1,1,1,0.07)
                visible: parent.containsMouse
            }
        }
    }

    component StatusBar: Rectangle {
        id: sb
        property string message: ""
        property color bgOk: "#173022"
        property color fgOk: "#b6ffd1"
        property color bgErr: "#3a1616"
        property color fgErr: "#ffb6b6"

        height: implicitHeight
        radius: 10
        color: message.length ? bgOk : "transparent"
        border.color: message.length ? "#2a2a2a" : "transparent"
        opacity: message.length ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

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

            DarkButton {
                text: "×"
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
            clearChainView()
        }

        function onNodeRestarted(kind) {
            clearChainView()
            if (nodeRunning && foreignApi) {
                refreshTip()
            }
        }
    }
}
