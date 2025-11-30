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

    // ------------------------------------------------------------------
    // UI STATE
    // ------------------------------------------------------------------
    property int poolSize: 0
    property int stempoolSize: 0
    property var tip: ({ height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 })
    property var entries: []   // only pool transactions

    // ------------------------------------------------------------------
    // Helper: Robust tip mapping from arbitrary payload
    // ------------------------------------------------------------------
    function toTip(obj) {
        // Accept Q_GADGET (QML value), QVariantMap, plain JS object
        if (!obj)
            return { height: 0, lastBlockPushed: "", prevBlockToLast: "", totalDifficulty: 0 }

        // Direct access if fields are already nice
        var h  = obj.height
        var lb = obj.lastBlockPushed || obj.last_block_pushed || obj.last_block_h
        var pv = obj.prevBlockToLast || obj.prev_block_to_last || obj.prev_block_h
        var td = obj.totalDifficulty  || obj.total_difficulty

        // If Q_GADGET fields are not exposed as properties, fall back to
        // generic key lookup (case-insensitive).
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
    function mapPoolEntries(listLike) {
        var out = []
        if (!listLike)
            return out

        for (var i = 0; i < listLike.length; ++i) {
            var e    = listLike[i] || {}
            var tx   = e.tx || {}
            var body = tx.body || {}

            var fee    = Number(tx.fee || e.fee || 0)
            var weight = Number(tx.weight || e.weight || 0)
            var inputs  = (body.inputs  && body.inputs.length)  || e.inputs  || 0
            var outputs = (body.outputs && body.outputs.length) || e.outputs || 0
            var kernels = (body.kernels && body.kernels.length) || e.kernels || 0
            var id      = e.id || tx.tx_id || ("tx-" + i)

            out.push({
                id: id,
                fee: fee,
                weight: weight,
                inputs: inputs,
                outputs: outputs,
                kernels: kernels
            })
        }
        return out
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

    Component.onCompleted: updatePollingState()
    onForeignApiChanged: updatePollingState()
    onNodeRunningChanged: updatePollingState()
    Component.onDestruction: stopMempoolPolling()

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

        // Robust: regardless of how the tip arrives (gadget, map, etc.)
        function onTipUpdated(payload) {
            tip = toTip(payload)
        }

        function onUnconfirmedTransactionsUpdated(list) {
            entries = mapPoolEntries(list)
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
        Flow {
            Layout.fillWidth: true
            width: parent.width
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

        // Legend for the block colors / sources
        Flow {
            Layout.fillWidth: true
            width: parent.width
            spacing: compactLayout ? 6 : 10

            LegendChip {
                label: i18n ? i18n.t("tx_legend_high_fee") : "High fee"
            }

            LegendChip {
                label: i18n ? i18n.t("tx_legend_low_fee") : "Low fee"
                invert: true
            }

            LegendChip {
                label: i18n ? i18n.t("tx_legend_pool") : "Pool"
                colorMode: "src-pool"
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
                            weight:  entries[index].weight
                            inputs:  entries[index].inputs
                            outputs: entries[index].outputs
                            kernels: entries[index].kernels
                            i18n:    root.i18n
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

        StatusBar {
            id: status
            Layout.fillWidth: true
            i18n: root.i18n
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

        // incoming data
        property int tipHeight: 0
        property string lastBlockPushed: ""
        property string prevBlockToLast: ""
        property var totalDifficulty: 0
        property bool compactLayout: false
        property var i18n: null

        // layout helpers
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

            // Height column
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
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                }
            }

            // Hash column
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

            // Total difficulty column
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

        // column width adapts depending on stacked vs. horizontal layout
        property real columnWidth: stackedLayout
            ? Math.max(0, width - 28)
            : Math.max(140, (width - 2 * contentSpacing - 28) / 3)

        implicitHeight: tipFlow.implicitHeight + 8
        height: implicitHeight
    }

    // ------------------------------------------------------------------
    // InfoChip: small key/value pill
    // ------------------------------------------------------------------
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

            Label {
                text: label + ":"
                color: "#bbbbbb"
                font.pixelSize: 12
            }

            Label {
                text: "" + value
                color: "white"
                font.bold: true
            }
        }
    }

    // ------------------------------------------------------------------
    // LegendChip: visual legend entry for colors / category
    // ------------------------------------------------------------------
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
                width: 16
                height: 16
                radius: 4
                color: colorMode === "src-pool"
                       ? "#ffa657"                 // fixed color for pool origin
                       : (invert ? "#65d365"      // low fee
                                 : "#ffa657")     // high fee
                border.color: "#111"
            }

            Label {
                text: chipLegend.label
                color: "#ddd"
            }
        }
    }

    // ------------------------------------------------------------------
    // PoolBlock: one transaction “block” visual
    // ------------------------------------------------------------------
    component PoolBlock: Rectangle {
        id: block

        property string txId: ""
        property real fee: 0
        property real weight: 0
        property int inputs: 0
        property int outputs: 0
        property int kernels: 0
        property var i18n: null

        radius: 12
        border.color: "#2a2a2a"
        border.width: 1
        color: feeColor()

        function feeColor() {
            // Map fee magnitude roughly into an alpha/intensity
            var f = Math.max(0, Math.min(1, fee / 100000000.0)) // ~= 0..1 GRIN
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

            // Header row with short tx id and source chip
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

            // Fee + weight
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

                Label {
                    text: i18n ? i18n.t("tx_block_weight_short") : "W:"
                    color: "#bbb"
                    font.pixelSize: 11
                }

                Label {
                    text: weight.toString()
                    color: "#eee"
                    font.pixelSize: 12
                }
            }

            // Inputs / outputs / kernels
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

        // Tooltip with full details
        ToolTip.visible: hover.containsMouse
        ToolTip.delay: 180
        ToolTip.text:
            (i18n ? i18n.t("tx_block_tooltip_tx") : "Tx") + ": " + (txId || "") +
            "\n" + (i18n ? i18n.t("tx_block_tooltip_fee") : "Fee") + ": " + fee +
            "\n" + (i18n ? i18n.t("tx_block_tooltip_weight") : "Weight") + ": " + weight +
            "\n" + (i18n ? i18n.t("tx_block_tooltip_io") : "I/O/K") + ": " +
            inputs + "/" + outputs + "/" + kernels

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
        }
    }

    // ------------------------------------------------------------------
    // StatusBar: simple status/info line at the bottom
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

            // Close button ("×" is language-neutral)
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
}
