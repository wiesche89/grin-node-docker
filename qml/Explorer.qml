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

    property int modeIndex: 0
    property bool loading: false
    property bool loadingDefaults: false
    property string errorText: ""
    property var blockResult: null
    property var headerResult: null
    property var kernelResult: null
    property var latestBlockData: null
    property bool blockDefaultsApplied: false
    property bool headerDefaultsApplied: false
    property bool kernelDefaultsApplied: false
    property string detailTitle: ""
    property var detailItems: []

    function tr(key, fallback) {
        var res
        if (i18n && typeof i18n.t === "function")
            res = i18n.t(key)
        if (res === undefined || res === null || res === "")
            res = fallback !== undefined ? fallback : key
        return String(res)
    }

    function hasText(text) {
        return String(text || "").trim().length > 0
    }

    function formatValue(value, fallback) {
        if (value === undefined || value === null || value === "")
            return fallback !== undefined ? fallback : "-"
        return String(value)
    }

    function joinLines(values) {
        if (!values || values.length === 0)
            return "-"
        return values.join("\n")
    }

    function buildDetailItems(kind, value) {
        if (kind === "block") {
            return [
                { label: "Height", value: formatValue(value && value.header ? value.header.height : "", "-") },
                { label: "Hash", value: formatValue(value && value.header ? value.header.hash : "", "-") },
                { label: "Timestamp", value: formatValue(value && value.header ? value.header.timestamp : "", "-") },
                { label: "Previous", value: formatValue(value && value.header ? value.header.previous : "", "-") },
                { label: "Kernel root", value: formatValue(value && value.header ? value.header.kernel_root : "", "-") },
                { label: "Output root", value: formatValue(value && value.header ? value.header.output_root : "", "-") },
                { label: "Inputs", value: joinLines((value && value.inputs ? value.inputs : []).map(function(item) { return JSON.stringify(item) })) },
                { label: "Outputs", value: joinLines((value && value.outputs ? value.outputs : []).map(function(item) { return JSON.stringify(item) })) },
                { label: "Kernels", value: joinLines((value && value.kernels ? value.kernels : []).map(function(item) { return JSON.stringify(item) })) }
            ]
        }

        if (kind === "header") {
            return [
                { label: "Height", value: formatValue(value ? value.height : "", "-") },
                { label: "Hash", value: formatValue(value ? value.hash : "", "-") },
                { label: "Timestamp", value: formatValue(value ? value.timestamp : "", "-") },
                { label: "Previous", value: formatValue(value ? value.previous : "", "-") },
                { label: "Output MMR size", value: formatValue(value ? value.outputMmrSize : "", "-") },
                { label: "Kernel MMR size", value: formatValue(value ? value.kernelMmrSize : "", "-") },
                { label: "Output root", value: formatValue(value ? value.outputRoot : "", "-") },
                { label: "Kernel root", value: formatValue(value ? value.kernelRoot : "", "-") },
                { label: "Range proof root", value: formatValue(value ? value.rangeProofRoot : "", "-") },
                { label: "Total difficulty", value: formatValue(value ? value.totalDifficulty : "", "-") }
            ]
        }

        return [
            { label: "Height", value: formatValue(value ? value.height : "", "-") },
            { label: "MMR index", value: formatValue(value ? value.mmr_index : "", "-") },
            { label: "Excess", value: formatValue(value && value.tx_kernel ? value.tx_kernel.excess : "", "-") },
            { label: "Excess signature", value: formatValue(value && value.tx_kernel ? value.tx_kernel.excess_sig : "", "-") },
            { label: "Features", value: formatValue(value && value.tx_kernel ? value.tx_kernel.features : "", "-") },
            { label: "Fee", value: formatValue(value && value.tx_kernel ? value.tx_kernel.fee : "", "-") },
            { label: "Lock height", value: formatValue(value && value.tx_kernel ? value.tx_kernel.lock_height : "", "-") }
        ]
    }

    function openDetail(kind, title, value) {
        detailTitle = title
        detailItems = buildDetailItems(kind, value)
        detailDialog.open()
    }

    function resetResults() {
        blockResult = null
        headerResult = null
        kernelResult = null
        errorText = ""
    }

    function applyDefaultsFromLatestBlock() {
        var header = latestBlockData && latestBlockData.header ? latestBlockData.header : null
        if (!header)
            return

        if (modeIndex === 0) {
            if (blockDefaultsApplied)
                return
            heightField.text = formatValue(header.height, "")
            hashField.text = formatValue(header.hash, "")
            excessField.text = ""
            minHeightField.text = ""
            maxHeightField.text = ""
            blockDefaultsApplied = true
            return
        }

        if (modeIndex === 1) {
            if (headerDefaultsApplied)
                return
            heightField.text = formatValue(header.height, "")
            hashField.text = formatValue(header.hash, "")
            excessField.text = ""
            minHeightField.text = ""
            maxHeightField.text = ""
            headerDefaultsApplied = true
            return
        }

        if (kernelDefaultsApplied)
            return
        var kernels = latestBlockData && latestBlockData.kernels ? latestBlockData.kernels : []
        var firstKernel = kernels && kernels.length > 0 ? kernels[0] : null
        excessField.text = firstKernel ? formatValue(firstKernel.excess, "") : ""
        minHeightField.text = "0"
        maxHeightField.text = formatValue(header.height, "")
        heightField.text = ""
        hashField.text = ""
        kernelDefaultsApplied = true
    }

    function triggerSearch() {
        if (!foreignApi) {
            errorText = tr("explorer_err_no_api", "Foreign API not available.")
            return
        }

        resetResults()
        loading = true

        var heightText = String(heightField.text || "").trim()
        var hashText = String(hashField.text || "").trim()
        var excessText = String(excessField.text || "").trim()
        var minHeight = hasText(minHeightField.text) ? Number(minHeightField.text) : 0
        var maxHeight = hasText(maxHeightField.text) ? Number(maxHeightField.text) : 0

        if (modeIndex === 0) {
            var blockHeight = hasText(heightText) ? Number(heightText) : 0
            if (blockHeight <= 0 && !hasText(hashText)) {
                loading = false
                errorText = tr("explorer_err_block_input", "Enter a block height or block hash.")
                return
            }
            foreignApi.getBlockAsync(blockHeight, hashText, "")
            return
        }

        if (modeIndex === 1) {
            var headerHeight = hasText(heightText) ? Number(heightText) : 0
            if (headerHeight <= 0 && !hasText(hashText)) {
                loading = false
                errorText = tr("explorer_err_header_input", "Enter a header height or header hash.")
                return
            }
            foreignApi.getHeaderAsync(headerHeight, hashText, "")
            return
        }

        if (!hasText(excessText)) {
            loading = false
            errorText = tr("explorer_err_kernel_input", "Enter a kernel excess to search.")
            return
        }

        if (maxHeight > 0 && maxHeight < minHeight)
            maxHeight = minHeight

        foreignApi.getKernelAsync(excessText, minHeight, maxHeight)
    }

    Connections {
        target: foreignApi
        enabled: !!foreignApi

        function onBlockUpdated(block) {
            if (loadingDefaults) {
                loadingDefaults = false
                latestBlockData = block
                applyDefaultsFromLatestBlock()
                return
            }
            loading = false
            errorText = ""
            blockResult = block
        }

        function onBlockLookupFailed(message) {
            if (loadingDefaults) {
                loadingDefaults = false
                return
            }
            loading = false
            errorText = message && String(message).length > 0
                    ? String(message)
                    : tr("explorer_err_block_failed", "Block lookup failed.")
        }

        function onHeaderUpdatedQml(header) {
            loading = false
            errorText = ""
            headerResult = header
        }

        function onHeaderLookupFailed(message) {
            loading = false
            errorText = message && String(message).length > 0
                    ? String(message)
                    : tr("explorer_err_header_failed", "Header lookup failed.")
        }

        function onKernelUpdatedQml(kernel) {
            loading = false
            errorText = ""
            kernelResult = kernel
        }

        function onKernelLookupFailed(message) {
            loading = false
            errorText = message && String(message).length > 0
                    ? String(message)
                    : tr("explorer_err_kernel_failed", "Kernel lookup failed.")
        }

        function onTipUpdated(tip) {
            if (!foreignApi || !tip || Number(tip.height || 0) <= 0)
                return
            loadingDefaults = true
            foreignApi.getBlockAsync(Number(tip.height || 0), "", "")
        }
    }

    Component.onCompleted: {
        if (foreignApi)
            foreignApi.getTipAsync()
    }

    ScrollView {
        id: explorerScroll
        anchors.fill: parent
        anchors.margins: compactLayout ? 12 : 20
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: explorerScroll.availableWidth
            spacing: 16

            Label {
                text: tr("explorer_title", "Explorer")
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.fillWidth: true
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: errorText.length > 0
                      ? errorText
                      : tr("explorer_description", "Search blocks, headers and kernels from a single page.")
                color: errorText.length > 0 ? "#ff9c9c" : "#bbbbbb"
            }

            Frame {
                Layout.fillWidth: true
                background: Rectangle {
                    color: "#101010"
                    radius: 12
                    border.color: "#252525"
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    ComboBox {
                        Layout.fillWidth: true
                        model: [
                            tr("explorer_mode_block", "Block"),
                            tr("explorer_mode_header", "Header"),
                            tr("explorer_mode_kernel", "Kernel")
                        ]
                        currentIndex: root.modeIndex
                        onActivated: {
                            root.modeIndex = currentIndex
                            root.resetResults()
                            root.applyDefaultsFromLatestBlock()
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: compactLayout ? 1 : 2
                        columnSpacing: 12
                        rowSpacing: 10

                        TextField {
                            id: heightField
                            Layout.fillWidth: true
                            visible: root.modeIndex !== 2
                            placeholderText: tr("explorer_height_placeholder", "Height")
                            color: "white"
                        }

                        TextField {
                            id: hashField
                            Layout.fillWidth: true
                            visible: root.modeIndex !== 2
                            placeholderText: tr("explorer_hash_placeholder", "Hash")
                            color: "white"
                        }

                        TextField {
                            id: excessField
                            Layout.fillWidth: true
                            visible: root.modeIndex === 2
                            placeholderText: tr("explorer_excess_placeholder", "Kernel excess")
                            color: "white"
                        }

                        TextField {
                            id: minHeightField
                            Layout.fillWidth: true
                            visible: root.modeIndex === 2
                            placeholderText: tr("explorer_min_height_placeholder", "Min height")
                            color: "white"
                        }

                        TextField {
                            id: maxHeightField
                            Layout.fillWidth: true
                            visible: root.modeIndex === 2
                            placeholderText: tr("explorer_max_height_placeholder", "Max height")
                            color: "white"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Button {
                            text: tr("explorer_search_button", "Search")
                            onClicked: root.triggerSearch()
                        }

                        BusyIndicator {
                            running: root.loading
                            visible: root.loading
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: !!blockResult
                implicitHeight: blockResultColumn.implicitHeight + 24
                color: "#101010"
                radius: 12
                border.color: "#252525"
                border.width: 1

                ColumnLayout {
                    id: blockResultColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Label {
                        text: tr("explorer_block_result", "Block Result")
                        color: "white"
                        font.bold: true
                    }

                    Label {
                        text: tr("explorer_block_meta", "Height %1 | Hash %2")
                              .replace("%1", formatValue(blockResult && blockResult.header ? blockResult.header.height : "", "-"))
                              .replace("%2", formatValue(blockResult && blockResult.header ? blockResult.header.hash : "", "-"))
                        color: "#d0d0d0"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: tr("explorer_block_counts", "Inputs %1 | Outputs %2 | Kernels %3")
                              .replace("%1", formatValue(blockResult && blockResult.inputs ? blockResult.inputs.length : 0, "0"))
                              .replace("%2", formatValue(blockResult && blockResult.outputs ? blockResult.outputs.length : 0, "0"))
                              .replace("%3", formatValue(blockResult && blockResult.kernels ? blockResult.kernels.length : 0, "0"))
                        color: "#9fb1c8"
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetail("block", tr("explorer_block_result", "Block Result"), blockResult)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: !!headerResult
                implicitHeight: headerResultColumn.implicitHeight + 24
                color: "#101010"
                radius: 12
                border.color: "#252525"
                border.width: 1

                ColumnLayout {
                    id: headerResultColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Label {
                        text: tr("explorer_header_result", "Header Result")
                        color: "white"
                        font.bold: true
                    }

                    Label {
                        text: tr("explorer_header_meta", "Height %1 | Hash %2")
                              .replace("%1", formatValue(headerResult ? headerResult.height : "", "-"))
                              .replace("%2", formatValue(headerResult ? headerResult.hash : "", "-"))
                        color: "#d0d0d0"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: tr("explorer_header_roots", "Output MMR %1 | Kernel MMR %2")
                              .replace("%1", formatValue(headerResult ? headerResult.outputMmrSize : "", "-"))
                              .replace("%2", formatValue(headerResult ? headerResult.kernelMmrSize : "", "-"))
                        color: "#9fb1c8"
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetail("header", tr("explorer_header_result", "Header Result"), headerResult)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: !!kernelResult
                implicitHeight: kernelResultColumn.implicitHeight + 24
                color: "#101010"
                radius: 12
                border.color: "#252525"
                border.width: 1

                ColumnLayout {
                    id: kernelResultColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Label {
                        text: tr("explorer_kernel_result", "Kernel Result")
                        color: "white"
                        font.bold: true
                    }

                    Label {
                        text: tr("explorer_kernel_meta", "Height %1 | MMR %2")
                              .replace("%1", formatValue(kernelResult ? kernelResult.height : "", "-"))
                              .replace("%2", formatValue(kernelResult ? kernelResult.mmr_index : "", "-"))
                        color: "#d0d0d0"
                        Layout.fillWidth: true
                    }

                    Label {
                        text: tr("explorer_kernel_excess", "Excess %1")
                              .replace("%1", formatValue(kernelResult && kernelResult.tx_kernel ? kernelResult.tx_kernel.excess : "", "-"))
                        color: "#9fb1c8"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        text: tr("explorer_kernel_fee", "Fee %1 | Lock height %2")
                              .replace("%1", formatValue(kernelResult && kernelResult.tx_kernel ? kernelResult.tx_kernel.fee : "", "-"))
                              .replace("%2", formatValue(kernelResult && kernelResult.tx_kernel ? kernelResult.tx_kernel.lock_height : "", "-"))
                        color: "#9fb1c8"
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openDetail("kernel", tr("explorer_kernel_result", "Kernel Result"), kernelResult)
                }
            }
        }
    }

    Dialog {
        id: detailDialog
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
            text: root.detailTitle
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
                width: detailDialog.availableWidth
                spacing: 10

                Repeater {
                    model: root.detailItems

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
                onClicked: detailDialog.close()
            }
        }
    }
}
