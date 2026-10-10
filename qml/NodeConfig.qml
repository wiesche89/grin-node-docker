import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    property bool compactLayout: false
    property var i18n: null
    property bool pageActive: false
    property bool loading: false
    property string nodeState: "none"
    property int revision: 0
    property int requestRevision: 0
    property string errorText: ""
    property string configText: ""

    readonly property var ownerApi: (typeof nodeOwnerApi === "object" ? nodeOwnerApi : null)

    onPageActiveChanged: {
        if (pageActive)
            refresh()
    }

    onNodeStateChanged: invalidate()

    function invalidate() {
        revision++
        configText = ""
        errorText = ""
        if (pageActive)
            refresh()
    }

    function tr(key, fallback) {
        return i18n && i18n.tf ? i18n.tf(key, fallback) : fallback
    }

    function refresh() {
        if (loading || nodeState !== "grinpp")
            return
        requestRevision = revision
        if (!ownerApi || typeof ownerApi.getConfigAsync !== "function") {
            loading = false
            errorText = tr("node_config_err_no_api", "Owner API is not available.")
            return
        }

        loading = true
        errorText = ""
        ownerApi.getConfigAsync()
    }

    Connections {
        target: ownerApi

        function onApiUrlChanged() { invalidate() }
        function onApiKeyChanged() { invalidate() }

        function onGetConfigFinished(config, error) {
            if (!loading)
                return
            loading = false
            if (requestRevision !== revision) {
                if (pageActive)
                    refresh()
                return
            }

            if (error && error.length > 0) {
                errorText = error
                configText = ""
                return
            }

            errorText = ""
            configText = JSON.stringify(config, null, 2)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: compactLayout ? 12 : 20
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: tr("node_config_title", "Node Config")
                color: "white"
                font.pixelSize: compactLayout ? 24 : 28
                font.bold: true
                Layout.fillWidth: true
            }

            Button {
                visible: nodeState === "grinpp"
                text: loading
                    ? tr("node_config_loading", "Loading...")
                    : tr("node_config_refresh", "Refresh")
                enabled: !loading && nodeState === "grinpp"
                onClicked: refresh()
            }
        }

        Label {
            text: nodeState === "grinpp"
                ? tr("node_config_description", "Grin++ configuration (read-only).")
                : nodeState === "rust" || nodeState === "rustStarting"
                  ? tr("node_config_rust", "Available for Grin++ only.")
                  : tr("node_config_stopped", "Start Grin++ to view its configuration.")
            color: "#bbbbbb"
            font.pixelSize: 14
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Rectangle {
            visible: errorText.length > 0
            Layout.fillWidth: true
            implicitHeight: errorLabel.implicitHeight + 20
            radius: 6
            color: "#3a2222"
            border.color: "#7a3838"
            border.width: 1

            Label {
                id: errorLabel
                anchors.fill: parent
                anchors.margins: 10
                text: errorText
                color: "#ffb0b0"
                font.pixelSize: 13
                wrapMode: Text.WrapAnywhere
            }
        }

        Rectangle {
            visible: nodeState === "grinpp"
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: "#1f1f1f"
            border.color: "#3a3a3a"
            border.width: 1

            ScrollView {
                anchors.fill: parent
                anchors.margins: 12
                clip: true

                TextArea {
                    text: loading && configText.length === 0
                        ? tr("node_config_loading", "Loading...")
                        : configText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.NoWrap
                    color: "#eeeeee"
                    selectedTextColor: "#111111"
                    selectionColor: "#d6c35a"
                    font.family: "monospace"
                    font.pixelSize: 13
                    background: null
                }
            }
        }
    }
}
