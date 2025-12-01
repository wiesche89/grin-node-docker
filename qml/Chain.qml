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
    function headerOf(rb) {
        var h = get(rb,"header",null)
        if (!h) h = get(rb,"block_header",null)
        return h || {}
    }

    // ---------------------------------------------------
    // Mapping: full block -> row tile
    // ---------------------------------------------------
    function simplifyBlockForRow(rb) {
        var h = headerOf(rb)
        function count(x){ return Array.isArray(x) ? x.length : (x && typeof x.length === "number" ? x.length : 0) }
        return {
            height: toNum(get(h,"height",0)),
            hash: String(get(h,"hash","")),
            timestamp: toTs(get(h,"timestamp",0)),
            txs: toNum(get(rb,"num_txs",0)),
            outputs: count(get(rb,"outputs",[])),
            kernels: count(get(rb,"kernels",[])),
            difficulty: toNum(get(h,"total_difficulty", get(h,"totalDifficulty",0)))
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
                out.push({ commit: it })
            } else {
                out.push({
                    commit: get(it,"commit",get(it,"commitment","")),
                    height: toNum(get(it,"height",get(it,"block_height",0))),
                    spent: !!get(it,"spent",false)
                })
            }
        }
        return out
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
    property var selectedRaw: (selectedIndex >= 0 && selectedIndex < blocksRaw.length) ? blocksRaw[selectedIndex] : null
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
                Qt.callLater(function(){ loadBlocksForTip(tip.height) })
            } else {
                blocksRaw = []
                blocks = []
                selectedIndex = -1
            }
        }

        function onBlocksUpdated(list, lastHeight) {
            blocksRaw = list || []

            var simple = []
            for (var i = 0; i < blocksRaw.length; ++i) {
                var s = simplifyBlockForRow(blocksRaw[i])
                s.rawIndex = i
                simple.push(s)
            }
            simple.sort(function(a,b){ return a.height - b.height })
            blocks = simple

            selectedIndex = (blocksRaw.length > 0) ? (blocksRaw.length - 1) : -1

            // Scroll all the way to the right when new blocks arrive
            Qt.callLater(function() {
                flick.contentX = Math.max(0, flick.contentWidth - flick.width)
            })
        }
    }

    // ---------------------------------------------------
    // UI layout
    // ---------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: compactLayout ? 12 : 20
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

        // ----------------------- Chain tiles row -----------------------
        Frame {
            Layout.fillWidth: true
            Layout.preferredHeight: 170
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
                interactive: true

                contentWidth: Math.max(chainRow.implicitWidth, width)
                contentHeight: height

                Row {
                    id: chainRow
                    spacing: 0
                    height: parent.height

                    Repeater {
                        model: Array.isArray(blocks) ? blocks.length : 0
                        delegate: ChainNode {
                            nodeWidth: 220
                            nodeHeight: 120
                            connectorWidth: 48
                            blk: blocks[index]
                            showConnector: index < (blocks.length - 1)
                            onClickedBlock: root.selectedIndex = blk.rawIndex
                        }
                    }

                    // Scroll immediately to the right when width changes
                    onImplicitWidthChanged: {
                        if (blocks.length > 0) {
                            flick.contentX = Math.max(0, flick.contentWidth - flick.width)
                        }
                    }
                }

                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }

        // ----------------------- Details area -----------------------
        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                    currentIndex: tabsBar.currentIndex

                    // ---- Header tab ----
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ScrollView {
                            anchors.fill: parent
                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                Label {
                                    text: hdrData
                                          ? tr("chain_hdr_hash_prefix", "Hash: ") + (hdrData.hash || "")
                                          : ""
                                    color: "#ddd"
                                }
                                Label {
                                    text: hdrData
                                          ? tr("chain_hdr_prev_prefix", "Previous: ") + (hdrData.previous || "")
                                          : ""
                                    color: "#bbb"
                                }
                                Label {
                                    text: hdrData
                                          ? tr("chain_hdr_total_diff_prefix", "Total difficulty: ") + hdrData.total_difficulty
                                          : ""
                                    color: "#bbb"
                                }
                                Label {
                                    text: hdrData && hdrData.timestamp
                                          ? tr("chain_hdr_time_prefix", "Time: ")
                                            + new Date(hdrData.timestamp*1000).toLocaleString()
                                          : ""
                                    color: "#bbb"
                                }
                                Label {
                                    text: hdrData && hdrData.kernel_root
                                          ? tr("chain_hdr_kernel_root_prefix", "Kernel root: ") + hdrData.kernel_root
                                          : ""
                                    color: "#bbb"
                                }
                                Label {
                                    text: hdrData && hdrData.output_root
                                          ? tr("chain_hdr_output_root_prefix", "Output root: ") + hdrData.output_root
                                          : ""
                                    color: "#bbb"
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

                                                Label {
                                                    text: tr("chain_input_commit_prefix", "Commit: ")
                                                          + (modelData.commit || "")
                                                    color: "#ddd"
                                                }
                                                Label {
                                                    visible: (modelData.height || 0) > 0
                                                    text: tr("chain_input_height_prefix", "Height: ") + modelData.height
                                                    color: "#bbb"
                                                }
                                                Label {
                                                    visible: modelData.spent !== undefined
                                                    text: tr("chain_input_spent_prefix", "Spent: ")
                                                          + (modelData.spent
                                                             ? tr("common_yes", "yes")
                                                             : tr("common_no", "no"))
                                                    color: "#bbb"
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

                                                Label {
                                                    text: tr("chain_output_type_prefix", "Type: ")
                                                          + get(modelData, "output_type", "")
                                                    color: "#bbb"
                                                }

                                                Label {
                                                    text: tr("chain_output_height_prefix", "Height: ")
                                                          + get(modelData, "height", "")
                                                    color: "#bbb"
                                                }

                                                Label {
                                                    text: tr("chain_output_mmr_index_prefix", "MMR index: ")
                                                          + get(modelData, "mmr_index", "")
                                                    color: "#bbb"
                                                }

                                                Label {
                                                    text: tr("chain_output_spent_prefix", "Spent: ")
                                                          + (get(modelData, "spent", false)
                                                             ? tr("common_yes", "yes")
                                                             : tr("common_no", "no"))
                                                    color: "#bbb"
                                                }

                                                Label {
                                                    visible: !!get(modelData, "proof_hash", "")
                                                    text: tr("chain_output_proof_hash_prefix", "Proof hash: ")
                                                          + get(modelData, "proof_hash", "")
                                                    color: "#777"
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

                                                Label {
                                                    text: tr("chain_kernel_features_prefix", "Features: ")
                                                          + (modelData.features || "")
                                                    color: "#ddd"
                                                }
                                                Label {
                                                    text: tr("chain_kernel_fee_prefix", "Fee: ")
                                                          + modelData.fee
                                                    color: "#bbb"
                                                }
                                                Label {
                                                    text: tr("chain_kernel_lock_height_prefix", "Lock height: ")
                                                          + modelData.lock_height
                                                    color: "#bbb"
                                                }
                                                Label {
                                                    text: tr("chain_kernel_excess_prefix", "Excess: ")
                                                          + (modelData.excess || "")
                                                    color: "#bbb"
                                                    wrapMode: Text.WrapAnywhere
                                                }
                                                Label {
                                                    text: tr("chain_kernel_excess_sig_prefix", "Excess sig: ")
                                                          + (modelData.excess_sig || "")
                                                    color: "#777"
                                                    wrapMode: Text.WrapAnywhere
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

    component ChainNode: Item {
        property var blk
        property bool showConnector: true
        property int nodeWidth: 220
        property int nodeHeight: 120
        property int connectorWidth: 48
        signal clickedBlock()

        width: nodeWidth + (showConnector ? connectorWidth : 0)
        height: nodeHeight

        BlockTile {
            id: blockTile
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: nodeWidth
            height: nodeHeight
            blk: parent.blk
            onClicked: parent.clickedBlock()
        }

        Item {
            anchors.left: blockTile.right
            anchors.verticalCenter: blockTile.verticalCenter
            width: parent.connectorWidth
            height: 8
            visible: parent.showConnector

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                height: 4
                radius: 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#ffea70" }
                    GradientStop { position: 1.0; color: "#ffcc33" }
                }
                opacity: 0.9
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                width: 12
                height: 12
                rotation: 45
                color: "#ffcc33"
                border.color: "#ffee88"
                border.width: 1
                opacity: 0.95
                radius: 1
            }
        }
    }

    component BlockTile: Rectangle {
        id: tileRect
        property var blk
        signal clicked()

        radius: 12
        border.color: "#2a2a2a"
        color: (blk && (blk.height % 2) === 0) ? "#171a20" : "#1b1f27"

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Row {
                spacing: 8
                Label {
                    text: "#" + (blk ? blk.height : "")
                    color: "white"
                    font.bold: true
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: "#7aa2ff"
                }
                Label {
                    text: (blk && blk.hash) ? blk.hash.substr(0,10) : ""
                    color: "#cfcfcf"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Label {
                text: blk
                      ? (tr("chain_tile_stats", "Tx:%1  Out:%2  Ker:%3")
                         .replace("%1", blk.txs)
                         .replace("%2", blk.outputs)
                         .replace("%3", blk.kernels))
                      : ""
                color: "#dddddd"
                font.pixelSize: 12
            }

            Label {
                text: (blk && blk.timestamp)
                      ? new Date(blk.timestamp*1000).toLocaleTimeString()
                      : ""
                color: "#aaaaaa"
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
