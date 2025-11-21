import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: settingsRoot
    Layout.fillWidth: true
    Layout.fillHeight: true

    property bool compactLayout: false
    property var settingsStore: null
    property string defaultControllerUrl: {
        if (typeof controllerBaseUrl !== "undefined" && controllerBaseUrl !== null) {
            var s = controllerBaseUrl.toString()
            if (s && s.length)
                return s
        }
        if (Qt.platform.os === "wasm" || Qt.platform.os === "wasm-emscripten")
            return "/api/"
        return "http://umbrel.local:3416/"
    }
    property string effectiveControllerUrl: (settingsStore && settingsStore.controllerUrlOverride && settingsStore.controllerUrlOverride.length > 0)
                                           ? settingsStore.controllerUrlOverride
                                           : defaultControllerUrl

    function refreshFromStore() {
        if (!urlField)
            return
        if (settingsStore && typeof settingsStore.controllerUrlOverride === "string") {
            urlField.text = settingsStore.controllerUrlOverride
        } else {
            urlField.text = ""
        }
    }

    function normalizeUrl(value) {
        var trimmed = (value || "").trim()
        if (trimmed === "")
            return ""
        if (trimmed.indexOf("://") === -1 && !trimmed.startsWith("/")) {
            trimmed = "http://" + trimmed
        }
        if (!trimmed.endsWith("/")) {
            trimmed = trimmed + "/"
        }
        return trimmed
    }

    function saveOverride() {
        if (!settingsStore)
            return
        var normalized = normalizeUrl(urlField.text)
        settingsStore.controllerUrlOverride = normalized
        urlField.text = normalized
    }

    function resetOverride() {
        if (!settingsStore)
            return
        settingsStore.controllerUrlOverride = ""
        urlField.text = ""
    }

    Component.onCompleted: refreshFromStore()

    Connections {
        target: settingsStore
        function onControllerUrlOverrideChanged() {
            settingsRoot.refreshFromStore()
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: 20
            anchors.margins: 20

            Text {
                text: "Settings"
                font.pixelSize: 26
                font.bold: true
                color: "white"
                Layout.alignment: Qt.AlignLeft
            }

            Rectangle {
                Layout.fillWidth: true
                color: "#252525"
                radius: 8
                border.color: "#3a3a3a"
                border.width: 1
                Layout.preferredHeight: columnBox.implicitHeight + 32

                ColumnLayout {
                    id: columnBox
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "Controller URL"
                        font.pixelSize: 20
                        font.bold: true
                        color: "#f0f0f0"
                    }

                    Text {
                        text: "Standard (web): " + defaultControllerUrl
                        color: "#bbbbbb"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        text: "Activ: " + effectiveControllerUrl
                        color: "#bbbbbb"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }

                    TextField {
                        id: urlField
                        Layout.fillWidth: true
                        placeholderText: "Example: http://localhost:8080/"
                        text: ""
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Button {
                            text: "Save"
                            Layout.preferredWidth: compactLayout ? Layout.fillWidth : 140
                            enabled: settingsStore !== null
                            onClicked: saveOverride()
                        }

                        Button {
                            text: "Reset"
                            Layout.preferredWidth: compactLayout ? Layout.fillWidth : 140
                            enabled: settingsStore !== null && settingsStore.controllerUrlOverride.length > 0
                            onClicked: resetOverride()
                        }
                    }

                    Text {
                        text: "Info: If empty then default."
                        color: "#999999"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
