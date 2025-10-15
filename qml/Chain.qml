import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // ---------------------------
    // C++ instance (NodeForeignApi*)
    // ---------------------------
    property var nodeForeignApi

    // ---------------------------
    // Settings
    // ---------------------------
    property bool useDummyData: true
    property int lastCount: 100

    // ---------------------------
    // Chain state
    // ---------------------------
    property int tipHeight: 0
    property string tipHash: ""
    property var blocks: []            // oldest → newest for left→right
    property string heightInput: ""    // search box

    // ---------------------------
    // Inline details (always visible)
    // ---------------------------
    property int detailsHeight: -1     // currently selected block height
    property var hdrData: null
    property var kernelData: null
    property var outputsData: []

    property bool _wantScrollRight: false

    // --- auto-scroll helper (scroll to far right when blocks update)
    Timer {
        id: scrollRightAfterLayout
        interval: 0
        repeat: false
        onTriggered: {
            if (flick && flick.contentWidth > 0) {
                flick.contentX = Math.max(0, flick.contentWidth - flick.width)
            }
        }
    }

    function requestScrollRight() {
        _wantScrollRight = true
        // try once immediately; if layout not ready yet, the Flickable hooks below will retry
        if (flick && flick.contentWidth > 0)
            flick.contentX = Math.max(0, flick.contentWidth - flick.width)
    }

    // ===========================
    // Dummy data
    // ===========================
    function seedDummyChain(count) {
        tipHeight = 456789
        tipHash = "9f7e1a22cafec0de1234beef7654abcd"

        var arr = []
        for (var i = 0; i < count; ++i) {
            var h = tipHeight - (count - 1 - i) // oldest → newest
            var txs = Math.floor(Math.random()*6)
            var o = Math.floor(2 + Math.random()*8)
            var k = Math.floor(1 + Math.random()*3)
            var ts = Date.now()/1000 - (count - 1 - i)*60
            var hash = (Math.random().toString(16).slice(2,10)
                      + Math.random().toString(16).slice(2,10)
                      + Math.random().toString(16).slice(2,10)).slice(0,64)
            arr.push({
                height: h,
                hash: hash,
                timestamp: ts,
                txs: txs,
                outputs: o,
                kernels: k,
                difficulty: Math.floor(100000 + Math.random()*500000)
            })
        }
        blocks = arr
        // pick newest block for details
        detailsHeight = (blocks.length > 0) ? blocks[blocks.length-1].height : -1
        if (detailsHeight >= 0) {
            seedDummyHeader(detailsHeight)
            seedDummyKernel()
            seedDummyOutputs(Math.floor(3 + Math.random()*6))
        }
        requestScrollRight()
    }

    function seedDummyHeader(h) {
        hdrData = {
            height: h,
            hash: (Math.random().toString(16).slice(2) + Math.random().toString(16).slice(2)).slice(0,64),
            previous: (Math.random().toString(16).slice(2) + Math.random().toString(16).slice(2)).slice(0,64),
            timestamp: Date.now()/1000,
            total_difficulty: Math.floor(1e8 + Math.random()*1e8),
            kernel_root: Math.random().toString(16).slice(2, 66),
            output_root: Math.random().toString(16).slice(2, 66)
        }
    }
    function seedDummyKernel() {
        kernelData = {
            excess: Math.random().toString(16).slice(2, 66),
            excess_sig: Math.random().toString(16).slice(2, 130),
            fee: Math.floor(Math.random()*2e8),
            lock_height: 0,
            height: detailsHeight
        }
    }
    function seedDummyOutputs(n) {
        var out = []
        for (var i = 0; i < n; ++i) {
            out.push({
                commitment: Math.random().toString(16).slice(2, 66),
                features: (Math.random() < 0.2) ? "Coinbase" : "Plain",
                proof: (Math.random() < 0.3) ? "(range proof …)" : "",
                height: detailsHeight
            })
        }
        outputsData = out
    }

    // ===========================
    // Mapping (real API → light JS)
    // ===========================
    function mapBlockPrintable(b) {
        if (!b) return null
        var hdr = b.header || b.block_header || b
        return {
            height: Number(hdr.height || b.height || 0),
            hash:   (hdr.hash || hdr.prev_root || b.hash || ""),
            timestamp: Number(hdr.timestamp || hdr.time || 0),
            txs: Number((b.txs && b.txs.length) || b.num_txs || 0),
            outputs: Number(b.outputs || 0),
            kernels: Number(b.kernels || 0),
            difficulty: Number(hdr.total_difficulty || hdr.difficulty || 0)
        }
    }
    function mapHeaderPrintable(h) {
        var hdr = h || {}
        var hh = hdr.header || hdr.block_header || hdr
        return {
            height: Number(hh.height || 0),
            hash:   (hh.hash || ""),
            previous: (hh.previous || hh.prev_root || ""),
            timestamp: Number(hh.timestamp || 0),
            total_difficulty: Number(hh.total_difficulty || 0),
            kernel_root: (hh.kernel_root || ""),
            output_root: (hh.output_root || "")
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
        var kern = kk.tx_kernel || kk.kernel || kk
        return {
            excess: kern.excess || "",
            excess_sig: kern.excess_sig || "",
            fee: Number(kern.fee || 0),
            lock_height: Number(kern.lock_height || 0),
            height: Number(kk.height || 0)
        }
    }
    function mapBlockListing(listing) {
        var arrSrc = listing && (listing.blocks || listing.items || listing)
        var out = []
        if (!arrSrc || !arrSrc.length) return out
        for (var i = 0; i < arrSrc.length; ++i)
            out.push(mapBlockPrintable(arrSrc[i]))
        // oldest → newest for left→right
        out.sort(function(a,b){ return a.height - b.height })
        return out
    }

    // ===========================
    // Data loading
    // ===========================
    function loadLatest() {
        if (useDummyData) { seedDummyChain(lastCount); return }
        if (!nodeForeignApi) return
        if (typeof nodeForeignApi.getTipAsync === "function") {
            nodeForeignApi.getTipAsync()
        } else {
            nodeForeignApi.getBlocksAsync(0, 0, lastCount, false)
        }
    }

    function loadFromTip(tipH) {
        if (!nodeForeignApi) return
        var start = Math.max(0, tipH - (lastCount - 1))
        var end   = tipH
        nodeForeignApi.getBlocksAsync(start, end, lastCount, false)
    }

    function selectNewestForDetails() {
        if (blocks.length === 0) { detailsHeight = -1; return }
        detailsHeight = blocks[blocks.length - 1].height
        if (useDummyData) {
            seedDummyHeader(detailsHeight)
            seedDummyKernel()
            seedDummyOutputs(Math.floor(3 + Math.random()*6))
        } else if (nodeForeignApi) {
            hdrData = null; kernelData = null; outputsData = []
            nodeForeignApi.getHeaderAsync(detailsHeight, "", "")
        }
    }

    function openDetails(height) {
        detailsHeight = height
        if (useDummyData) {
            seedDummyHeader(height)
            seedDummyKernel()
            seedDummyOutputs(Math.floor(3 + Math.random()*6))
        } else if (nodeForeignApi) {
            hdrData = null; kernelData = null; outputsData = []
            nodeForeignApi.getHeaderAsync(height, "", "")
        }
    }

    // ===========================
    // Lifecycle / connections
    // ===========================
    Component.onCompleted: loadLatest()
    onNodeForeignApiChanged: { if (!useDummyData && nodeForeignApi) loadLatest() }

    Connections {
        target: (useDummyData ? null : nodeForeignApi)
        ignoreUnknownSignals: true

        function onTipUpdated(tipObj) {
            tipHeight = Number(tipObj.height || 0)
            tipHash = tipObj.last_block_pushed || tipObj.last_block_h || ""
            if (tipHeight > 0) loadFromTip(tipHeight)
        }
        function onGetBlocksFinished(r) {
            if (r.hasError && r.hasError()) {
                status.showError(r.errorString ? r.errorString() : "getBlocks failed")
                return
            }
            var v = r.value ? r.value() : r.value
            blocks = mapBlockListing(v)
            requestScrollRight()
            selectNewestForDetails()
        }
        function onGetHeaderFinished(r) {
            if (r.hasError && r.hasError()) {
                status.showError(r.errorString ? r.errorString() : "getHeader failed")
                return
            }
            var v = r.value ? r.value() : r.value
            hdrData = mapHeaderPrintable(v)
        }
        function onGetKernelFinished(r) {
            if (r.hasError && r.hasError()) {
                status.showError(r.errorString ? r.errorString() : "getKernel failed")
                return
            }
            var v = r.value ? r.value() : r.value
            kernelData = mapLocatedTxKernel(v)
        }
        function onGetOutputsFinished(r) {
            if (r.hasError && r.hasError()) {
                status.showError(r.errorString ? r.errorString() : "getOutputs failed")
                return
            }
            var v = r.value ? r.value() : r.value
            outputsData = mapOutputPrintableList(v)
        }
    }

    // ===========================
    // UI
    // ===========================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // Header row
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                text: "Chain"
                color: "white"
                font.pixelSize: 28
                font.bold: true
            }

            Rectangle {
                Layout.preferredWidth: 520
                Layout.preferredHeight: 36
                radius: 10
                color: "#161616"
                border.color: "#2a2a2a"
                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 14
                    Label { text: "Tip:"; color: "#bbbbbb" }
                    Label {
                        text: tipHeight > 0 ? (tipHeight + " • " + (tipHash.length ? tipHash.substr(0, 8) + "…" : "—")) : "—"
                        color: "white"; font.bold: true
                    }
                    Rectangle { width: 1; height: parent.height * 0.7; color: "#333" }
                    Label { text: "Blocks:"; color: "#bbbbbb" }
                    Label { text: blocks.length; color: "white"; font.bold: true }
                }
            }

            Item { Layout.fillWidth: true }

            CheckBox {
                id: dummyToggle
                text: "Dummy"
                checked: useDummyData
                onToggled: {
                    useDummyData = checked
                    loadLatest()
                }
                indicator: Rectangle {
                    implicitWidth: 18; implicitHeight: 18; radius: 3
                    color: control.checked ? "#3a6df0" : "#2b2b2b"
                    border.color: "#555"
                }
                contentItem: Text { text: control.text; color: "#ddd"; verticalAlignment: Text.AlignVCenter }
                background: null
            }

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
                    if (!isNaN(h)) openDetails(h)
                }
            }

            DarkButton {
                text: "Refresh"
                onClicked: loadLatest()
            }
        }

        Label {
            Layout.fillWidth: true
            text: "Last " + lastCount + " blocks (left → right). Click a block to show its details below."
            color: "#bbbbbb"
        }

        // Blockchain view: left-to-right with connectors
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

                // Re-try after geometry changes
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
                        id: rep
                        model: Array.isArray(blocks) ? blocks.length : 0

                        delegate: ChainNode {
                            nodeWidth: 220
                            nodeHeight: 120
                            connectorWidth: 48
                            blk: blocks[index]
                            showConnector: index < (blocks.length - 1)
                            onClickedBlock: openDetails(blk.height)
                        }
                    }
                }

                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }

        // Inline details (always visible)
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
                    Label { text: "Details for block"; color: "#bbb" }
                    Label { text: detailsHeight >= 0 ? ("#" + detailsHeight) : "—"; color: "white"; font.bold: true }
                    Item { Layout.fillWidth: true }
                    DarkButton {
                        text: useDummyData ? "Reload (dummy header)" : "Reload header"
                        onClicked: {
                            if (detailsHeight < 0) return
                            if (useDummyData) seedDummyHeader(detailsHeight)
                            else if (nodeForeignApi) nodeForeignApi.getHeaderAsync(detailsHeight, "", "")
                        }
                    }
                }

                // Tabs without TabView: TabBar + StackLayout
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

                    DarkTabButton { text: "Header" }
                    DarkTabButton { text: "Kernel" }
                    DarkTabButton { text: "Outputs" }
                }


                StackLayout {
                    id: tabsStack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: tabsBar.currentIndex

                    // === Header tab ===
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ScrollView {
                            anchors.fill: parent
                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                Label { text: hdrData ? "Hash: " + (hdrData.hash || "—") : "—"; color: "#ddd" }
                                Label { text: hdrData ? "Previous: " + (hdrData.previous || "—") : ""; color: "#bbb" }
                                Label { text: hdrData ? "Total difficulty: " + hdrData.total_difficulty : ""; color: "#bbb" }
                                Label { text: hdrData && hdrData.timestamp ? "Time: " + new Date(hdrData.timestamp*1000).toLocaleString() : ""; color: "#bbb" }
                                Label { text: hdrData && hdrData.kernel_root ? "Kernel root: " + hdrData.kernel_root : ""; color: "#bbb" }
                                Label { text: hdrData && hdrData.output_root ? "Output root: " + hdrData.output_root : ""; color: "#bbb" }
                            }
                        }
                    }

                    // === Kernel tab ===
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                DarkTextField {
                                    id: excessField
                                    placeholderText: "excess (hex)…"
                                    Layout.fillWidth: true
                                    text: ""
                                }
                                DarkTextField {
                                    id: minH
                                    placeholderText: "min height"
                                    validator: IntValidator { bottom: 0; top: 2147483647 }
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    text: detailsHeight >= 0 ? String(Math.max(detailsHeight - 100, 0)) : "0"
                                    Layout.preferredWidth: 120
                                }
                                DarkTextField {
                                    id: maxH
                                    placeholderText: "max height"
                                    validator: IntValidator { bottom: 0; top: 2147483647 }
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    text: detailsHeight >= 0 ? String(detailsHeight) : "0"
                                    Layout.preferredWidth: 120
                                }
                                DarkButton {
                                    text: useDummyData ? "Dummy kernel" : "Load kernel"
                                    onClicked: {
                                        if (detailsHeight < 0) return
                                        if (useDummyData) seedDummyKernel()
                                        else if (nodeForeignApi && excessField.text.length > 0)
                                            nodeForeignApi.getKernelAsync(excessField.text, parseInt(minH.text||"0"), parseInt(maxH.text||"0"))
                                    }
                                }
                            }

                            Frame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                background: Rectangle { color: "#141414"; radius: 10; border.color: "#2a2a2a" }
                                padding: 10

                                Column {
                                    anchors.fill: parent
                                    spacing: 6
                                    Label { text: kernelData ? "Excess: " + kernelData.excess : "—"; color: "#ddd" }
                                    Label { text: kernelData ? "Excess sig: " + kernelData.excess_sig : ""; color: "#bbb" }
                                    Label { text: kernelData ? "Fee: " + kernelData.fee : ""; color: "#bbb" }
                                    Label { text: kernelData ? "Lock height: " + kernelData.lock_height : ""; color: "#bbb" }
                                    Label { text: kernelData && kernelData.height ? "Found at height: " + kernelData.height : ""; color: "#bbb" }
                                }
                            }
                        }
                    }

                    // === Outputs tab ===
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                DarkTextArea {
                                    id: commitsArea
                                    placeholderText: "commitments (hex), separated by comma"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 70
                                    wrapMode: TextEdit.WrapAnywhere
                                }
                                ColumnLayout {
                                    spacing: 6
                                    DarkTextField {
                                        id: outMinH
                                        placeholderText: "min height"
                                        validator: IntValidator { bottom: 0; top: 2147483647 }
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        text: detailsHeight >= 0 ? String(Math.max(detailsHeight - 100, 0)) : "0"
                                        Layout.preferredWidth: 120
                                    }
                                    DarkTextField {
                                        id: outMaxH
                                        placeholderText: "max height"
                                        validator: IntValidator { bottom: 0; top: 2147483647 }
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        text: detailsHeight >= 0 ? String(detailsHeight) : "0"
                                        Layout.preferredWidth: 120
                                    }
                                    RowLayout {
                                        spacing: 6
                                        CheckBox { id: includeProof; text: "Proof"; checked: false
                                            indicator: Rectangle {
                                                implicitWidth: 18; implicitHeight: 18; radius: 3
                                                color: control.checked ? "#3a6df0" : "#2b2b2b"
                                                border.color: "#555"
                                            }
                                            contentItem: Text { text: control.text; color: "#ddd"; verticalAlignment: Text.AlignVCenter }
                                            background: null
                                        }
                                        CheckBox { id: includeMerkle; text: "Merkle"; checked: false
                                            indicator: Rectangle {
                                                implicitWidth: 18; implicitHeight: 18; radius: 3
                                                color: control.checked ? "#3a6df0" : "#2b2b2b"
                                                border.color: "#555"
                                            }
                                            contentItem: Text { text: control.text; color: "#ddd"; verticalAlignment: Text.AlignVCenter }
                                            background: null
                                        }
                                    }
                                    DarkButton {
                                        text: useDummyData ? "Dummy outputs" : "Load outputs"
                                        onClicked: {
                                            if (detailsHeight < 0) return
                                            if (useDummyData) {
                                                seedDummyOutputs(6)
                                            } else if (nodeForeignApi) {
                                                var commits = []
                                                var raw = commitsArea.text.split(/[, \n]+/)
                                                for (var i=0;i<raw.length;i++) {
                                                    var c = raw[i].trim()
                                                    if (c.length) commits.push(c)
                                                }
                                                nodeForeignApi.getOutputsAsync(
                                                    commits,
                                                    parseInt(outMinH.text||"0"),
                                                    parseInt(outMaxH.text||"0"),
                                                    includeProof.checked,
                                                    includeMerkle.checked
                                                )
                                            }
                                        }
                                    }
                                }
                            }

                            Frame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
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

        StatusBar { id: status; Layout.fillWidth: true }
    }

    // ===========================
    // Components
    // ===========================

    // --- Your exact custom dark Button style (as given) ---
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



    // Convenience: use as a normal type
    component DarkButton: Button {
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

    // TabButton im gleichen Dark-Stil wie DarkButton
    // TabButton in the same dark style as DarkButton (no 'flat' prop here)
    component DarkTabButton: TabButton {
        id: control

        // colors
        property color bgNormal: hovered ? "#3a3a3a" : "#2b2b2b"
        property color bgChecked: hovered ? "#4a4a4a" : "#3b3b3b"
        property color fg: enabled ? "white" : "#777"

        // sizing
        implicitHeight: 36
        implicitWidth: Math.max(90, contentItem.implicitWidth + 20)
        padding: 10
        checkable: true   // keep explicit for clarity

        background: Rectangle {
            radius: 6
            color: control.checked
                   ? (control.down ? "#353535" : control.bgChecked)
                   : (control.down ? "#2f2f2f" : control.bgNormal)
            border.color: control.checked ? "#66aaff" : "#555"
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


    // Dark text field / text area to match the button style
    component DarkTextField: TextField {
        id: tf
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

    component DarkTextArea: TextArea {
        id: ta
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

    // Chain node (tile + right connector) — click to open details
    component ChainNode: Item {
        id: node
        property var blk
        property bool showConnector: true
        property int nodeWidth: 220
        property int nodeHeight: 120
        property int connectorWidth: 48
        signal clickedBlock()

        width: nodeWidth + (showConnector ? connectorWidth : 0)
        height: nodeHeight

        BlockTile {
            id: tile
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: nodeWidth
            height: nodeHeight
            blk: node.blk
            onClicked: node.clickedBlock()
        }

        // --- yellow grin-style connector between blocks ---
        Item {
            anchors.left: tile.right
            anchors.verticalCenter: tile.verticalCenter
            width: connectorWidth
            height: 8
            visible: showConnector

            // softly glowing bar
            Rectangle {
                id: bar
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                height: 4
                radius: 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#ffea70" }   // light yellow
                    GradientStop { position: 1.0; color: "#ffcc33" }   // grin gold
                }
                opacity: 0.9
            }

            // arrow head (small diamond shape)
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

    // Block tile (clickable)
    component BlockTile: Rectangle {
        id: tile
        property var blk
        signal clicked()
        radius: 12
        border.color: "#2a2a2a"
        color: tileColor()

        function tileColor() {
            if (!blk) return "#1a1a1a"
            var even = (blk.height % 2) === 0
            return even ? "#171a20" : "#1b1f27"
        }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Row { spacing: 8
                Label { text: "#" + (blk ? blk.height : "—"); color: "white"; font.bold: true }
                Rectangle { width: 6; height: 6; radius: 3; color: "#7aa2ff" }
                Label {
                    text: (blk && blk.hash) ? blk.hash.substr(0,10) + "…" : "—"
                    color: "#cfcfcf"; font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Label { text: (blk ? ("Tx:" + blk.txs + "  Out:" + blk.outputs + "  Ker:" + blk.kernels) : "—"); color: "#dddddd"; font.pixelSize: 12 }
            Label { text: (blk && blk.timestamp) ? new Date(blk.timestamp*1000).toLocaleTimeString() : "—"; color: "#aaaaaa"; font.pixelSize: 11 }

            Item { Layout.fillHeight: true }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: tile.clicked()
            cursorShape: Qt.PointingHandCursor

            Rectangle {
                anchors.fill: parent
                radius: tile.radius
                color: Qt.rgba(1, 1, 1, 0.07)   // leichtes hellgrau-transparent
                visible: parent.containsMouse
            }
        }
    }

    // Status bar
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

        function show(msg) { message = msg; color = bgOk; label.color = fgOk; hideTimer.restart() }
        function showError(msg) { message = msg; color = bgErr; label.color = fgErr; hideTimer.restart() }

        width: parent.width
        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            Label { id: label; text: sb.message; color: sb.fgOk; elide: Text.ElideRight; Layout.fillWidth: true }
            DarkButton { text: "×"; onClicked: sb.message = "" }
        }
        Timer { id: hideTimer; interval: 4000; running: false; onTriggered: sb.message = "" }
    }
}
