import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true
    property bool nodeRunning: false

    // ---------- API ----------
    readonly property var foreignApi: nodeForeignApi

    // ---------- Settings ----------
    property int  lastCount: 100
    property bool autoRefresh: true
    property int  refreshIntervalMs: 5000

    // ---------- Chain state ----------
    property var tip: ({ height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 })
    property var blocksRaw: []        // volle Objekte inkl. inputs/outputs/kernels
    property var blocks: []           // vereinfachte Kacheldaten (height/hash/…)

    // ---------- Auswahl / Details (Binding-basiert) ----------
    property int selectedIndex: -1

    // ---------- Helpers ----------
    function get(o, k, dflt) {
        if (o === null || o === undefined) return dflt
        if (o.hasOwnProperty && o.hasOwnProperty(k) && o[k] !== undefined) return o[k]
        if (o[k] !== undefined) return o[k]
        if (k in o) return o[k]
        return dflt
    }
    function toNum(x) { if (typeof x === "number" && isFinite(x)) return x; var n = Number(x); return isFinite(n) ? n : 0 }
    function toTs(x)  { if (typeof x === "number" && isFinite(x)) return x; var ms = Date.parse(x || ""); return isNaN(ms) ? 0 : Math.floor(ms/1000) }
    function headerOf(rb) { var h = get(rb,"header",null); if (!h) h = get(rb,"block_header",null); return h || {} }

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
            if (typeof it === "string") out.push({ commit: it })
            else out.push({ commit: get(it,"commit",get(it,"commitment","")), height: toNum(get(it,"height",get(it,"block_height",0))), spent: !!get(it,"spent",false) })
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

    // ---------- Ableitungen aus Auswahl ----------
    property var selectedRaw: (selectedIndex >= 0 && selectedIndex < blocksRaw.length) ? blocksRaw[selectedIndex] : null
    property var hdrData:     selectedRaw ? mapHeaderFromRaw(selectedRaw)  : null
    property var inputsData:  selectedRaw ? mapInputsFromRaw(selectedRaw)  : []
    property var outputsData: selectedRaw ? mapOutputsFromRaw(selectedRaw) : []
    property var kernelsData: selectedRaw ? mapKernelsFromRaw(selectedRaw) : []
    property int detailsHeight: hdrData ? hdrData.height : -1

    // ---------- API calls ----------
    function refreshTip() {
        if (!foreignApi) { status.showError("Foreign API nicht gesetzt."); return }
        try { foreignApi.getTipAsync() } catch(e) { status.showError("getTipAsync: " + e) }
    }
    function loadBlocksForTip(h) {
        if (!foreignApi) return
        var start = Math.max(0, h - (lastCount - 1))
        try { foreignApi.getBlocksAsync(start, h, lastCount, false) } catch(e) { status.showError("getBlocksAsync: " + e) }
    }

    // ---------- Lifecycle ----------
    Component.onCompleted: if (nodeRunning && foreignApi) refreshTip()
    onForeignApiChanged: if (foreignApi && nodeRunning) refreshTip()

    // ---------- Auto-Refresh ----------
    Timer {
        id: autoTimer
        interval: refreshIntervalMs
        repeat: true
        running: autoRefresh && nodeRunning && !!foreignApi
        onTriggered: if (nodeRunning) refreshTip()
    }

    onNodeRunningChanged: {
        autoTimer.running = autoRefresh && nodeRunning && !!foreignApi
        if (nodeRunning && foreignApi) refreshTip()
    }

    // ---------- Signals ----------
    Connections {
        target: (typeof foreignApi === "object" && foreignApi) ? foreignApi : null
        ignoreUnknownSignals: true

        function onTipUpdated(payload) {
            var t = payload || {}
            var h  = get(t,"height",0)
            var lb = get(t,"lastBlockPushed", get(t,"last_block_pushed",""))
            var pv = get(t,"prevBlockToLast", get(t,"prev_block_to_last",""))
            var td = get(t,"totalDifficulty", get(t,"total_difficulty",0))
            tip = { height: toNum(h), lastBlockPushed: String(lb||""), prevBlockToLast: String(pv||""), totalDifficulty: toNum(td) }

            if (tip.height > 0) Qt.callLater(function(){ loadBlocksForTip(tip.height) })
            else { blocksRaw = []; blocks = []; selectedIndex = -1 }
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

            // Scroll ganz nach rechts, wenn neue Blöcke kommen
            Qt.callLater(function() {
                flick.contentX = Math.max(0, flick.contentWidth - flick.width)
            })
        }
    }

    // ---------- UI ----------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label { text: "Chain"; color: "white"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.preferredWidth: 520
                Layout.preferredHeight: 36
                radius: 10
                color: "#161616"
                border.color: "#2a2a2a"
                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 14
                    Label { text: "Tip:"; color: "#bbbbbb" }
                    Label {
                        text: tip.height > 0
                              ? (tip.height + " • " + (tip.lastBlockPushed && tip.lastBlockPushed.length ? tip.lastBlockPushed.substr(0,10) + "…" : "—"))
                              : "—"
                        color: "white"; font.bold: true
                    }
                    Rectangle { width: 1; height: parent.height * 0.7; color: "#333" }
                    Label { text: "Blocks:"; color: "#bbbbbb" }
                    Label { text: blocks.length; color: "white"; font.bold: true }
                }
            }

            Item { Layout.fillWidth: true }

            // ---- Auto-Refresh Switch + Text (statt CheckBox/Buttons/Feld) ----
            Row {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter

                Switch {
                    id: autoSw
                    checked: autoRefresh
                    onToggled: autoRefresh = checked

                    indicator: Rectangle {
                        implicitWidth: 42
                        implicitHeight: 22
                        radius: 11
                        color: autoSw.checked ? "#3a6df0" : "#2b2b2b"
                        border.color: "#555"

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: autoSw.checked ? parent.width - width - 2 : 2
                            width: 18
                            height: 18
                            radius: 9
                            color: "white"
                        }
                    }

                    contentItem: Item {}   // kein Standardtext
                    background: null
                }

                Label {
                    text: autoSw.checked ? "Auto refresh: ON" : "Auto refresh: OFF"
                    color: "#ddd"
                    anchors.verticalCenter: autoSw.verticalCenter
                }
            }

        }

        Label {
            Layout.fillWidth: true
            text: "Letzte " + lastCount + " Blöcke (links → rechts). Klicke einen Block für Details."
            color: "#bbbbbb"
        }

        Frame {
            Layout.fillWidth: true
            Layout.preferredHeight: 170
            padding: 12
            background: Rectangle { color: "#101010"; radius: 12; border.color: "#252525" }

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

                    // Scroll sofort nach rechts, wenn die Breite neu berechnet wurde
                    onImplicitWidthChanged: {
                        if (blocks.length > 0) {
                            flick.contentX = Math.max(0, flick.contentWidth - flick.width)
                        }
                    }
                }

                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }

        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 12
            background: Rectangle { color: "#121212"; radius: 12; border.color: "#303030" }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: "Details für Block"; color: "#bbb" }
                    Label { text: detailsHeight >= 0 ? ("#" + detailsHeight) : "—"; color: "white"; font.bold: true }
                    Item { Layout.fillWidth: true }
                }

                TabBar {
                    id: tabsBar
                    Layout.fillWidth: true
                    currentIndex: 0
                    background: Rectangle { radius: 8; color: "#151515"; border.color: "#2a2a2a"; height: parent.height }
                    DarkTabButton { text: "Header" }
                    DarkTabButton { text: "Inputs" }
                    DarkTabButton { text: "Outputs" }
                    DarkTabButton { text: "Kernels" }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: tabsBar.currentIndex

                    // Header
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ScrollView {
                            anchors.fill: parent
                            Column {
                                anchors.fill: parent; anchors.margins: 10; spacing: 6
                                Label { text: hdrData ? "Hash: " + (hdrData.hash || "—") : "—"; color: "#ddd" }
                                Label { text: hdrData ? "Previous: " + (hdrData.previous || "—") : ""; color: "#bbb" }
                                Label { text: hdrData ? "Total difficulty: " + hdrData.total_difficulty : ""; color: "#bbb" }
                                Label { text: hdrData && hdrData.timestamp ? "Time: " + new Date(hdrData.timestamp*1000).toLocaleString() : ""; color: "#bbb" }
                                Label { text: hdrData && hdrData.kernel_root ? "Kernel root: " + hdrData.kernel_root : ""; color: "#bbb" }
                                Label { text: hdrData && hdrData.output_root ? "Output root: " + hdrData.output_root : ""; color: "#bbb" }
                            }
                        }
                    }

                    // Inputs
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Frame {
                            anchors.fill: parent
                            background: Rectangle { color: "#141414"; radius: 10; border.color: "#2a2a2a" }
                            padding: 10
                            Flickable {
                                anchors.fill: parent
                                clip: true
                                contentWidth: parent.width
                                contentHeight: inCol.implicitHeight
                                Column {
                                    id: inCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 8
                                    Label { text: inputsData.length + " Inputs"; color: "#ddd" }

                                    Repeater {
                                        model: inputsData
                                        delegate: Rectangle {
                                            radius: 8
                                            color: "#1a1a1a"
                                            border.color: "#2a2a2a"
                                            width: parent.width
                                            implicitHeight: col.implicitHeight + 12
                                            height: implicitHeight

                                            Column {
                                                id: col
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4
                                                Label { text: "Commit: " + (modelData.commit || "—"); color: "#ddd" }
                                                Label { visible: (modelData.height || 0) > 0; text: "Height: " + modelData.height; color: "#bbb" }
                                                Label { visible: modelData.spent !== undefined; text: "Spent: " + (modelData.spent ? "yes" : "no"); color: "#bbb" }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Outputs
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Frame {
                            anchors.fill: parent
                            background: Rectangle { color: "#141414"; radius: 10; border.color: "#2a2a2a" }
                            padding: 10
                            Flickable {
                                anchors.fill: parent
                                clip: true
                                contentWidth: parent.width
                                contentHeight: outCol.implicitHeight
                                Column {
                                    id: outCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 8
                                    Label { text: outputsData.length + " Outputs"; color: "#ddd" }

                                    Repeater {
                                        model: outputsData
                                        delegate: Rectangle {
                                            radius: 8
                                            color: "#1a1a1a"
                                            border.color: "#2a2a2a"
                                            width: parent.width
                                            implicitHeight: col.implicitHeight + 12
                                            height: implicitHeight

                                            Column {
                                                id: col
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4
                                                Label { text: "Commitment: " + (modelData.commitment || "—"); color: "#ddd" }
                                                Label { text: "Type: " + (modelData.output_type || "—"); color: "#bbb" }
                                                Label { text: "Height: " + (modelData.height || "—"); color: "#bbb" }
                                                Label { text: "MMR index: " + (modelData.mmr_index || "—"); color: "#bbb" }
                                                Label { text: "Spent: " + (modelData.spent ? "yes" : "no"); color: "#bbb" }
                                                Label { visible: !!modelData.proof_hash; text: "Proof hash: " + modelData.proof_hash; color: "#777" }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Kernels
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Frame {
                            anchors.fill: parent
                            background: Rectangle { color: "#141414"; radius: 10; border.color: "#2a2a2a" }
                            padding: 10
                            Flickable {
                                anchors.fill: parent
                                clip: true
                                contentWidth: parent.width
                                contentHeight: kerCol.implicitHeight
                                Column {
                                    id: kerCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 8
                                    Label { text: kernelsData.length + " Kernels"; color: "#ddd" }

                                    Repeater {
                                        model: kernelsData
                                        delegate: Rectangle {
                                            radius: 8
                                            color: "#1a1a1a"
                                            border.color: "#2a2a2a"
                                            width: parent.width
                                            implicitHeight: col.implicitHeight + 12
                                            height: implicitHeight

                                            Column {
                                                id: col
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 4
                                                Label { text: "Features: " + (modelData.features || "—"); color: "#ddd" }
                                                Label { text: "Fee: " + modelData.fee; color: "#bbb" }
                                                Label { text: "Lock height: " + modelData.lock_height; color: "#bbb" }
                                                Label { text: "Excess: " + (modelData.excess || "—"); color: "#bbb"; wrapMode: Text.WrapAnywhere }
                                                Label { text: "Excess sig: " + (modelData.excess_sig || "—"); color: "#777"; wrapMode: Text.WrapAnywhere }
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

        Label {
            visible: blocks.length === 0 && tip.height === 0
            text: "Lade Tip …"
            color: "#888"
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        StatusBar { id: status; Layout.fillWidth: true }
    }

    // ---------- Dark UI bits ----------
    component DarkButton: Button {
        id: control
        property color bg: hovered ? "#3a3a3a" : "#2b2b2b"
        property color fg: enabled ? "white" : "#777"
        flat: true
        padding: 10
        background: Rectangle { radius: 6; color: control.down ? "#2f2f2f" : control.bg; border.color: control.down ? "#66aaff" : "#555"; border.width: 1 }
        contentItem: Text { text: control.text; color: control.fg; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    }
    component DarkTabButton: TabButton {
        id: control
        property color bgNormal: hovered ? "#3a3a3a" : "#2b2b2b"
        property color bgChecked: hovered ? "#4a4a4a" : "#3b3b3b"
        property color fg: enabled ? "white" : "#777"
        implicitHeight: 36
        implicitWidth: Math.max(90, contentItem.implicitWidth + 20)
        padding: 10; checkable: true
        background: Rectangle { radius: 6; color: control.checked ? (control.down ? "#353535" : "#3b3b3b") : (control.down ? "#2f2f2f" : "#2b2b2b"); border.color: control.checked ? "#66aaff" : "#555"; border.width: 1 }
        contentItem: Text { text: control.text; color: control.fg; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    }
    component DarkTextField: TextField {
        color: "white"; placeholderTextColor: "#777"; selectionColor: "#3a6df0"; selectedTextColor: "white"
        background: Rectangle { radius: 6; color: "#2b2b2b"; border.color: "#555"; border.width: 1 }
        padding: 8; font.pixelSize: 14
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
        BlockTile { id: tile; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: nodeWidth; height: nodeHeight; blk: parent.blk; onClicked: parent.clickedBlock() }
        Item {
            anchors.left: tile.right; anchors.verticalCenter: tile.verticalCenter
            width: parent.connectorWidth; height: 8; visible: parent.showConnector
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 20; height: 4; radius: 2
                gradient: Gradient { GradientStop { position: 0.0; color: "#ffea70" } GradientStop { position: 1.0; color: "#ffcc33" } }
                opacity: 0.9
            }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; width: 12; height: 12; rotation: 45; color: "#ffcc33"; border.color: "#ffee88"; border.width: 1; opacity: 0.95; radius: 1 }
        }
    }
    component BlockTile: Rectangle {
        property var blk; signal clicked()
        radius: 12; border.color: "#2a2a2a"; color: (blk && (blk.height % 2) === 0) ? "#171a20" : "#1b1f27"
        Column {
            anchors.fill: parent; anchors.margins: 10; spacing: 4
            Row { spacing: 8
                Label { text: "#" + (blk ? blk.height : "—"); color: "white"; font.bold: true }
                Rectangle { width: 6; height: 6; radius: 3; color: "#7aa2ff" }
                Label { text: (blk && blk.hash) ? blk.hash.substr(0,10) + "…" : "—"; color: "#cfcfcf"; font.pixelSize: 12; elide: Text.ElideRight }
            }
            Label { text: (blk ? ("Tx:" + blk.txs + "  Out:" + blk.outputs + "  Ker:" + blk.kernels) : "—"); color: "#dddddd"; font.pixelSize: 12 }
            Label { text: (blk && blk.timestamp) ? new Date(blk.timestamp*1000).toLocaleTimeString() : "—"; color: "#aaaaaa"; font.pixelSize: 11 }
            Item { Layout.fillHeight: true }
        }
        MouseArea {
            anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked(); cursorShape: Qt.PointingHandCursor
            Rectangle { anchors.fill: parent; radius: tile.radius; color: Qt.rgba(1,1,1,0.07); visible: parent.containsMouse }
        }
    }
    component StatusBar: Rectangle {
        id: sb
        property string message: ""
        property color bgOk: "#173022"; property color fgOk: "#b6ffd1"
        property color bgErr: "#3a1616"; property color fgErr: "#ffb6b6"
        height: implicitHeight; radius: 10
        color: message.length ? bgOk : "transparent"
        border.color: message.length ? "#2a2a2a" : "transparent"
        opacity: message.length ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        function show(msg) { message = msg; color = bgOk; label.color = fgOk; hideTimer.restart() }
        function showError(msg) { message = msg; color = bgErr; label.color = fgErr; hideTimer.restart() }
        width: parent.width
        Row { anchors.fill: parent; anchors.margins: 10; spacing: 8
            Label { id: label; text: sb.message; color: sb.fgOk; elide: Text.ElideRight; Layout.fillWidth: true }
            DarkButton { text: "×"; onClicked: sb.message = "" }
        }
        Timer { id: hideTimer; interval: 4000; running: false; onTriggered: sb.message = "" }
    }
}
