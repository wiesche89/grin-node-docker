import QtQuick 2.15
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    property bool compactLayout: false
    property var i18n: null
    readonly property var foreignApi: nodeForeignApi

    property bool loading: false
    property string errorText: ""
    property var allOutputs: []
    property var filteredOutputs: []
    property var selectedOutput: null
    property int highestIndex: 0
    property int lastRetrievedIndex: 0
    property int startIndex: 1
    property int endIndex: -1
    property int maxResults: 50
    property bool includeProof: false
    property bool probingLatestWindow: false
    property bool resolvingHeightRange: false
    property int tipHeight: 0
    property int blockStartHeight: 0
    property int blockEndHeight: 0

    function tr(key, fallback) {
        var res
        if (i18n && typeof i18n.t === "function")
            res = i18n.t(key)
        if (res === undefined || res === null || res === "")
            res = fallback !== undefined ? fallback : key
        return String(res)
    }

    function commitHex(output) {
        if (!output)
            return ""
        var commit = output.commit
        if (typeof commit === "string")
            return commit
        if (commit && typeof commit === "object") {
            if (commit.hex !== undefined && commit.hex !== null)
                return String(commit.hex)
            if (commit.commitment !== undefined && commit.commitment !== null)
                return String(commit.commitment)
        }
        return ""
    }

    function proofHash(output) {
        return output && output.proof_hash ? String(output.proof_hash) : ""
    }

    function blockHeightText(output) {
        if (!output || output.block_height === undefined || output.block_height === null)
            return "-"
        return String(output.block_height)
    }

    function applyFilter() {
        var search = String(searchField.text || "").trim().toLowerCase()
        var typeText = String(typeFilter.currentText || "")
        var spentText = String(spentFilter.currentText || "")

        filteredOutputs = allOutputs.filter(function(output) {
            var commit = commitHex(output).toLowerCase()
            var matchesSearch = search.length === 0
                    || commit.indexOf(search) >= 0
                    || String(output.mmr_index || "").toLowerCase().indexOf(search) >= 0
                    || String(output.block_height || "").toLowerCase().indexOf(search) >= 0

            var matchesType = typeText === tr("utxo_filter_all", "All")
                    || String(output.output_type || "") === typeText

            var matchesSpent = spentText === tr("utxo_filter_all", "All")
                    || (spentText === tr("utxo_spent_only", "Spent") && !!output.spent)
                    || (spentText === tr("utxo_unspent_only", "Unspent") && !output.spent)

            return matchesSearch && matchesType && matchesSpent
        })

        filteredOutputs.sort(function(a, b) {
            var aMmr = Number(a && a.mmr_index !== undefined ? a.mmr_index : -1)
            var bMmr = Number(b && b.mmr_index !== undefined ? b.mmr_index : -1)
            if (aMmr !== bMmr)
                return bMmr - aMmr

            var aHeight = Number(a && a.block_height !== undefined ? a.block_height : -1)
            var bHeight = Number(b && b.block_height !== undefined ? b.block_height : -1)
            return bHeight - aHeight
        })
    }

    function loadOutputs() {
        if (!foreignApi) {
            errorText = tr("utxo_err_no_api", "Foreign API not available.")
            status.showError(errorText)
            return
        }

        loading = true
        errorText = ""
        foreignApi.getUnspentOutputsAsync(startIndex,
                                          endIndex,
                                          Math.max(1, maxResults),
                                          includeProof)
    }

    function loadLatestWindow() {
        probingLatestWindow = true
        loading = true
        errorText = ""
        foreignApi.getUnspentOutputsAsync(1, -1, 1, false)
    }

    function resolveHeightRange() {
        if (!foreignApi) {
            errorText = tr("utxo_err_no_api", "Foreign API not available.")
            status.showError(errorText)
            return
        }

        console.log("[UTXO] resolveHeightRange input:",
                    "blockStartHeight=", blockStartHeight,
                    "blockEndHeight=", blockEndHeight,
                    "blockStartField=", String(blockStartField.text || ""),
                    "blockEndField=", String(blockEndField.text || ""))

        resolvingHeightRange = true
        loading = true
        errorText = ""
        foreignApi.getPmmrIndicesAsync(blockStartHeight, blockEndHeight)
    }

    function applyLatestBlockWindow(height) {
        var resolvedHeight = Math.max(0, Number(height || 0))
        tipHeight = resolvedHeight
        if (resolvedHeight <= 0)
            return

        blockEndHeight = resolvedHeight
        blockStartHeight = Math.max(0, resolvedHeight - 49)
        blockStartField.text = String(blockStartHeight)
        blockEndField.text = String(blockEndHeight)
    }

    function loadPreviousPage() {
        startIndex = Math.max(1, startIndex - Math.max(1, maxResults))
        endIndexField.text = ""
        endIndex = -1
        startIndexField.text = String(startIndex)
        loadOutputs()
    }

    function loadNextPage() {
        if (lastRetrievedIndex > 0)
            startIndex = lastRetrievedIndex + 1
        else
            startIndex = Math.max(1, startIndex + Math.max(1, maxResults))

        endIndexField.text = ""
        endIndex = -1
        startIndexField.text = String(startIndex)
        loadOutputs()
    }

    Connections {
        target: foreignApi
        enabled: !!foreignApi

        function onUnspentOutputsUpdated(outputs, highest, lastRetrieved) {
            loading = false
            errorText = ""
            highestIndex = Number(highest || 0)
            lastRetrievedIndex = Number(lastRetrieved || 0)

            if (probingLatestWindow) {
                probingLatestWindow = false
                startIndex = Math.max(1, highestIndex - Math.max(1, maxResults) + 1)
                endIndex = -1
                startIndexField.text = String(startIndex)
                endIndexField.text = ""
                maxField.text = String(maxResults)
                loadOutputs()
                return
            }

            allOutputs = outputs || []
            applyFilter()
        }

        function onTipUpdated(tip) {
            if (!tip)
                return
            applyLatestBlockWindow(tip.height)
        }

        function onUnspentOutputsLookupFailed(message) {
            loading = false
            probingLatestWindow = false
            errorText = message && String(message).length > 0
                    ? String(message)
                    : tr("utxo_err_load_failed", "Failed to load UTXO outputs.")
            status.showError(errorText)
        }

        function onPmmrIndicesUpdated(outputs, highest, lastRetrieved) {
            loading = false
            resolvingHeightRange = false

            var resolvedHighest = Number(highest || 0)
            var resolvedLast = Number(lastRetrieved || 0)

            console.log("[UTXO] onPmmrIndicesUpdated raw:",
                        "highest=", highest,
                        "lastRetrieved=", lastRetrieved,
                        "outputsLen=", outputs ? outputs.length : -1)

            if (resolvedHighest <= 0 && resolvedLast <= 0) {
                errorText = tr("utxo_err_no_pmmr_match", "No PMMR indices found for this block height range.")
                console.log("[UTXO] onPmmrIndicesUpdated -> no match")
                status.showError(errorText)
                return
            }

            if (resolvedHighest <= 0)
                resolvedHighest = resolvedLast
            if (resolvedLast <= 0)
                resolvedLast = resolvedHighest

            console.log("[UTXO] onPmmrIndicesUpdated normalized:",
                        "resolvedHighest=", resolvedHighest,
                        "resolvedLast=", resolvedLast)

            startIndex = Math.min(resolvedHighest, resolvedLast)
            endIndex = Math.max(resolvedHighest, resolvedLast)
            highestIndex = resolvedHighest
            lastRetrievedIndex = resolvedLast
            errorText = ""

            startIndexField.text = String(startIndex)
            endIndexField.text = String(endIndex)
            loadOutputs()
        }

        function onPmmrIndicesLookupFailed(message) {
            loading = false
            resolvingHeightRange = false
            console.log("[UTXO] onPmmrIndicesLookupFailed:", message)
            errorText = message && String(message).length > 0
                    ? String(message)
                    : tr("utxo_err_pmmr_failed", "Failed to resolve PMMR indices for the block range.")
            status.showError(errorText)
        }
    }

    Component.onCompleted: {
        startIndexField.text = String(startIndex)
        maxField.text = String(maxResults)
        blockStartField.text = String(blockStartHeight)
        blockEndField.text = String(blockEndHeight)
        if (foreignApi)
            foreignApi.getTipAsync()
        loadLatestWindow()
    }

    ScrollView {
        id: pageScroll
        anchors.fill: parent
        anchors.margins: compactLayout ? 12 : 20
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: pageScroll.availableWidth
            height: Math.max(implicitHeight, pageScroll.availableHeight)
            spacing: 16

            Label {
                text: tr("utxo_title", "UTXO Explorer")
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                BusyIndicator {
                    running: loading
                    visible: loading
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                }

                Label {
                    Layout.fillWidth: true
                    text: errorText.length > 0
                          ? errorText
                          : tr("utxo_description", "Browse unspent outputs by PMMR index range. You can also resolve the range from a block height interval below.")
                    color: errorText.length > 0 ? "#ff9c9c" : "#bbbbbb"
                    wrapMode: Text.WordWrap
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: compactLayout ? 1 : 5
                columnSpacing: 10
                rowSpacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_start_index", "Start index"); color: "#bbb"; font.pixelSize: 12 }
                    TextField {
                        id: startIndexField
                        Layout.fillWidth: true
                        placeholderText: "1"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_end_index", "End index"); color: "#bbb"; font.pixelSize: 12 }
                    TextField {
                        id: endIndexField
                        Layout.fillWidth: true
                        placeholderText: tr("utxo_end_index_auto", "auto / null")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_max_results", "Max results"); color: "#bbb"; font.pixelSize: 12 }
                    TextField {
                        id: maxField
                        Layout.fillWidth: true
                        placeholderText: "50"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_include_proof", "Include proof"); color: "#bbb"; font.pixelSize: 12 }
                    CheckBox {
                        id: includeProofCheck
                        checked: root.includeProof
                        text: tr("common_yes", "yes")
                        onToggled: root.includeProof = checked
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 8

                    Button {
                        text: tr("utxo_load_button", "Load")
                        onClicked: {
                            startIndex = Math.max(1, Number(startIndexField.text || "1"))
                            endIndex = String(endIndexField.text || "").trim().length > 0
                                     ? Number(endIndexField.text)
                                     : -1
                            maxResults = Math.max(1, Number(maxField.text || "50"))
                            loadOutputs()
                        }
                    }

                    Button {
                        text: tr("utxo_prev_button", "Prev")
                        onClicked: loadPreviousPage()
                    }

                    Button {
                        text: tr("utxo_next_button", "Next")
                        onClicked: loadNextPage()
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: compactLayout ? 1 : 4
                columnSpacing: 10
                rowSpacing: 8

                Label {
                    Layout.fillWidth: true
                    Layout.columnSpan: compactLayout ? 1 : 4
                    text: tr("utxo_block_range_hint", "Resolve a PMMR index range from block heights, then load matching UTXOs.")
                    color: "#aeb7c4"
                    wrapMode: Text.WordWrap
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_block_start", "Block start"); color: "#bbb"; font.pixelSize: 12 }
                    TextField {
                        id: blockStartField
                        Layout.fillWidth: true
                        placeholderText: "0"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_block_end", "Block end"); color: "#bbb"; font.pixelSize: 12 }
                    TextField {
                        id: blockEndField
                        Layout.fillWidth: true
                        placeholderText: tr("utxo_block_end_placeholder", "same as start")
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 8

                    Button {
                        text: tr("utxo_resolve_height_button", "Resolve PMMR range")
                        enabled: !resolvingHeightRange
                        onClicked: {
                            blockStartHeight = Math.max(0, Number(blockStartField.text || "0"))
                            blockEndHeight = String(blockEndField.text || "").trim().length > 0
                                    ? Math.max(blockStartHeight, Number(blockEndField.text))
                                    : blockStartHeight
                            resolveHeightRange()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                SummaryCard {
                    Layout.fillWidth: true
                    title: tr("utxo_highest_index", "Highest index")
                    value: String(highestIndex)
                }

                SummaryCard {
                    Layout.fillWidth: true
                    title: tr("utxo_last_retrieved", "Last retrieved")
                    value: String(lastRetrievedIndex)
                }

                SummaryCard {
                    Layout.fillWidth: true
                    title: tr("utxo_loaded_count", "Loaded outputs")
                    value: String(filteredOutputs.length)
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: compactLayout ? 1 : 3
                columnSpacing: 10
                rowSpacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_search", "Search"); color: "#bbb"; font.pixelSize: 12 }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: tr("utxo_search_placeholder", "Search commit, height or MMR index")
                        onTextChanged: applyFilter()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_type", "Type"); color: "#bbb"; font.pixelSize: 12 }
                    ComboBox {
                        id: typeFilter
                        Layout.fillWidth: true
                        model: [
                            tr("utxo_filter_all", "All"),
                            "Coinbase",
                            "Transaction",
                            "Unknown"
                        ]
                        onCurrentIndexChanged: applyFilter()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: tr("utxo_spent", "Spent"); color: "#bbb"; font.pixelSize: 12 }
                    ComboBox {
                        id: spentFilter
                        Layout.fillWidth: true
                        model: [
                            tr("utxo_filter_all", "All"),
                            tr("utxo_unspent_only", "Unspent"),
                            tr("utxo_spent_only", "Spent")
                        ]
                        onCurrentIndexChanged: applyFilter()
                    }
                }
            }

            Frame {
                Layout.fillWidth: true
                Layout.minimumHeight: compactLayout ? 420 : 520
                Layout.preferredHeight: compactLayout ? 420 : 520
                padding: 12
                background: Rectangle {
                    color: "#101010"
                    radius: 12
                    border.color: "#252525"
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    spacing: 8
                    model: filteredOutputs

                    delegate: Rectangle {
                        width: list.width
                        height: cardLayout.implicitHeight + 20
                        radius: 10
                        color: "#171717"
                        border.color: "#2a2a2a"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                selectedOutput = modelData
                                outputDialog.open()
                            }
                        }

                        ColumnLayout {
                            id: cardLayout
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Label {
                                    text: "#" + (index + 1)
                                    color: "#8aa8d8"
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: commitHex(modelData)
                                    color: "white"
                                    font.pixelSize: 13
                                    elide: Text.ElideMiddle
                                }

                                Label {
                                    text: String(modelData.output_type || "-")
                                    color: String(modelData.output_type || "") === "Coinbase" ? "#d6c06e" : "#9db6d9"
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: "#d0d0d0"
                                text: String(tr("utxo_row_meta", "Height %1 | MMR %2 | Spent %3"))
                                      .replace("%1", blockHeightText(modelData))
                                      .replace("%2", String(modelData.mmr_index || "-"))
                                      .replace("%3", modelData.spent ? tr("common_yes", "yes") : tr("common_no", "no"))
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: proofHash(modelData).length > 0
                                text: tr("utxo_proof_hash_prefix", "Proof hash: ") + proofHash(modelData)
                                color: "#9fb1c8"
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: !loading && filteredOutputs.length === 0
                        text: tr("utxo_empty", "No outputs available for the current filter.")
                        color: "#8c8c8c"
                    }

                    ScrollBar.vertical: ScrollBar { }
                }
            }

            StatusBar {
                id: status
                Layout.fillWidth: true
            }
        }
    }

    Dialog {
        id: outputDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(root.width - 32, 760)
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
            text: tr("utxo_details_title", "UTXO details")
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
                width: outputDialog.availableWidth
                spacing: 10

                Repeater {
                    model: [
                        { label: tr("utxo_commit", "Commit"), value: commitHex(selectedOutput) },
                        { label: tr("utxo_type", "Type"), value: selectedOutput ? String(selectedOutput.output_type || "-") : "-" },
                        { label: tr("utxo_block_height", "Block height"), value: blockHeightText(selectedOutput) },
                        { label: tr("utxo_mmr_index", "MMR index"), value: selectedOutput ? String(selectedOutput.mmr_index || "-") : "-" },
                        { label: tr("utxo_spent", "Spent"), value: selectedOutput && selectedOutput.spent ? tr("common_yes", "yes") : tr("common_no", "no") },
                        { label: tr("utxo_proof_hash", "Proof hash"), value: selectedOutput ? String(selectedOutput.proof_hash || "-") : "-" },
                        { label: tr("utxo_merkle_proof", "Merkle proof"), value: selectedOutput ? JSON.stringify(selectedOutput.merkle_proof || null, null, 2) : "-" },
                        { label: tr("utxo_proof", "Proof"), value: selectedOutput ? String(selectedOutput.proof || "-") : "-" }
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

                            Label {
                                text: modelData.label
                                color: "white"
                                font.bold: true
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
                text: tr("app_close", "Close")
                onClicked: outputDialog.close()
            }
        }
    }

    component SummaryCard: Rectangle {
        id: summaryCard
        property string title: ""
        property string value: ""

        radius: 10
        color: "#141414"
        border.color: "#2a2a2a"
        border.width: 1
        implicitHeight: 82

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            Label {
                text: summaryCard.title
                color: "#a7a7a7"
                font.pixelSize: 12
            }

            Label {
                text: summaryCard.value
                color: "white"
                font.pixelSize: 24
                font.bold: true
            }
        }
    }

    component StatusBar: Rectangle {
        property string message: ""
        property bool errorState: false
        property color bgOk: "#173022"
        property color fgOk: "#b6ffd1"
        property color bgErr: "#3a1616"
        property color fgErr: "#ffb6b6"

        radius: 10
        color: errorState ? bgErr : bgOk
        implicitHeight: message.length > 0 ? 40 : 0
        visible: message.length > 0

        function show(text) {
            message = String(text || "")
            errorState = false
        }

        function showError(text) {
            message = String(text || "")
            errorState = true
        }

        Label {
            anchors.centerIn: parent
            text: parent.message
            color: parent.errorState ? parent.fgErr : parent.fgOk
        }
    }
}
