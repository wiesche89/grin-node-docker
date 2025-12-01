import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: settingsRoot
    Layout.fillWidth: true
    Layout.fillHeight: true

    // External properties
    property bool compactLayout: false
    property var settingsStore: null
    property bool rustNodeRunning: false
    property bool grinppNodeRunning: false

    // Provided from Main.qml
    property var nodeManager: null
    property var i18n: null

    // Local flag: true while a chain-delete request is in progress
    property bool requestInFlight: false

    // Text for success banner after chainDeleted
    property string lastDeleteMessage: ""

    // --- Default + effective controller URL ---
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


    // -----------------------------------------------------------------------
    // Utilities
    // -----------------------------------------------------------------------

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

    // Initialize language selection
    function initLanguageFromStore() {
        if (!i18n || !languageCombo)
            return

        var code = "en"
        if (settingsStore && settingsStore.languageCode) {
            code = settingsStore.languageCode
        } else {
            code = i18n.language
        }

        i18n.language = code

        // Set ComboBox index
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

    // -----------------------------------------------------------------------
    // Listen to SettingsStore changes
    // -----------------------------------------------------------------------
    Connections {
        target: settingsStore
        function onControllerUrlOverrideChanged() { settingsRoot.refreshFromStore() }
        function onLanguageCodeChanged() { initLanguageFromStore() }
    }

    // -----------------------------------------------------------------------
    // Listen to GrinNodeManager signals (chainDeleted)
    // -----------------------------------------------------------------------
    Connections {
        target: nodeManager

        function onChainDeleted(kind) {
            console.log("Settings: onChainDeleted, kind =", kind)
            settingsRoot.requestInFlight = false

            var msg
            if (i18n) {
                if (kind === 0)
                    msg = i18n.t("settings_chain_deleted_rust",
                                 "Rust node chain data deleted.")
                else if (kind === 1)
                    msg = i18n.t("settings_chain_deleted_grinpp",
                                 "Grin++ node chain data deleted.")
                else
                    msg = i18n.t("settings_chain_deleted_generic",
                                 "Chain data deleted.")
            } else {
                msg = (kind === 0) ? "Rust chain deleted."
                    : (kind === 1) ? "Grin++ chain deleted."
                    : "Chain data deleted."
            }

            settingsRoot.lastDeleteMessage = msg
            deleteSuccessTimer.restart()
        }

        // Fallback error
        function onErrorOccurred(message) {
            if (!settingsRoot.requestInFlight)
                return

            if (message.indexOf("/delete/rust") === -1 &&
                message.indexOf("/delete/grinpp") === -1) {
                return
            }

            console.log("Settings: delete error, requestInFlight = false")
            settingsRoot.requestInFlight = false

            deleteErrorOverlay.titleText =
                i18n ? i18n.t("settings_chain_title") : "Chain data"

            deleteErrorOverlay.messageText = i18n
                ? i18n.t("settings_chain_delete_failed",
                         "Failed to delete chain data.\nPlease check the controller logs on your Umbrel node.")
                : "Failed to delete chain data.\nPlease check the controller logs on your Umbrel node."

            deleteErrorOverlay.active = true
        }
    }


    // -----------------------------------------------------------------------
    // Main ScrollView Content
    // -----------------------------------------------------------------------
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

            // ================================================================
            // HEADER
            // ================================================================
            Label {
                text: i18n ? i18n.t("settings_title") : "Settings"
                color: "white"
                font.pixelSize: compactLayout ? 24 : 28
                font.bold: true
                Layout.fillWidth: true
            }

            // ================================================================
            // LANGUAGE CARD
            // ================================================================
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

                            Component.onCompleted: initLanguageFromStore()

                            onCurrentIndexChanged: {
                                if (currentIndex < 0 || currentIndex >= model.length)
                                    return

                                var code = model[currentIndex].code
                                if (i18n) i18n.language = code
                                if (settingsStore) settingsStore.languageCode = code
                            }
                        }
                    }
                }
            }

            // ================================================================
            // CONTROLLER URL CARD
            // ================================================================
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

                    // Default controller URL (mit sicherem .arg())
                    Label {
                        text: {
                            var base = i18n
                                ? i18n.t("settings_controller_default")
                                : "Default (web): %1"
                            var url = defaultControllerUrl

                            if (base.indexOf("%1") !== -1)
                                return base.arg(url)
                            return base + " " + url
                        }
                        color: "#bbbbbb"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Aktive controller URL (mit sicherem .arg())
                    Label {
                        text: {
                            var base = i18n
                                ? i18n.t("settings_controller_active")
                                : "Active: %1"
                            var url = effectiveControllerUrl

                            if (base.indexOf("%1") !== -1)
                                return base.arg(url)
                            return base + " " + url
                        }
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
                        text: i18n
                              ? i18n.t("settings_controller_info")
                              : "Info: If empty, the default will be used."
                        color: "#999999"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }


            // ================================================================
            // CHAIN DELETE CARD
            // ================================================================
            Rectangle {
                id: chainCard
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

                        // --------------------------------------------------------
                        // DELETE RUST
                        // --------------------------------------------------------
                        DarkButton {
                            text: i18n ? i18n.t("settings_chain_delete_rust") : "Delete Rust"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            enabled: nodeManager !== null && !settingsRoot.requestInFlight

                            onClicked: {
                                if (!nodeManager)
                                    return

                                if (rustNodeRunning) {
                                    deleteErrorOverlay.titleText =
                                        i18n ? i18n.t("settings_chain_title") : "Chain data"
                                    deleteErrorOverlay.messageText =
                                        i18n ? i18n.t("settings_chain_err_rust_running")
                                             : "The Rust node is still running.\nStop it before deleting its chain data."
                                    deleteErrorOverlay.active = true
                                    return
                                }

                                console.log("Settings: delete RUST, requestInFlight = true")
                                settingsRoot.lastDeleteMessage = ""
                                settingsRoot.requestInFlight = true
                                nodeManager.deleteRustChain()
                            }
                        }

                        // --------------------------------------------------------
                        // DELETE GRIN++
                        // --------------------------------------------------------
                        DarkButton {
                            text: i18n ? i18n.t("settings_chain_delete_grinpp") : "Delete Grin++"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            enabled: nodeManager !== null && !settingsRoot.requestInFlight

                            onClicked: {
                                if (!nodeManager)
                                    return

                                if (grinppNodeRunning) {
                                    deleteErrorOverlay.titleText =
                                        i18n ? i18n.t("settings_chain_title") : "Chain data"
                                    deleteErrorOverlay.messageText =
                                        i18n ? i18n.t("settings_chain_err_grinpp_running")
                                             : "The Grin++ node is still running.\nStop it before deleting its chain data."
                                    deleteErrorOverlay.active = true
                                    return
                                }

                                console.log("Settings: delete GRIN++, requestInFlight = true")
                                settingsRoot.lastDeleteMessage = ""
                                settingsRoot.requestInFlight = true
                                nodeManager.deleteGrinppChain()
                            }
                        }
                    }
                }

                // ------------------------------------------------------------
                // REQUEST-IN-FLIGHT OVERLAY (SPINNER)
                // ------------------------------------------------------------
                Rectangle {
                    anchors.fill: parent
                    visible: settingsRoot.requestInFlight
                    color: "#00000080"
                    z: 100

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        BusyIndicator {
                            running: parent.visible
                            width: 40
                            height: 40
                        }

                        Label {
                            text: i18n ? i18n.t("settings_chain_deleting")
                                       : "Deleting chain data…"
                            color: "#f0f0f0"
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }


    // ================================================================
    // SUCCESS BANNER (Appears after chainDeleted)
    // ================================================================
    Rectangle {
        id: deleteSuccessBanner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        // Breite explizit setzen, z.B. 40px Rand links/rechts
        width: parent.width - 40
        // Höhe vom Inhalt ableiten
        height: contentRow.implicitHeight + 24

        radius: 6
        color: "#2e7d32"
        visible: lastDeleteMessage.length > 0
        opacity: visible ? 1 : 0
        z: 200

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        RowLayout {
            id: contentRow
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Label {
                text: lastDeleteMessage
                color: "white"
                font.pixelSize: 14
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // Timer to auto-hide success banner
    Timer {
        id: deleteSuccessTimer
        interval: 3000
        repeat: false
        onTriggered: lastDeleteMessage = ""
    }


    // ================================================================
    // DARK BUTTON THEME
    // ================================================================
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

    // ================================================================
    // ERROR OVERLAY (already existing)
    // ================================================================
    ErrorOverlay {
        id: deleteErrorOverlay
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        i18n: settingsRoot.i18n

        onRetry: active = false
        onIgnore: active = false
    }
}
