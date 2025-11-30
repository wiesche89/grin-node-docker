import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: settingsRoot
    Layout.fillWidth: true
    Layout.fillHeight: true

    property bool compactLayout: false
    property var settingsStore: null
    property bool rustNodeRunning: false
    property bool grinppNodeRunning: false

    // kommt aus Main.qml
    property var nodeManager: null
    property var i18n: null   // gemeinsames Übersetzungsobjekt

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

    property string effectiveControllerUrl: (
        settingsStore && settingsStore.controllerUrlOverride
        && settingsStore.controllerUrlOverride.length > 0
    ) ? settingsStore.controllerUrlOverride : defaultControllerUrl

    function refreshFromStore() {
        if (!urlField)
            return
        if (settingsStore && typeof settingsStore.controllerUrlOverride === "string")
            urlField.text = settingsStore.controllerUrlOverride
        else
            urlField.text = ""
    }

    function normalizeUrl(value) {
        var trimmed = (value || "").trim()
        if (trimmed === "")
            return ""
        if (trimmed.indexOf("://") === -1 && !trimmed.startsWith("/"))
            trimmed = "http://" + trimmed
        if (!trimmed.endsWith("/"))
            trimmed += "/"
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

    // Sprache aus settingsStore übernehmen (und ComboBox synchronisieren)
    function initLanguageFromStore() {
        if (!i18n || !languageCombo)
            return

        var code = "en"
        if (settingsStore && settingsStore.languageCode) {
            code = settingsStore.languageCode
        } else if (i18n.language) {
            code = i18n.language
        }

        i18n.language = code

        // ComboBox-Index passend setzen
        for (var i = 0; i < languageCombo.model.length; ++i) {
            if (languageCombo.model[i].code === code) {
                languageCombo.currentIndex = i
                break
            }
        }
    }

    Component.onCompleted: {
        refreshFromStore()
        initLanguageFromStore()
    }

    Connections {
        target: settingsStore
        function onControllerUrlOverrideChanged() {
            settingsRoot.refreshFromStore()
        }
        function onLanguageCodeChanged() {
            initLanguageFromStore()
        }
    }

    ScrollView {
        id: settingsScroll
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 40

        ColumnLayout {
            id: contentColumn
            width: settingsScroll.width - 40
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: 20
            spacing: 24

            // Überschrift
            Label {
                text: i18n ? i18n.t("settings_title") : "Settings"
                color: "white"
                font.pixelSize: compactLayout ? 24 : 28
                font.bold: true
                Layout.fillWidth: true
            }

            // ------- Language Card -------
            Rectangle {
                Layout.fillWidth: true
                radius: 8
                color: "#252525"
                border.color: "#3a3a3a"
                border.width: 1

                implicitHeight: languageBox.implicitHeight + 32

                ColumnLayout {
                    id: languageBox
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Label {
                        text: i18n ? i18n.t("settings_language_title") : "Language"
                        color: "#f0f0f0"
                        font.pixelSize: compactLayout ? 18 : 20
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Label {
                            text: i18n ? i18n.t("settings_language_label") : "App language"
                            color: "#dddddd"
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ComboBox {
                            id: languageCombo
                            Layout.fillWidth: true

                            // Keine Abhängigkeit von i18n, reine Daten
                            model: [
                                { code: "en", label: "English" },
                                { code: "de", label: "Deutsch" },
                                { code: "ru", label: "Русский" },
                                { code: "zh", label: "中文" },
                                { code: "ja", label: "日本語" },
                                { code: "fr", label: "Français" },
                                { code: "it", label: "Italiano" },
                                { code: "es", label: "Español" },
                                { code: "tr", label: "Türkçe" },
                                { code: "nl", label: "Nederlands" }
                            ]
                            textRole: "label"

                            Component.onCompleted: {
                                // beim Start passend setzen
                                var code = "en"
                                if (settingsStore && settingsStore.languageCode)
                                    code = settingsStore.languageCode
                                else if (i18n && i18n.language)
                                    code = i18n.language

                                for (var i = 0; i < model.length; ++i) {
                                    if (model[i].code === code) {
                                        currentIndex = i
                                        break
                                    }
                                }
                            }

                            onCurrentIndexChanged: {
                                if (currentIndex < 0 || currentIndex >= model.length)
                                    return

                                var code = model[currentIndex].code

                                if (i18n)
                                    i18n.language = code
                                if (settingsStore)
                                    settingsStore.languageCode = code
                            }
                        }
                    }
                }
            }

            // ------- Controller URL Card -------
            Rectangle {
                Layout.fillWidth: true
                radius: 8
                color: "#252525"
                border.color: "#3a3a3a"
                border.width: 1

                implicitHeight: controllerBox.implicitHeight + 32

                ColumnLayout {
                    id: controllerBox
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Label {
                        text: i18n ? i18n.t("settings_controller_url") : "Controller URL"
                        color: "#f0f0f0"
                        font.pixelSize: compactLayout ? 18 : 20
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Label {
                        text: i18n
                              ? i18n.t("settings_controller_default").arg(defaultControllerUrl)
                              : "Default (web): " + defaultControllerUrl
                        color: "#bbbbbb"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: i18n
                              ? i18n.t("settings_controller_active").arg(effectiveControllerUrl)
                              : "Active: " + effectiveControllerUrl
                        color: "#bbbbbb"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    TextField {
                        id: urlField
                        Layout.fillWidth: true
                        placeholderText: i18n
                            ? i18n.t("settings_controller_placeholder")
                            : "Example: http://localhost:8080/"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        DarkButton {
                            text: i18n ? i18n.t("settings_controller_save") : "Save"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            enabled: settingsStore !== null
                            onClicked: saveOverride()
                        }

                        DarkButton {
                            text: i18n ? i18n.t("settings_controller_reset") : "Reset"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            enabled: settingsStore !== null
                                     && settingsStore.controllerUrlOverride.length > 0
                            onClicked: resetOverride()
                        }
                    }

                    Label {
                        text: i18n ? i18n.t("settings_controller_info") : "Info: If empty, the default will be used."
                        color: "#999999"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // ------- Chain Data Card -------
            Rectangle {
                Layout.fillWidth: true
                radius: 8
                color: "#252525"
                border.color: "#3a3a3a"
                border.width: 1

                Layout.preferredHeight: chainBox.implicitHeight + 32

                ColumnLayout {
                    id: chainBox
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Label {
                        text: i18n ? i18n.t("settings_chain_title") : "Chain data"
                        color: "#f0f0f0"
                        font.pixelSize: compactLayout ? 18 : 20
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Label {
                        text: i18n
                              ? i18n.t("settings_chain_info")
                              : "Delete local chain data of the selected node.\nThe node must be stopped before deleting."
                        color: "#dddddd"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: i18n
                              ? i18n.t("settings_chain_warning")
                              : "Warning: This removes all downloaded chain state.\nA full resync will be required."
                        color: "#ffb366"
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        DarkButton {
                            text: i18n ? i18n.t("settings_chain_delete_rust") : "Delete Rust"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            enabled: nodeManager !== null

                            onClicked: {
                                if (!nodeManager)
                                    return

                                if (rustNodeRunning) {
                                    // Rust-Node läuft -> Overlay anzeigen
                                    deleteErrorOverlay.titleText =
                                            i18n ? i18n.t("settings_chain_title") : "Chain data"
                                    deleteErrorOverlay.messageText =
                                            i18n
                                            ? i18n.t("settings_chain_err_rust_running",
                                                     "The Rust node is still running.\nStop it before deleting its chain data.")
                                            : "The Rust node is still running.\nStop it before deleting its chain data."
                                    deleteErrorOverlay.active = true
                                    return
                                }

                                nodeManager.deleteRustChain()
                            }
                        }

                        DarkButton {
                            text: i18n ? i18n.t("settings_chain_delete_grinpp") : "Delete Grin++"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            enabled: nodeManager !== null

                            onClicked: {
                                if (!nodeManager)
                                    return

                                if (grinppNodeRunning) {
                                    // Grin++-Node läuft -> Overlay anzeigen
                                    deleteErrorOverlay.titleText =
                                            i18n ? i18n.t("settings_chain_title") : "Chain data"
                                    deleteErrorOverlay.messageText =
                                            i18n
                                            ? i18n.t("settings_chain_err_grinpp_running",
                                                     "The Grin++ node is still running.\nStop it before deleting its chain data.")
                                            : "The Grin++ node is still running.\nStop it before deleting its chain data."
                                    deleteErrorOverlay.active = true
                                    return
                                }

                                nodeManager.deleteGrinppChain()
                            }
                        }
                    }
                }
            }

        }
    }

    // ---- Gemeinsam genutzter DarkButton-Stil ----
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

    // =========================================================
    // ErrorOverlay
    // =========================================================
    ErrorOverlay {
        id: deleteErrorOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        i18n: settingsRoot.i18n

        onRetry: {
            active = false
        }
        onIgnore: {
            active = false
        }
    }
}
