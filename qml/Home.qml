import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Grin 1.0   // GrinNodeManager

Item {
    id: homeRoot
    Layout.fillWidth: true
    Layout.fillHeight: true

    // Basis-URL für den Controller:
    // - im WASM-Build: /api/  (wird von Nginx zum Controller proxied)
    // - Desktop:       http://127.0.0.1:8080/
    property url controllerApiUrl: {
        var base = ""

        if (typeof controllerBaseUrl !== "undefined" && controllerBaseUrl !== null) {
            base = controllerBaseUrl.toString()
        }

        if (base === "") {
            if (Qt.platform.os === "wasm" || Qt.platform.os === "wasm-emscripten")
                base = "/api/"
            else
                base = "http://127.0.0.1:8080/"
        }

        if (!base.endsWith("/"))
            base += "/"

        return base
    }

    // ---------------------------------------------
    // STATE VARS
    // ---------------------------------------------
    property bool isBooting: false
    property string currentNodeKind: "none"   // "none" | "rust" | "grinpp"
    property string nodeState: "none"        // "none" | "rustStarting" | "grinppStarting" | "rust" | "grinpp"
    property bool nodeRunning: isRustRunning() || isGrinppRunning()
    property bool controllerError: false

    function isRustRunning()   { return nodeState === "rust"; }
    function isGrinppRunning() { return nodeState === "grinpp"; }
    function isStarting()      { return nodeState === "rustStarting" || nodeState === "grinppStarting"; }

    // ---------------------------------------------
    // Grin Node Controller Client
    // ---------------------------------------------
    GrinNodeManager {
        id: mgr
        baseUrl: controllerApiUrl    // z.B. "/api/" oder "http://127.0.0.1:8080/"
        username: ""
        password: ""

        onNodeStarted: function(kind) {
            console.log("QML: nodeStarted signal received, kind=", kind)
            homeRoot.nodeState = (kind === GrinNodeManager.Rust) ? "rust" : "grinpp"
            bootTimer.restart()
            controllerError = false
        }

        onNodeRestarted: function(kind) {
            homeRoot.nodeState = (kind === GrinNodeManager.Rust) ? "rust" : "grinpp"
            bootTimer.restart()
            controllerError = false
        }

        onNodeStopped: function(kind) {
            homeRoot.nodeState = "none"
            if (typeof nodeOwnerApi !== "undefined" && nodeOwnerApi) {
                if (typeof nodeOwnerApi.stopStatusPolling === "function")
                    nodeOwnerApi.stopStatusPolling()
                if (typeof nodeOwnerApi.stopConnectedPeersPolling === "function")
                    nodeOwnerApi.stopConnectedPeersPolling()
            }
        }

        onErrorOccurred: function(msg) {
            console.log("QML: errorOccurred", msg)
            controllerError = true
            if (homeRoot.nodeState === "rustStarting" || homeRoot.nodeState === "grinppStarting")
                homeRoot.nodeState = "none"
        }

        onLastResponseChanged: {
            responseField.text = mgr.lastResponse

            if (!mgr.lastResponse || mgr.lastResponse === "")
                return

            try {
                var obj = JSON.parse(mgr.lastResponse)

                if (obj && obj.status && typeof obj.status === "object") {
                    var st = obj.status
                    var running = st.running === true
                    var id = st.id || ""

                    if (running) {
                        if (id === "rust")
                            homeRoot.nodeState = "rust"
                        else if (id === "grinpp")
                            homeRoot.nodeState = "grinpp"

                        controllerError = false

                        if (!bootTimer.running) {
                            console.log("BootTimer gestartet über lastResponse")
                            bootTimer.restart()
                        }
                    } else {
                        if (homeRoot.nodeState === "rust" || homeRoot.nodeState === "grinpp")
                            homeRoot.nodeState = "none"
                    }
                }
            } catch (e) {
                console.log("Failed to parse mgr.lastResponse:", e, mgr.lastResponse)
            }
        }
    }

    // ---------------------------------------------
    // Boot Timer (10s) -> Status & Peers Polling
    // ---------------------------------------------
    Timer {
        id: bootTimer
        interval: 10000
        repeat: false
        onTriggered: {
            isBooting = false
            if (homeRoot.nodeState === "rust" || homeRoot.nodeState === "grinpp") {
                if (typeof nodeOwnerApi !== "undefined" && nodeOwnerApi) {
                    nodeOwnerApi.startStatusPolling && nodeOwnerApi.startStatusPolling(10000)
                    nodeOwnerApi.startConnectedPeersPolling && nodeOwnerApi.startConnectedPeersPolling(5000)
                }
            } else {
                console.log("BootTimer skipped because no node is running")
            }
        }
    }

    // ---------------------------------------------
    // Dark Button-Komponente
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
        spacing: 20

        // HEADER
        RowLayout {
            Layout.fillWidth: true
            spacing: 20
            Label {
                text: "Grin Node Dashboard"
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true }
        }

        // BUTTONS + RESPONSE
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // --- Rust: Start ---
                Loader {
                    id: startRustBtn
                    sourceComponent: darkButtonComponent
                    onLoaded: {
                        if (!startRustBtn.item) return
                        startRustBtn.item.text = (homeRoot.nodeState === "rustStarting")
                                ? "Starting Rust Node…"
                                : "Start Rust Node"
                        startRustBtn.item.enabled = (homeRoot.nodeState === "none")
                        startRustBtn.item.clicked.connect(function () {
                            if (homeRoot.nodeState !== "none") return
                            homeRoot.nodeState = "rustStarting"
                            mgr.startRust([])
                        })
                    }
                    Connections {
                        target: homeRoot
                        function onNodeStateChanged() {
                            if (!startRustBtn.item) return
                            startRustBtn.item.text = (homeRoot.nodeState === "rustStarting")
                                    ? "Starting Rust Node…"
                                    : "Start Rust Node"
                            startRustBtn.item.enabled = (homeRoot.nodeState === "none")
                        }
                    }
                }

                // --- Rust: Restart ---
                Loader {
                    id: restartRustBtn
                    sourceComponent: darkButtonComponent
                    onLoaded: {
                        if (!restartRustBtn.item) return
                        restartRustBtn.item.text = "Restart Rust Node"
                        restartRustBtn.item.enabled = (homeRoot.nodeState === "rust")
                        restartRustBtn.item.clicked.connect(function () { mgr.restartRust([]) })
                    }
                    Connections {
                        target: homeRoot
                        function onNodeStateChanged() {
                            if (!restartRustBtn.item) return
                            restartRustBtn.item.enabled = (homeRoot.nodeState === "rust")
                        }
                    }
                }

                // --- Rust: Stop ---
                Loader {
                    id: stopRustBtn
                    sourceComponent: darkButtonComponent
                    onLoaded: {
                        if (!stopRustBtn.item) return
                        stopRustBtn.item.text = "Stop Rust Node"
                        stopRustBtn.item.enabled = (homeRoot.nodeState === "rust")
                        stopRustBtn.item.clicked.connect(function () { mgr.stopRust() })
                    }
                    Connections {
                        target: homeRoot
                        function onNodeStateChanged() {
                            if (!stopRustBtn.item) return
                            stopRustBtn.item.enabled = (homeRoot.nodeState === "rust")
                        }
                    }
                }

                // --- Grin++: Start ---
                Loader {
                    id: startGrinppBtn
                    sourceComponent: darkButtonComponent
                    onLoaded: {
                        if (!startGrinppBtn.item) return
                        startGrinppBtn.item.text = (homeRoot.nodeState === "grinppStarting")
                                ? "Starting Grin++ Node…"
                                : "Start Grin++ Node"
                        startGrinppBtn.item.enabled = (homeRoot.nodeState === "none")
                        startGrinppBtn.item.clicked.connect(function () {
                            if (homeRoot.nodeState !== "none") return
                            homeRoot.nodeState = "grinppStarting"
                            mgr.startGrinPP([])
                        })
                    }
                    Connections {
                        target: homeRoot
                        function onNodeStateChanged() {
                            if (!startGrinppBtn.item) return
                            startGrinppBtn.item.text = (homeRoot.nodeState === "grinppStarting")
                                    ? "Starting Grin++ Node…"
                                    : "Start Grin++ Node"
                            startGrinppBtn.item.enabled = (homeRoot.nodeState === "none")
                        }
                    }
                }

                // --- Grin++: Restart ---
                Loader {
                    id: restartGrinppBtn
                    sourceComponent: darkButtonComponent
                    onLoaded: {
                        if (!restartGrinppBtn.item) return
                        restartGrinppBtn.item.text = "Restart Grin++ Node"
                        restartGrinppBtn.item.enabled = (homeRoot.nodeState === "grinpp")
                        restartGrinppBtn.item.clicked.connect(function () { mgr.restartGrinPP([]) })
                    }
                    Connections {
                        target: homeRoot
                        function onNodeStateChanged() {
                            if (!restartGrinppBtn.item) return
                            restartGrinppBtn.item.enabled = (homeRoot.nodeState === "grinpp")
                        }
                    }
                }

                // --- Grin++: Stop ---
                Loader {
                    id: stopGrinppBtn
                    sourceComponent: darkButtonComponent
                    onLoaded: {
                        if (!stopGrinppBtn.item) return
                        stopGrinppBtn.item.text = "Stop Grin++ Node"
                        stopGrinppBtn.item.enabled = (homeRoot.nodeState === "grinpp")
                        stopGrinppBtn.item.clicked.connect(function () { mgr.stopGrinPP() })
                    }
                    Connections {
                        target: homeRoot
                        function onNodeStateChanged() {
                            if (!stopGrinppBtn.item) return
                            stopGrinppBtn.item.enabled = (homeRoot.nodeState === "grinpp")
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Response-Log
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                clip: true

                background: Rectangle {
                    color: "#2b2b2b"
                    radius: 6
                    border.color: "#555"
                    border.width: 1
                }

                ScrollBar.vertical: ScrollBar {
                    id: vbar
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: vbar.pressed ? "#777" : (vbar.hovered ? "#666" : "#444")
                    }
                    background: Rectangle { color: "transparent" }
                }
                ScrollBar.horizontal: ScrollBar {
                    id: hbar
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitHeight: 6
                        radius: 3
                        color: hbar.pressed ? "#777" : (hbar.hovered ? "#666" : "#444")
                    }
                    background: Rectangle { color: "transparent" }
                }

                TextArea {
                    id: responseField
                    readOnly: true
                    wrapMode: TextEdit.NoWrap
                    textFormat: TextEdit.PlainText
                    color: "white"
                    selectionColor: "#295d9b"
                    selectedTextColor: "white"
                    font.family: "Consolas"
                    font.pixelSize: 12
                    background: null
                }
            }
        }

        // STATUS + PEERS
        StatusView {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
        }

        PeerListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    // ---------------------------------------------
    // Fehler-Overlay (Controller nicht erreichbar)
    // ---------------------------------------------
    Rectangle {
        id: controllerErrorOverlay
        width: parent ? parent.width * 0.6 : 400
        height: 140
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        anchors.bottom: parent ? parent.bottom : undefined
        anchors.bottomMargin: 20
        color: "#050000"
        visible: controllerError
        z: 99
        opacity: 0.85
        radius: 12
        border.color: "#660000"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                text: "Controller-API not available"
                color: "white"
                font.pixelSize: 18
                wrapMode: Text.Wrap
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Retry if Controller-Api runs"
                color: "#ccc"
                font.pixelSize: 13
                wrapMode: Text.Wrap
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Button {
                    text: "Erneut verbinden"
                    onClicked: {
                        controllerError = false
                        mgr.getStatus()
                    }
                }

                Button {
                    text: "Ignorieren"
                    onClicked: controllerError = false
                }
            }
        }
    }
}
