import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // ---------- API-Handle wie in deiner funktionierenden Datei ----------
    readonly property var foreignApi: nodeForeignApi

    // ---------- Settings ----------
    property int lastCount: 100

    // ---------- Chain state ----------
    property var blocks: []            // oldest → newest
    property string heightInput: ""
    property var tip: ({ height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 })

    // ---------- Details ----------
    property int   detailsHeight: -1
    property var   hdrData: null
    property var   kernelData: null
    property var   outputsData: []

    // ---------- Scroll helper ----------
    property bool _wantScrollRight: false
    function requestScrollRight() {
        _wantScrollRight = true
        if (flick && flick.contentWidth > 0)
            flick.contentX = Math.max(0, flick.contentWidth - flick.width)
    }

    // ---------- Mapping helpers ----------
    function toTip(obj) {
        if (!obj) return { height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 }
        function pick(o, keys) {
            for (var i=0;i<keys.length;i++) {
                var k=keys[i]; if (o.hasOwnProperty(k) && o[k]!==undefined && o[k]!==null) return o[k]
                var lc=k.toLowerCase()
                for (var p in o) if (String(p).toLowerCase()===lc && o[p]!==undefined && o[p]!==null) return o[p]
            }
            return undefined
        }
        var h  = obj.height;            if (h  === undefined) h  = pick(obj, ["height"])
        var lb = obj.lastBlockPushed;   if (lb === undefined) lb = pick(obj, ["lastBlockPushed","last_block_pushed","last_block_h"])
        var pv = obj.prevBlockToLast;   if (pv === undefined) pv = pick(obj, ["prevBlockToLast","prev_block_to_last","prev_block_h"])
        var td = obj.totalDifficulty;   if (td === undefined) td = pick(obj, ["totalDifficulty","total_difficulty"])
        return { height: Number(h||0), lastBlockPushed: String(lb||""), prevBlockToLast: String(pv||""), totalDifficulty: Number(td||0) }
    }

    function mapBlockPrintable(b) {
        if (!b) return null
        var hdr = b.header || b.block_header || b

        // Liefert die Länge, wenn x Array-ähnlich ist, sonst 0
        function countLike(x) {
            if (x === undefined || x === null) return 0
            // QML/Qt kann QVariantList/JS-Array liefern
            if (Array.isArray(x)) return x.length
            // Manche Qt-Container exposen 'length' als Property
            if (typeof x === "object" && "length" in x && typeof x.length === "number")
                return x.length
            return 0
        }
        // Zahl extrahieren, falls schon numerisch vorhanden
        function num(x) { return (typeof x === "number" && isFinite(x)) ? x : 0 }

        // Zähler defensiv bestimmen:
        var txs     = num(b.num_txs)     || num(b.txs)     || countLike(b.txs)     || 0
        var outputs = num(b.outputs)     || num(b.num_outputs) || countLike(b.outputs) || countLike(b.outputsVariant) || 0
        var kernels = num(b.kernels)     || num(b.num_kernels) || countLike(b.kernels) || countLike(b.kernelsVariant) || 0

        // Header-Felder defensiv lesen
        var height     = Number(hdr.height || b.height || 0)
        var hash       = (hdr.hash || hdr.prev_root || b.hash || "")
        var timestamp  = Number(hdr.timestamp || hdr.time || 0)
        var difficulty = Number(hdr.total_difficulty || hdr.difficulty || 0)

        return {
            height: height,
            hash: hash,
            timestamp: timestamp,
            txs: txs,
            outputs: outputs,
            kernels: kernels,
            difficulty: difficulty
        }
    }


    function mapHeaderPrintable(h) {
        var hh = (h && (h.header || h.block_header || h)) || {}

        function toTs(x) {
            if (typeof x === "number" && isFinite(x)) return x
            if (typeof x === "string" && x.length) {
                var n = Number(x); if (isFinite(n)) return n
                var ms = Date.parse(x); if (!isNaN(ms)) return Math.floor(ms/1000)
            }
            return 0
        }
        function toNum(x) { return (typeof x === "number" && isFinite(x)) ? x
                                   : (typeof x === "string" && isFinite(Number(x)) ? Number(x) : 0) }

        // WICHTIG: Nur dot-Access verwenden (GADGET!)
        var height = toNum(hh.height)
        var hash   = hh.hash || ""
        var prev   = hh.previous || hh.prevRoot || ""
        var ts     = toTs(hh.timestamp)          // QString (ISO) oder Zahl
        var td     = toNum(hh.totalDifficulty)   // camelCase in deinem Header
        var kroot  = hh.kernelRoot || ""
        var oroot  = hh.outputRoot || ""

        return {
            height: height,
            hash: hash,
            previous: prev,
            timestamp: ts,
            total_difficulty: td,
            kernel_root: kroot,
            output_root: oroot
        }
    }

    function mapOutputPrintableList(list) {
        var out = []
        if (!list || !list.length) return out
        for (var i=0; i<list.length; ++i) {
            var o = list[i] || {}
            out.push({
                commitment: o.commit || o.commitment || "",
                features: o.features || (o.is_coinbase ? "Coinbase" : "Plain"),
                proof: (o.proof || ""),
                height: Number(o.height || 0)
            })
        }
        return out
    }
    function mapLocatedTxKernel(k) {
        var kk = k || {}
        var kern = kk.tx_kernel || kk.kernel || kk || {}
        return {
            excess: (kern.excess || ""),
            excess_sig: (kern.excess_sig || ""),
            fee: Number(kern.fee || 0),
            lock_height: Number(kern.lock_height || 0),
            height: Number(kk.height || 0)
        }
    }

    function mapBlockListing(listing) {
        var arrSrc = (listing && (listing.blocksVariant || listing.blocks || listing.items || listing)) || []
        var out = []
        for (var i = 0; i < arrSrc.length; ++i)
            out.push(mapBlockPrintable(arrSrc[i]))
        out.sort(function(a,b){ return a.height - b.height })
        return out
    }


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
    function selectNewestForDetails() {
        if (blocks.length === 0) { detailsHeight = -1; return }
        detailsHeight = blocks[blocks.length - 1].height
        if (foreignApi && detailsHeight >= 0) {
            hdrData = null; kernelData = null; outputsData = []
            Qt.callLater(function(){ try { foreignApi.getHeaderAsync(detailsHeight, "", "") } catch(e) { status.showError("getHeaderAsync: " + e) } })
        }
    }
    function openDetails(h) {
        var hh = Number(h)            // <— Zahl erzwingen
        if (!isFinite(hh) || hh < 0) {
            status.showError("Ungültige Block-Höhe")
            return
        }
        detailsHeight = hh
        if (foreignApi) {
            hdrData = null; kernelData = null; outputsData = []
            try {
                foreignApi.getHeaderAsync(hh, "", "")
                console.log("[QML] getHeaderAsync(", hh, ")")
            } catch(e) {
                status.showError("getHeaderAsync: " + e)
            }
        }
    }

    // ---------- Lifecycle ----------
    Component.onCompleted: refreshTip()
    onForeignApiChanged: if (foreignApi) refreshTip()

    // ---------- Signals (nur „Updated“-Signale nutzen) ----------
    Connections {
        target: (typeof foreignApi === "object" && foreignApi) ? foreignApi : null
        ignoreUnknownSignals: true

        // genau wie in deiner funktionierenden Datei
        function onTipUpdated(payload) {
            tip = toTip(payload)

            if (tip.height > 0) {
                // erst dann Blöcke holen (entkoppelt)
                Qt.callLater(function(){ loadBlocksForTip(tip.height) })
            } else {
                // Keine Folge-Calls bei leerem Tip
                blocks = []
                detailsHeight = -1
                hdrData = null; kernelData = null; outputsData = []
            }
        }

        // NEU: QML-fertige Liste
        function onBlocksUpdated(list, lastHeight) {
            // mapBlockListing akzeptiert ein Objekt mit blocksVariant
            var arr = mapBlockListing({ blocksVariant: list })
            if (!arr || arr.length === 0) {
                blocks = []
                detailsHeight = -1
                hdrData = null; kernelData = null; outputsData = []
                status.show("Keine Blöcke empfangen")
                return
            }
            blocks = arr
            requestScrollRight()
            selectNewestForDetails()
        }

        function onHeaderUpdated(hdr) {
            // Dot-Access – jetzt sicher
            var ts = (typeof hdr.timestamp === "number") ? hdr.timestamp
                     : (typeof hdr.timestamp === "string" ? Math.floor(Date.parse(hdr.timestamp)/1000) : 0)

            hdrData = {
                height: Number(hdr.height || 0),
                hash:   String(hdr.hash || ""),
                previous: String(hdr.previous || hdr.prevRoot || ""),
                timestamp: Number(ts || 0),
                total_difficulty: Number(hdr.totalDifficulty || 0),
                kernel_root: String(hdr.kernelRoot || ""),
                output_root: String(hdr.outputRoot || "")
            }

            console.log("[QML] header h/hash/ts/td =",
                        hdrData.height, hdrData.hash, hdrData.timestamp, hdrData.total_difficulty)
        }



        function onGetKernelFinished(r) {
            if (r && typeof r.hasError === "function" && r.hasError()) {
                status.showError(typeof r.errorString === "function" ? r.errorString() : "getKernel failed"); return
            }
            var v = (r && typeof r.value === "function") ? r.value() : (r && r.value)
            kernelData = mapLocatedTxKernel(v)
        }

        function onGetOutputsFinished(r) {
            if (r && typeof r.hasError === "function" && r.hasError()) {
                status.showError(typeof r.errorString === "function" ? r.errorString() : "getOutputs failed"); return
            }
            var v = (r && typeof r.value === "function") ? r.value() : (r && r.value)
            outputsData = mapOutputPrintableList(v)
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

            DarkTextField {
                id: heightField
                placeholderText: "Block height…"
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 2147483647 }
                text: heightInput
                onTextChanged: heightInput = text
                Layout.preferredWidth: 140
            }
            DarkButton {
                text: "Load"
                enabled: heightField.acceptableInput && heightField.text.length>0
                onClicked: {
                    var h = parseInt(heightField.text)
                    if (!isNaN(h) && h >= 0) openDetails(h)
                }
            }
            DarkButton { text: "Refresh"; onClicked: refreshTip() }
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

                onContentWidthChanged: _applyScrollRight()
                onWidthChanged: _applyScrollRight()
                function _applyScrollRight() {
                    if (_wantScrollRight && contentWidth > 0) {
                        Qt.callLater(function() {
                            contentX = Math.max(0, contentWidth - width)
                            _wantScrollRight = false
                        })
                    }
                }

                Row {
                    id: chainRow
                    spacing: 0
                    height: parent.height
                    onImplicitWidthChanged: flick._applyScrollRight()

                    Repeater {
                        model: Array.isArray(blocks) ? blocks.length : 0
                        delegate: ChainNode {
                            nodeWidth: 220
                            nodeHeight: 120
                            connectorWidth: 48
                            blk: blocks[index]
                            showConnector: index < (blocks.length - 1)
                            // im Repeater-Delegate:
                            onClickedBlock: {
                                // Debug hilft sofort zu sehen, ob der Klick feuert + welchen Wert wir schicken
                                console.log("[QML] clicked height =", blk && blk.height)
                                openDetails(blk && blk.height)
                            }
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
                    DarkButton {
                        text: "Header neu laden"
                        onClicked: {
                            if (detailsHeight >= 0 && foreignApi)
                                Qt.callLater(function(){ try { foreignApi.getHeaderAsync(detailsHeight, "", "") } catch(e) { status.showError("getHeaderAsync: " + e) } })
                        }
                    }
                }

                TabBar {
                    id: tabsBar
                    Layout.fillWidth: true
                    currentIndex: 0
                    background: Rectangle { radius: 8; color: "#151515"; border.color: "#2a2a2a"; height: parent.height }
                    DarkTabButton { text: "Header" }
                    DarkTabButton { text: "Kernel" }
                    DarkTabButton { text: "Outputs" }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: tabsBar.currentIndex

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

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                DarkTextField { id: excessField; placeholderText: "excess (hex)…"; Layout.fillWidth: true; text: "" }
                                DarkTextField {
                                    id: minH; placeholderText: "min height"
                                    validator: IntValidator { bottom: 0; top: 2147483647 }
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    text: detailsHeight >= 0 ? String(Math.max(detailsHeight - 100, 0)) : "0"
                                    Layout.preferredWidth: 120
                                }
                                DarkTextField {
                                    id: maxH; placeholderText: "max height"
                                    validator: IntValidator { bottom: 0; top: 2147483647 }
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    text: detailsHeight >= 0 ? String(detailsHeight) : "0"
                                    Layout.preferredWidth: 120
                                }
                                DarkButton {
                                    text: "Kernel laden"
                                    onClicked: {
                                        if (detailsHeight < 0 || !foreignApi || !excessField.text.length) return
                                        Qt.callLater(function(){ try { foreignApi.getKernelAsync(excessField.text, parseInt(minH.text||"0"), parseInt(maxH.text||"0")) } catch(e) { status.showError("getKernelAsync: " + e) } })
                                    }
                                }
                            }
                            Frame {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                background: Rectangle { color: "#141414"; radius: 10; border.color: "#2a2a2a" }
                                padding: 10
                                Column {
                                    anchors.fill: parent; spacing: 6
                                    Label { text: kernelData ? "Excess: " + kernelData.excess : "—"; color: "#ddd" }
                                    Label { text: kernelData ? "Excess sig: " + kernelData.excess_sig : ""; color: "#bbb" }
                                    Label { text: kernelData ? "Fee: " + kernelData.fee : ""; color: "#bbb" }
                                    Label { text: kernelData ? "Lock height: " + kernelData.lock_height : ""; color: "#bbb" }
                                    Label { text: kernelData && kernelData.height ? "Found at height: " + kernelData.height : ""; color: "#bbb" }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                DarkTextArea {
                                    id: commitsArea
                                    placeholderText: "commitments (hex), getrennt durch Komma/Leerzeichen/Zeilenumbruch"
                                    Layout.fillWidth: true; Layout.preferredHeight: 70
                                    wrapMode: TextEdit.WrapAnywhere
                                }
                                ColumnLayout {
                                    spacing: 6
                                    DarkTextField {
                                        id: outMinH; placeholderText: "min height"
                                        validator: IntValidator { bottom: 0; top: 2147483647 }
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        text: detailsHeight >= 0 ? String(Math.max(detailsHeight - 100, 0)) : "0"
                                        Layout.preferredWidth: 120
                                    }
                                    DarkTextField {
                                        id: outMaxH; placeholderText: "max height"
                                        validator: IntValidator { bottom: 0; top: 2147483647 }
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        text: detailsHeight >= 0 ? String(detailsHeight) : "0"
                                        Layout.preferredWidth: 120
                                    }
                                    RowLayout {
                                        spacing: 6
                                        CheckBox {
                                            id: includeProof; text: "Proof"; checked: false
                                            indicator: Rectangle { implicitWidth: 18; implicitHeight: 18; radius: 3; color: includeProof.checked ? "#3a6df0" : "#2b2b2b"; border.color: "#555" }
                                            contentItem: Text { text: includeProof.text; color: "#ddd"; verticalAlignment: Text.AlignVCenter }
                                            background: null
                                        }
                                        CheckBox {
                                            id: includeMerkle; text: "Merkle"; checked: false
                                            indicator: Rectangle { implicitWidth: 18; implicitHeight: 18; radius: 3; color: includeMerkle.checked ? "#3a6df0" : "#2b2b2b"; border.color: "#555" }
                                            contentItem: Text { text: includeMerkle.text; color: "#ddd"; verticalAlignment: Text.AlignVCenter }
                                            background: null
                                        }
                                    }
                                    DarkButton {
                                        text: "Outputs laden"
                                        onClicked: {
                                            if (detailsHeight < 0 || !foreignApi) return
                                            var commits = []
                                            var raw = commitsArea.text.split(/[, \n]+/)
                                            for (var i=0;i<raw.length;i++) {
                                                var c = raw[i].trim(); if (c.length) commits.push(c)
                                            }
                                            Qt.callLater(function(){
                                                try {
                                                    foreignApi.getOutputsAsync(
                                                        commits,
                                                        parseInt(outMinH.text||"0"),
                                                        parseInt(outMaxH.text||"0"),
                                                        includeProof.checked,
                                                        includeMerkle.checked
                                                    )
                                                } catch(e) { status.showError("getOutputsAsync: " + e) }
                                            })
                                        }
                                    }
                                }
                            }
                            Frame {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                background: Rectangle { color: "#141414"; radius: 10; border.color: "#2a2a2a" }
                                padding: 10

                                Flickable {
                                    anchors.fill: parent
                                    contentWidth: parent.width
                                    contentHeight: outCol.implicitHeight
                                    clip: true

                                    Column {
                                        id: outCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        spacing: 8

                                        Repeater {
                                            model: outputsData
                                            delegate: Rectangle {
                                                radius: 8
                                                color: "#1a1a1a"
                                                border.color: "#2a2a2a"
                                                width: parent.width
                                                height: column.implicitHeight + 12

                                                Column {
                                                    id: column
                                                    anchors.fill: parent
                                                    anchors.margins: 8
                                                    spacing: 4
                                                    Label { text: "Commitment: " + (modelData.commitment || "—"); color: "#ddd" }
                                                    Label { text: "Features: " + (modelData.features || "—"); color: "#bbb" }
                                                    Label { text: "Height: " + (modelData.height || "—"); color: "#bbb" }
                                                    Label { visible: !!modelData.proof; text: "Proof: " + modelData.proof; color: "#777" }
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

        // Hinweis solange nichts da ist
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
    component DarkTextArea: TextArea {
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
