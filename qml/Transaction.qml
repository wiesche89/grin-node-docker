import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    // In main.cpp gesetzt: engine.rootContext()->setContextProperty("nodeForeignApi", api);
    readonly property var foreignApi: nodeForeignApi
    property int refreshIntervalMs: 8000

    // ---- UI-State
    property int poolSize: 0
    property int stempoolSize: 0
    property var tip: ({ height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 })
    property var entries: []   // nur Pool-Transaktionen

    // ---------- Helper: robustes Tip-Mapping aus beliebiger Payload ----------
    function toTip(obj) {
        // akzeptiere Q_GADGET (QML-Value), QVariantMap, JS-Objekt
        if (!obj) return { height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 }

        // Direkter Zugriff
        var h = obj.height
        var lb = obj.lastBlockPushed || obj.last_block_pushed || obj.last_block_h
        var pv = obj.prevBlockToLast || obj.prev_block_to_last || obj.prev_block_h
        var td = obj.totalDifficulty || obj.total_difficulty

        // Falls Q_GADGET-Felder nicht als Properties sichtbar wären, versuche stringifier
        // (u. U. liefert dein C++-Side schon ein QJsonObject -> dann oben ok)
        // Noch defensiver: Keys-case-insensitive prüfen
        function pick(o, keys) {
            for (var i=0;i<keys.length;i++) {
                var k = keys[i]
                if (o.hasOwnProperty(k) && o[k] !== undefined && o[k] !== null) return o[k]
                // versuch auch lower-case match
                var lc = k.toLowerCase()
                for (var p in o) {
                    if (String(p).toLowerCase() === lc && o[p] !== undefined && o[p] !== null) return o[p]
                }
            }
            return undefined
        }
        if (h === undefined) h  = pick(obj, ["height"])
        if (lb === undefined) lb = pick(obj, ["lastBlockPushed","last_block_pushed","last_block_h"])
        if (pv === undefined) pv = pick(obj, ["prevBlockToLast","prev_block_to_last","prev_block_h"])
        if (td === undefined) td = pick(obj, ["totalDifficulty","total_difficulty"])

        return {
            height: Number(h || 0),
            lastBlockPushed: lb ? String(lb) : "",
            prevBlockToLast: pv ? String(pv) : "",
            totalDifficulty: Number(td || 0)
        }
    }

    // ---------------- API: Mapping-Helfer ----------------
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
            out.push({ id: id, fee: fee, weight: weight, inputs: inputs, outputs: outputs, kernels: kernels })
        }
        return out
    }

    // ---------------- API: Aufrufe ----------------
    function refreshAll() {
        if (!foreignApi) { status.showError("Foreign API nicht gesetzt."); return }
        try {
            foreignApi.getTipAsync()
            foreignApi.getPoolSizeAsync()
            foreignApi.getStempoolSizeAsync()
            foreignApi.getUnconfirmedTransactionsAsync()
            // kein Status.show hier, sonst spammt's beim Auto-Polling
        } catch (e) {
            status.showError("API-Fehler: " + e)
        }
    }

    // Auto-Polling
    Timer {
        id: pollTimer
        interval: refreshIntervalMs
        repeat: true
        running: !!foreignApi
        onTriggered: refreshAll()
    }

    Component.onCompleted: refreshAll()
    onForeignApiChanged: {
        pollTimer.running = !!foreignApi
        if (foreignApi) refreshAll()
    }

    // ---------------- Signale der Foreign API ----------------
    Connections {
        target: (typeof foreignApi === "object" && foreignApi) ? foreignApi : null
        ignoreUnknownSignals: true

        function onPoolSizeUpdated(size) { poolSize = Number(size || 0) }
        function onStempoolSizeUpdated(size) { stempoolSize = Number(size || 0) }

        // Robust: egal ob Tip als Gadget/Map kommt
        function onTipUpdated(payload) {
            // Debug-Ausgabe einmal aktiv lassen – hilft sofort beim Verifizieren
            // (kannst du später entfernen)
            // console.debug("[Transaction.qml] tipUpdated payload =", payload)
            tip = toTip(payload)
        }

        function onUnconfirmedTransactionsUpdated(list) {
            entries = mapPoolEntries(list)
        }
    }

    // ---------------------------------------------
    // Custom Dark Button
    // ---------------------------------------------
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

    // ---------------------------------------------
    // Layout
    // ---------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                text: "Transaction"
                color: "white"
                font.pixelSize: 28
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Loader {
                id: refreshBtn
                sourceComponent: darkButtonComponent
                onLoaded: {
                    if (!refreshBtn.item) return
                    refreshBtn.item.text = "Refresh"
                    refreshBtn.item.clicked.connect(function() {
                        status.show("Aktualisiere …")
                        refreshAll()
                    })
                }
            }
        }

        // TIP-KARTE
        TipCard {
            Layout.fillWidth: true
            tipHeight: tip.height
            lastBlockPushed: tip.lastBlockPushed
            prevBlockToLast: tip.prevBlockToLast
            totalDifficulty: tip.totalDifficulty
        }

        // Infochips Pool/Stempool
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            InfoChip { label: "Pool"; value: poolSize }
            InfoChip { label: "Stempool"; value: stempoolSize }
            Item { Layout.fillWidth: true }
        }

        // Hinweis
        Label {
            Layout.fillWidth: true
            text: "Hinweis: Stempool-Transaktionen werden aus Privacy-Gründen nicht gelistet; unten siehst du nur den (geflufften) Pool."
            color: "#888"
            font.pixelSize: 12
        }

        // Legende
        Row {
            Layout.fillWidth: true
            spacing: 10
            height: 32
            LegendChip { label: "Fee hoch" }
            LegendChip { label: "Fee niedrig"; invert: true }
            LegendChip { label: "Pool"; colorMode: "src-pool" }
            Item { Layout.fillWidth: true }
        }

        // Inhalt (Pool-Transaktionen)
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
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; background: Rectangle { color: "transparent" } }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded; background: Rectangle { color: "transparent" } }
            }
        }

        StatusBar { id: status; Layout.fillWidth: true }
    }

    // ---------- Komponenten ----------

    component TipCard: Rectangle {
        id: tipCard
        property int tipHeight: 0
        property string lastBlockPushed: ""
        property string prevBlockToLast: ""
        property var totalDifficulty: 0

        radius: 12
        color: "#141414"
        border.color: "#2a2a2a"
        border.width: 1
        height: 96

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 18

            ColumnLayout {
                spacing: 2
                Label { text: "Tip Height"; color: "#bbbbbb"; font.pixelSize: 12 }
                Label {
                    text: tipCard.tipHeight > 0 ? tipCard.tipHeight.toLocaleString(Qt.locale(), 'f', 0) : "—"
                    color: "white"; font.pixelSize: 28; font.bold: true
                }
            }

            Rectangle { width: 1; height: parent.height * 0.7; color: "#2d2d2d"; Layout.alignment: Qt.AlignVCenter }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    spacing: 8
                    Label { text: "Last:"; color: "#bbbbbb"; font.pixelSize: 12 }
                    Label {
                        text: tipCard.lastBlockPushed && tipCard.lastBlockPushed.length >= 8
                              ? tipCard.lastBlockPushed.substr(0, 8) + "…" + tipCard.lastBlockPushed.substr(-8)
                              : (tipCard.lastBlockPushed || "—")
                        color: "#eaeaea"; font.family: "Consolas"; font.pixelSize: 14
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }

                RowLayout {
                    spacing: 8
                    Label { text: "Prev:"; color: "#bbbbbb"; font.pixelSize: 12 }
                    Label {
                        text: tipCard.prevBlockToLast && tipCard.prevBlockToLast.length >= 8
                              ? tipCard.prevBlockToLast.substr(0, 8) + "…" + tipCard.prevBlockToLast.substr(-8)
                              : (tipCard.prevBlockToLast || "—")
                        color: "#cfcfcf"; font.family: "Consolas"; font.pixelSize: 14
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
            }

            Rectangle { width: 1; height: parent.height * 0.7; color: "#2d2d2d"; Layout.alignment: Qt.AlignVCenter }

            ColumnLayout {
                spacing: 2
                Label { text: "Total Difficulty"; color: "#bbbbbb"; font.pixelSize: 12 }
                Label {
                    text: Number(tipCard.totalDifficulty || 0).toLocaleString(Qt.locale(), 'f', 0)
                    color: "#ffd46a"; font.pixelSize: 18; font.bold: true
                }
            }
        }
    }

    component InfoChip: Rectangle {
        id: chip
        property string label: ""
        property var value: ""
        radius: 10
        color: "#161616"
        border.color: "#2a2a2a"
        height: 32
        width: Math.max(160, row.implicitWidth + 20)
        Row {
            id: row
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            Label { text: label + ":"; color: "#bbbbbb"; font.pixelSize: 12 }
            Label { text: "" + value; color: "white"; font.bold: true }
        }
    }

    component LegendChip: Rectangle {
        id: chipLegend
        property string label: ""
        property bool invert: false
        property string colorMode: "fee"   // "fee" | "src-pool"
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
                color: colorMode === "src-pool" ? "#ffa657"
                      : (invert ? "#65d365" : "#ffa657")
                border.color: "#111"
            }
            Label { text: chipLegend.label; color: "#ddd" }
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

        radius: 12
        border.color: "#2a2a2a"
        border.width: 1
        color: feeColor()

        function feeColor() {
            var f = Math.max(0, Math.min(1, fee / 100000000.0)) // 0..~1 GRIN
            var alpha = 0.25 + 0.55 * f
            var r = 0.95 - 0.30*(1-f)
            var g = 0.58
            var b = 0.34
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
                Rectangle { width: 6; height: 6; radius: 3; color: "#ffa657" }
                Label { text: "pool"; color: "#bbb"; font.pixelSize: 11; elide: Text.ElideRight }
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
