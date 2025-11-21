import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Grin 1.0   // GrinNodeManager

Item {
    id: homeRoot
    Layout.fillWidth: true
    Layout.fillHeight: true
    property bool compactLayout: false
    property var settingsStore: null
    property int headingFontSize: 20
    property int bodyFontSize: 16

    // Basis-URL für den Controller:
    // - im WASM-Build: /api/  (wird von Nginx zum Controller proxied)
    property url controllerApiUrl: {
        var base = ""

        if (settingsStore && settingsStore.controllerUrlOverride && settingsStore.controllerUrlOverride.length > 0) {
            base = settingsStore.controllerUrlOverride
        }

        if (base === "" && typeof controllerBaseUrl !== "undefined" && controllerBaseUrl !== null) {
            base = controllerBaseUrl.toString()
        }

        if (base === "") {
            if (Qt.platform.os === "wasm" || Qt.platform.os === "wasm-emscripten")
                base = "/api/"
            else
                base = "localhost:8080/"
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
    property string controllerErrorMessage: ""

    function isRustRunning()   { return nodeState === "rust"; }
    function isGrinppRunning() { return nodeState === "grinpp"; }
    function isStarting()      { return nodeState === "rustStarting" || nodeState === "grinppStarting"; }

    function toPlainObject(obj) {
        if (!obj || typeof obj !== "object")
            return obj
        try {
            return JSON.parse(JSON.stringify(obj))
        } catch (e) {
            return obj
        }
    }

    function startStatusAndPeersPolling() {
        if (typeof nodeOwnerApi !== "undefined" && nodeOwnerApi) {
            nodeOwnerApi.startStatusPolling && nodeOwnerApi.startStatusPolling(10000)
            nodeOwnerApi.startConnectedPeersPolling && nodeOwnerApi.startConnectedPeersPolling(5000)
        } else {
            mgr.startStatusPolling(10000)
        }
    }

    function stopStatusAndPeersPolling() {
        if (typeof nodeOwnerApi !== "undefined" && nodeOwnerApi) {
            if (typeof nodeOwnerApi.stopStatusPolling === "function")
                nodeOwnerApi.stopStatusPolling()
            if (typeof nodeOwnerApi.stopConnectedPeersPolling === "function")
                nodeOwnerApi.stopConnectedPeersPolling()
        } else {
            mgr.stopStatusPolling()
        }
    }

    function applyControllerStatus(statusObj) {
        var normalized = toPlainObject(statusObj)
        if (!normalized)
            return

        var nodes = null
        if (normalized.nodes) {
            nodes = normalized.nodes
        } else if (normalized["nodes"]) {
            nodes = normalized["nodes"]
        } else if (normalized.id) {
            nodes = {}
            nodes[normalized.id] = normalized
        } else if (normalized.rust || normalized.grinpp) {
            nodes = normalized
        }
        if (!nodes)
            return

        var normalizeRunningFlag = function(flag) {
            if (typeof flag === "boolean")
                return flag
            if (typeof flag === "number")
                return flag !== 0
            if (typeof flag === "string")
                return flag.toLowerCase() === "true" || flag === "1"
            return false
        }

        var rustInfo = nodes.rust || nodes["rust"]
        var grinppInfo = nodes.grinpp || nodes["grinpp"]
        var rustRunning = rustInfo ? normalizeRunningFlag(rustInfo.running) : false
        var grinppRunning = grinppInfo ? normalizeRunningFlag(grinppInfo.running) : false

        var newState = "none"
        if (rustRunning) {
            newState = "rust"
        } else if (grinppRunning) {
            newState = "grinpp"
        }

        var previousState = homeRoot.nodeState
        if (previousState !== newState) {
            homeRoot.nodeState = newState
        }

        var nodeIsRunning = rustRunning || grinppRunning
        if (nodeIsRunning && !bootTimer.running && previousState !== newState) {
            // Ensure polling kicks in when we detect an already running node (e.g. initial getStatus)
            bootTimer.restart()
        }

        controllerError = false
        controllerErrorOverlay.visible = false
    }

    // ---------------------------------------------
    // Grin Node Controller Client
    // ---------------------------------------------
    GrinNodeManager {
        id: mgr
        baseUrl: controllerApiUrl
        username: ""
        password: ""
        Component.onCompleted: mgr.getStatus()

        onNodeStarted: function(kind) {
            console.log("QML: nodeStarted signal received, kind=", kind)
            homeRoot.nodeState = (kind === GrinNodeManager.Rust) ? "rust" : "grinpp"
            bootTimer.restart()
            controllerError = false
            controllerErrorOverlay.visible = false
        }

        onNodeRestarted: function(kind) {
            homeRoot.nodeState = (kind === GrinNodeManager.Rust) ? "rust" : "grinpp"
            bootTimer.restart()
            controllerError = false
            controllerErrorOverlay.visible = false
        }

        onNodeStopped: function(kind) {
            homeRoot.nodeState = "none"
            stopStatusAndPeersPolling()
        }

        onStatusReceived: function(statusObj) {
            applyControllerStatus(statusObj)
        }

        onErrorOccurred: function(msg) {
            console.log("QML: errorOccurred", msg)
            controllerError = true
            controllerErrorOverlay.visible = true
            controllerErrorMessage = msg
            if (homeRoot.nodeState === "rustStarting" || homeRoot.nodeState === "grinppStarting")
                homeRoot.nodeState = "none"
        }

        onLastResponseChanged: {
            if (!mgr.lastResponse || mgr.lastResponse === "")
                return

            try {
                var obj = JSON.parse(mgr.lastResponse)
                if (obj && obj.status && typeof obj.status === "object") {
                    applyControllerStatus(obj.status)
                } else if (obj && obj.nodes && typeof obj.nodes === "object") {
                    applyControllerStatus(obj)
                } else if (obj && obj.id) {
                    applyControllerStatus(obj)
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
        interval: 5000
        repeat: false
        onTriggered: {
            isBooting = false
            if (homeRoot.nodeState === "rust" || homeRoot.nodeState === "grinpp") {
                startStatusAndPeersPolling()
            } else {
                console.log("BootTimer skipped because no node is running")
            }
        }
    }

    // ---------------------------------------------
    // Layout
    // ---------------------------------------------
    ScrollView {
        id: homeScrollView
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        Item {
            width: homeScrollView.width
            implicitHeight: contentColumn.implicitHeight + 40
            height: implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20

                // HEADER
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Grin Node Dashboard"
                        color: "white"
                        font.pixelSize: homeRoot.compactLayout ? headingFontSize - 2 : headingFontSize
                        font.bold: true
                    }

                    RowLayout {
                        visible: bootTimer.running
                        spacing: 8
                        Layout.alignment: Qt.AlignLeft

                        BusyIndicator {
                            running: bootTimer.running
                            implicitWidth: 28
                            implicitHeight: 28
                        }

                        Text {
                            text: "Connecting, please wait..."
                            color: "#cccccc"
                            font.pixelSize: bodyFontSize
                        }
                    }
                }

                // BUTTONS + RESPONSE
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    GridLayout {
                        id: nodeControlGrid
                        Layout.fillWidth: true
                        columns: homeRoot.compactLayout ? 1 : 2
                        columnSpacing: 20
                        rowSpacing: 20

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Rust Node"
                                color: "#f0f0f0"
                                font.pixelSize: headingFontSize
                                font.bold: true
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 8
                                rowSpacing: 8

                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: homeRoot.nodeState === "rustStarting" ? "Starting..." : "Start"
                                    enabled: homeRoot.nodeState === "none"
                                    onClicked: {
                                        if (homeRoot.nodeState !== "none") return
                                        homeRoot.nodeState = "rustStarting"
                                        mgr.startRust([])
                                    }
                                }

                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: "Restart"
                                    enabled: homeRoot.nodeState === "rust"
                                    onClicked: mgr.restartRust([])
                                }

                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: "Stop"
                                    enabled: homeRoot.nodeState === "rust"
                                    onClicked: mgr.stopRust()
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Grin++ Node"
                                color: "#f0f0f0"
                                font.pixelSize: headingFontSize
                                font.bold: true
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 8
                                rowSpacing: 8

                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: homeRoot.nodeState === "grinppStarting" ? "Starting..." : "Start"
                                    enabled: homeRoot.nodeState === "none"
                                    onClicked: {
                                        if (homeRoot.nodeState !== "none") return
                                        homeRoot.nodeState = "grinppStarting"
                                        mgr.startGrinPP([])
                                    }
                                }

                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: "Restart"
                                    enabled: homeRoot.nodeState === "grinpp"
                                    onClicked: mgr.restartGrinPP([])
                                }

                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: "Stop"
                                    enabled: homeRoot.nodeState === "grinpp"
                                    onClicked: mgr.stopGrinPP()
                                }
                            }
                        }
                    }

                }

                // STATUS + PEERS
                GridLayout {
                    Layout.fillWidth: true
                    columns: 1
                    columnSpacing: 0
                    rowSpacing: 16

                    StatusView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 360
                        Layout.minimumHeight: 280
                    }

                    PeerListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 360
                        Layout.minimumHeight: 280
                    }
                }
            }
        }
    }

        ErrorOverlay {
            id: controllerErrorOverlay
            message: controllerErrorMessage
            onRetry: {
                controllerError = false
                controllerErrorOverlay.visible = false
            }
            onIgnore: {
                controllerError = false
                controllerErrorOverlay.visible = false
            }
        }
}



