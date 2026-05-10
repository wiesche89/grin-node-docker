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
    property bool loadedOnce: false
    property string errorText: ""
    property string configText: ""

    readonly property var ownerApi: (typeof nodeOwnerApi === "object" ? nodeOwnerApi : null)

    onPageActiveChanged: {
        if (pageActive && !loadedOnce)
            refresh()
    }

    function tr(key, fallback) {
        return i18n && i18n.tf ? i18n.tf(key, fallback) : fallback
    }

    function refresh() {
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

        function onGetConfigFinished(config, error) {
            loading = false
            loadedOnce = true

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
                text: loading
                    ? tr("node_config_loading", "Loading...")
                    : tr("node_config_refresh", "Refresh")
                enabled: !loading
                onClicked: refresh()
            }
        }

        Label {
            text: tr("node_config_description", "Grin++ get_config export")
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
