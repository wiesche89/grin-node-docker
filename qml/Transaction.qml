import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // engine.rootContext()->setContextProperty("nodeForeignApi", nodeForeignApi);
    property var nodeForeignApi
    property int refreshIntervalMs: 8000

    // Demo/Dummy-Modus
    property bool demoMode: true            // ← auf false setzen, wenn echte API genutzt werden soll
    property int demoCount: 120             // wie viele Dummy-Transaktionen

    // UI-State
    property int poolSize: 0
    property int stempoolSize: 0
    property int tipHeight: 0
    property string tipHash: ""
    property var entries: []   // JS-Array für die Kacheln

    // ---------- Dummy: Generator ----------
    function randInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min }
    function randHex(n) {
        var s = ""; var hex = "0123456789abcdef";
        for (var i=0;i<n;i++) s += hex.charAt(randInt(0,15));
        return s;
    }
    function fillDummy(count) {
        var list = [];
        for (var i=0; i<count; i++) {
            var isStem = Math.random() < 0.25;                   // ~25% in den Stempool
            var feeSat = Math.floor(Math.pow(Math.random(), 0.6) * 2e8); // 0..~2 GRIN, bias hoch
            var weight = randInt(1, 120);
            var inputs = randInt(1, 4);
            var outputs = randInt(1, 6);
            var kernels = randInt(1, 2);
            list.push({
                id: randHex(10) + "-" + i,
                fee: feeSat,
                weight: weight,
                inputs: inputs,
                outputs: outputs,
                kernels: kernels,
                src: isStem ? "stem" : "pool"
            })
        }
        entries = list;
        poolSize = list.length;
        stempoolSize = list.filter(function(x){ return (x.src+"").toLowerCase().indexOf("stem")>=0 }).length;
        tipHeight = 100000 + randInt(0, 50000);
        tipHash = randHex(8) + randHex(8) + randHex(8) + randHex(8);
    }

    // ---------- API-Helper ----------
    function mapPoolEntries(listLike) {
        var out = []
        if (!listLike) return out
        for (var i = 0; i < listLike.length; ++i) {
            var e = listLike[i] || {}
            var tx = e.tx || {}
            var body = tx.body || {}

            var fee = Number(tx.fee || e.fee || 0)
            var weight = Number(tx.weight || e.weight || 0)
            var inputs  = (body.inputs  && body.inputs.length)  || e.inputs  || 0
            var outputs = (body.outputs && body.outputs.length) || e.outputs || 0
            var kernels = (body.kernels && body.kernels.length) || e.kernels || 0
            var id = e.id || tx.tx_id || ("tx-" + i)
            var src = (e.src && (e.src.debug || e.src.origin || e.src)) || "pool"

            out.push({ id: id, fee: fee, weight: weight, inputs: inputs, outputs: outputs, kernels: kernels, src: src })
        }
        return out
    }

    function refreshAll() {
        if (demoMode || !nodeForeignApi) {
            fillDummy(demoCount)
            return
        }
        nodeForeignApi.getTipAsync()
        nodeForeignApi.getPoolSizeAsync()
        nodeForeignApi.getStempoolSizeAsync()
        nodeForeignApi.getUnconfirmedTransactionsAsync()
    }

    Component.onCompleted: refreshAll()
    onNodeForeignApiChanged: { if (!demoMode && nodeForeignApi) refreshAll() }

    Connections {
        id: foreignApiConn
        target: (demoMode ? null : ((typeof nodeForeignApi === "object" && nodeForeignApi) ? nodeForeignApi : null))
        ignoreUnknownSignals: true

        function onPoolSizeUpdated(size) { poolSize = size }
        function onStempoolSizeUpdated(size) { stempoolSize = size }
        function onTipUpdated(tipObj) {
            tipHeight = Number(tipObj.height || 0)
            tipHash = tipObj.last_block_pushed || tipObj.last_block_h || ""
        }
        function onUnconfirmedTransactionsUpdated(list) {
            entries = mapPoolEntries(list)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                text: "Transaction"
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
                    Label { text: "Pool:"; color: "#bbbbbb" }
                    Label { text: poolSize; color: "white"; font.bold: true }
                    Rectangle { width: 1; height: parent.height * 0.7; color: "#333" }
                    Label { text: "Stempool:"; color: "#bbbbbb" }
                    Label { text: stempoolSize; color: "white"; font.bold: true }
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: demoMode ? "Refresh (Dummy)" : "Refresh"
                onClicked: refreshAll()
            }
        }

        // Unterzeile
        Label {
            Layout.fillWidth: true
            text: demoMode
                  ? "Demo-Modus: zufällig generierte Transaktionen."
                  : "Unbestätigte Transaktionen (Pool/Stempool) als Blockübersicht."
            color: "#bbbbbb"
        }

        // Legende
        Row {
            id: legendRow
            Layout.fillWidth: true
            spacing: 10
            height: 32

            LegendChip { label: "Fee hoch" }
            LegendChip { label: "Fee niedrig"; invert: true }
            LegendChip { label: "Stem"; colorMode: "src-stem" }
            LegendChip { label: "Pool"; colorMode: "src-pool" }
            Item { Layout.fillWidth: true }
        }

        // Inhalt
        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 12
            background: Rectangle { color: "#101010"; radius: 12; border.color: "#252525" }

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
                            weight:  entries[index].weight
                            inputs:  entries[index].inputs
                            outputs: entries[index].outputs
                            kernels: entries[index].kernels
                            src:     entries[index].src
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }

        StatusBar { id: status; Layout.fillWidth: true }
    }

    // ---------- Komponenten ----------

    component LegendChip: Rectangle {
        id: chip
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
                width: 16; height: 16; radius: 4
                color: colorMode === "src-stem" ? "#62c2ff"
                      : colorMode === "src-pool" ? "#ffa657"
                      : (invert ? "#65d365" : "#ffa657")
                border.color: "#111"
            }
            Label { text: chip.label; color: "#ddd" }
        }
    }

    component PoolBlock: Rectangle {
        id: block
        property string txId: ""
        property real fee: 0
        property real weight: 0
        property int inputs: 0
        property int outputs: 0
        property int kernels: 0
        property string src: "pool"

        radius: 12
        border.color: "#2a2a2a"
        border.width: 1
        color: feeColor()

        function feeColor() {
            var f = Math.max(0, Math.min(1, fee / 100000000.0))  // Fee als Anteil bis ~1 GRIN
            var alpha = 0.25 + 0.55 * f
            var isStem = src.toString().toLowerCase().indexOf("stem") >= 0
            var r = isStem ? 0.30 : (0.95 - 0.30*(1-f))
            var g = isStem ? 0.70 : 0.58
            var b = isStem ? (0.85 - 0.20*(1-f)) : 0.34
            return Qt.rgba(r, g, b, alpha)
        }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Row { spacing: 6
                Label {
                    text: txId && txId.length ? txId.substr(0,10) + "…" : "Tx"
                    font.bold: true
                    color: "#eee"
                    elide: Text.ElideRight
                }
                Rectangle { width: 6; height: 6; radius: 3; color: src.toLowerCase().indexOf("stem")>=0 ? "#62c2ff" : "#ffa657" }
                Label { text: src; color: "#bbb"; font.pixelSize: 11; elide: Text.ElideRight }
            }

            Row { spacing: 10
                Label { text: "Fee"; color: "#bbb"; font.pixelSize: 11 }
                Label { text: fee.toLocaleString(Qt.locale(), 'f', 0); color: "#eee"; font.pixelSize: 12 }
                Label { text: "W:"; color: "#bbb"; font.pixelSize: 11 }
                Label { text: weight.toString(); color: "#eee"; font.pixelSize: 12 }
            }

            Row { spacing: 12
                Label { text: "in:" + inputs; color: "#ddd"; font.pixelSize: 12 }
                Label { text: "out:" + outputs; color: "#ddd"; font.pixelSize: 12 }
                Label { text: "kern:" + kernels; color: "#ddd"; font.pixelSize: 12 }
            }
        }

        ToolTip.visible: hover.containsMouse
        ToolTip.delay: 180
        ToolTip.text: "Tx: " + (txId || "–")
                      + "\nFee: " + fee
                      + "\nWeight: " + weight
                      + "\nI/O/K: " + inputs + "/" + outputs + "/" + kernels
                      + "\nSrc: " + src

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
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

        function show(msg) { message = msg; color = bgOk; label.color = fgOk; hideTimer.restart() }
        function showError(msg) { message = msg; color = bgErr; label.color = fgErr; hideTimer.restart() }

        width: parent.width
        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            Label { id: label; text: sb.message; color: sb.fgOk; elide: Text.ElideRight; Layout.fillWidth: true }
            Button { text: "×"; onClicked: sb.message = "" }
        }
        Timer { id: hideTimer; interval: 4000; running: false; onTriggered: sb.message = "" }
    }
}
