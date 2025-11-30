import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Grin 1.0   // GrinNodeManager

// =====================================================================
// Home page (Dashboard)
// - shows node start/stop controls
// - shows uptime and basic status
// - drives polling for status/peers (via nodeOwnerApi)
// - fully language-aware via i18n.t(...)
// =====================================================================
Item {
    id: homeRoot
    Layout.fillWidth: true
    Layout.fillHeight: true

    // -----------------------------------------------------------------
    // External dependencies
    // -----------------------------------------------------------------
    // Global i18n object (provided by Main.qml)
    property var i18n: null

    // Settings storage (Qt.labs.settings instance from Main.qml)
    property var settingsStore: null

    // Node manager from C++ (GrinNodeManager)
    property var nodeManager: null
    property var mgr: nodeManager   // short alias used internally

    // -----------------------------------------------------------------
    // Layout / font state
    // -----------------------------------------------------------------
    // Switch to compact layout when window becomes narrow
    property bool compactLayout: width < 900

    // Base font sizes (scaled based on compact layout)
    property int headingFontSize: compactLayout ? 18 : 22
    property int bodyFontSize:    compactLayout ? 13 : 16

    // -----------------------------------------------------------------
    // Request / busy state for node actions (start/stop/restart)
    // -----------------------------------------------------------------
    // True when a request is in flight and we are waiting for a response
    property bool requestInFlight: false

    // -----------------------------------------------------------------
    // Controller base URL (used by GrinNodeManager)
    // -----------------------------------------------------------------
    // Controller URL:
    // - In WASM builds: "/api/" (proxied via nginx)
    // - Otherwise: default "localhost:8080/"
    property url controllerApiUrl: {
        var base = ""

        if (settingsStore && settingsStore.controllerUrlOverride
                && settingsStore.controllerUrlOverride.length > 0) {
            base = settingsStore.controllerUrlOverride
        }

        if (base === "" && typeof controllerBaseUrl !== "undefined"
                && controllerBaseUrl !== null) {
            base = controllerBaseUrl.toString()
        }

        if (base === "") {
            if (Qt.platform.os === "wasm" || Qt.platform.os === "wasm-emscripten")
                base = "/api/"
            else
                base = "http://localhost:8080/"
        }

        if (!base.endsWith("/"))
            base += "/"

        return base
    }

    // -----------------------------------------------------------------
    // Node and polling state
    // -----------------------------------------------------------------
    property bool   isBooting: false
    property string currentNodeKind: "none"   // "none" | "rust" | "grinpp"
    property string nodeState: "none"        // "none" | "rustStarting" | "grinppStarting" | "rust" | "grinpp"

    // Derived: node is running if either Rust or Grin++ is active
    property bool nodeRunning: isRustRunning() || isGrinppRunning()

    property bool   controllerError: false
    property string controllerErrorMessage: ""
    property bool   controllerStatusPollingActive: false
    property bool   nodeOwnerStatusPollingActive: false
    property bool   peersPollingActive: false

    // Uptime label and seconds (for the currently running node)
    property string nodeUptimeLabel: ""
    property int    nodeUptimeSeconds: -1
    property bool   hasNodeUptime: nodeUptimeSeconds >= 0 && nodeUptimeLabel !== ""

    // -----------------------------------------------------------------
    // Helper: translation wrapper with fallback
    // -----------------------------------------------------------------
    function tr(key, fallback) {
        return i18n ? i18n.t(key) : fallback
    }

    // -----------------------------------------------------------------
    // Life-cycle: initialize polling and request initial status
    // -----------------------------------------------------------------
    Component.onCompleted: {
        if (mgr) {
            ensureControllerStatusPolling()
            mgr.getStatus()
        }
    }

    // -----------------------------------------------------------------
    // Utility helpers
    // -----------------------------------------------------------------
    function formatUptime(seconds) {
        var total = Number(seconds)
        if (!isFinite(total) || total < 0)
            return ""
        total = Math.floor(total)

        var days    = Math.floor(total / 86400)
        total       -= days * 86400
        var hours   = Math.floor(total / 3600)
        total       -= hours * 3600
        var minutes = Math.floor(total / 60)
        var secs    = total - minutes * 60

        var parts = []
        if (days > 0)
            parts.push(days + "d")
        if (hours > 0 || parts.length > 0)
            parts.push(hours + "h")
        if (minutes > 0 || parts.length > 0)
            parts.push(minutes + "m")
        parts.push(secs + "s")

        return parts.join(" ")
    }

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

    // -----------------------------------------------------------------
    // Controller / owner status polling helpers
    // -----------------------------------------------------------------
    function ensureControllerStatusPolling() {
        if (controllerStatusPollingActive || !mgr)
            return
        mgr.startStatusPolling(10000)
        controllerStatusPollingActive = true
    }

    function startStatusAndPeersPolling() {
        ensureControllerStatusPolling()
        if (typeof nodeOwnerApi !== "undefined" && nodeOwnerApi) {
            if (!nodeOwnerStatusPollingActive
                    && typeof nodeOwnerApi.startStatusPolling === "function") {
                nodeOwnerApi.startStatusPolling(10000)
                nodeOwnerStatusPollingActive = true
            }
            if (!peersPollingActive
                    && typeof nodeOwnerApi.startConnectedPeersPolling === "function") {
                nodeOwnerApi.startConnectedPeersPolling(5000)
                peersPollingActive = true
            }
        }
    }

    function stopStatusAndPeersPolling() {
        if (typeof nodeOwnerApi !== "undefined" && nodeOwnerApi) {
            if (nodeOwnerStatusPollingActive
                    && typeof nodeOwnerApi.stopStatusPolling === "function") {
                nodeOwnerApi.stopStatusPolling()
                nodeOwnerStatusPollingActive = false
            }
            if (peersPollingActive
                    && typeof nodeOwnerApi.stopConnectedPeersPolling === "function") {
                nodeOwnerApi.stopConnectedPeersPolling()
                peersPollingActive = false
            }
        }
    }

    // -----------------------------------------------------------------
    // Apply controller status payload
    // -----------------------------------------------------------------
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

        var rustInfo    = nodes.rust   || nodes["rust"]
        var grinppInfo  = nodes.grinpp || nodes["grinpp"]
        var rustRunning = rustInfo   ? normalizeRunningFlag(rustInfo.running)   : false
        var grinppRunning = grinppInfo ? normalizeRunningFlag(grinppInfo.running) : false

        // Determine overall node state
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

        // Uptime handling (per node)
        var uptimeLabel   = ""
        var uptimeSeconds = -1
        if (rustRunning && rustInfo && rustInfo.uptimeSec !== undefined) {
            uptimeLabel   = tr("home_rust_node", "Rust Node")
            uptimeSeconds = Number(rustInfo.uptimeSec)
        } else if (grinppRunning && grinppInfo && grinppInfo.uptimeSec !== undefined) {
            uptimeLabel   = tr("home_grinpp_node", "Grin++ Node")
            uptimeSeconds = Number(grinppInfo.uptimeSec)
        }

        if (!isFinite(uptimeSeconds) || uptimeSeconds < 0) {
            uptimeLabel   = ""
            uptimeSeconds = -1
        }

        homeRoot.nodeUptimeLabel   = uptimeLabel
        homeRoot.nodeUptimeSeconds = uptimeSeconds

        var nodeIsRunning = rustRunning || grinppRunning
        if (nodeIsRunning && !bootTimer.running && previousState !== newState) {
            // Ensure polling kicks in when we detect an already running node
            bootTimer.restart()
        }

        controllerError = false
        controllerErrorOverlay.visible = false
    }

    // -----------------------------------------------------------------
    // Boot timer: after initial start, begin status/peers polling
    // -----------------------------------------------------------------
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

    // -----------------------------------------------------------------
    // Main layout: scrollable column
    // -----------------------------------------------------------------
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

                // ---------------------------------------------------------
                // Header section: title, uptime, connection indicator
                // ---------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    // Page title
                    Text {
                        text: tr("home_title", "Grin Node Dashboard")
                        color: "white"
                        font.pixelSize: homeRoot.compactLayout
                                        ? headingFontSize - 2
                                        : headingFontSize
                        font.bold: true
                        wrapMode: Text.NoWrap
                    }

                    // Uptime information under the title
                    Text {
                        visible: homeRoot.hasNodeUptime
                        text: homeRoot.hasNodeUptime
                              ? (homeRoot.nodeUptimeLabel + " "
                                 + tr("home_uptime_suffix", "uptime:")
                                 + " " + formatUptime(homeRoot.nodeUptimeSeconds))
                              : ""
                        color: "#aaaaaa"
                        font.pixelSize: bodyFontSize
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    // Booting / connecting indicator
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
                            text: tr("home_connecting",
                                     "Connecting, please wait...")
                            color: "#cccccc"
                            font.pixelSize: bodyFontSize
                            wrapMode: Text.NoWrap
                        }
                    }
                }

                // ---------------------------------------------------------
                // Node control buttons (Rust / Grin++)
                // ---------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    GridLayout {
                        id: nodeControlGrid
                        Layout.fillWidth: true
                        columns: homeRoot.compactLayout ? 1 : 2
                        columnSpacing: 20
                        rowSpacing: 20

                        // ---------------- Rust node controls --------------
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: tr("home_rust_node", "Rust Node")
                                color: "#f0f0f0"
                                font.pixelSize: headingFontSize
                                font.bold: true
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 8
                                rowSpacing: 8

                                // Rust start
                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: homeRoot.nodeState === "rustStarting"
                                          ? tr("home_btn_starting", "Starting...")
                                          : tr("home_btn_start", "Start")
                                    enabled: homeRoot.nodeState === "none"
                                             && !homeRoot.requestInFlight
                                    onClicked: {
                                        if (homeRoot.nodeState !== "none")
                                            return
                                        homeRoot.nodeState = "rustStarting"
                                        homeRoot.requestInFlight = true
                                        mgr.startRust([])
                                    }
                                }

                                // Rust restart
                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: tr("home_btn_restart", "Restart")
                                    enabled: homeRoot.nodeState === "rust"
                                             && !homeRoot.requestInFlight
                                    onClicked: {
                                        homeRoot.requestInFlight = true
                                        mgr.restartRust([])
                                    }
                                }

                                // Rust stop
                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: tr("home_btn_stop", "Stop")
                                    enabled: homeRoot.nodeState === "rust"
                                             && !homeRoot.requestInFlight
                                    onClicked: {
                                        homeRoot.requestInFlight = true
                                        mgr.stopRust()
                                    }
                                }
                            }
                        }

                        // ---------------- Grin++ node controls -----------
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: tr("home_grinpp_node", "Grin++ Node")
                                color: "#f0f0f0"
                                font.pixelSize: headingFontSize
                                font.bold: true
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 8
                                rowSpacing: 8

                                // Grin++ start
                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: homeRoot.nodeState === "grinppStarting"
                                          ? tr("home_btn_starting", "Starting...")
                                          : tr("home_btn_start", "Start")
                                    enabled: homeRoot.nodeState === "none"
                                             && !homeRoot.requestInFlight
                                    onClicked: {
                                        if (homeRoot.nodeState !== "none")
                                            return
                                        homeRoot.nodeState = "grinppStarting"
                                        homeRoot.requestInFlight = true
                                        mgr.startGrinPP([])
                                    }
                                }

                                // Grin++ restart
                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: tr("home_btn_restart", "Restart")
                                    enabled: homeRoot.nodeState === "grinpp"
                                             && !homeRoot.requestInFlight
                                    onClicked: {
                                        homeRoot.requestInFlight = true
                                        mgr.restartGrinPP([])
                                    }
                                }

                                // Grin++ stop
                                DarkButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 200
                                    Layout.preferredHeight: 52
                                    text: tr("home_btn_stop", "Stop")
                                    enabled: homeRoot.nodeState === "grinpp"
                                             && !homeRoot.requestInFlight
                                    onClicked: {
                                        homeRoot.requestInFlight = true
                                        mgr.stopGrinPP()
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // Status + peers sections
                // ---------------------------------------------------------
                GridLayout {
                    Layout.fillWidth: true
                    columns: 1
                    columnSpacing: 0
                    rowSpacing: 16

                    StatusView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 360
                        Layout.minimumHeight: 280
                        i18n: homeRoot.i18n
                    }

                    PeerListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 360
                        Layout.minimumHeight: 280
                        i18n: homeRoot.i18n
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Controller error overlay
    // -----------------------------------------------------------------
    ErrorOverlay {
        id: controllerErrorOverlay
        i18n: homeRoot.i18n
        active: controllerError
        messageText: controllerErrorMessage

        onRetry: {
            controllerError = false
        }

        onIgnore: {
            controllerError = false
        }
    }


    // -----------------------------------------------------------------
    // Global loading overlay while any node action is in flight
    // -----------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#00000080"
        visible: homeRoot.requestInFlight
        z: 999

        BusyIndicator {
            anchors.centerIn: parent
            running: homeRoot.requestInFlight
            implicitWidth: 48
            implicitHeight: 48
        }
    }

    // -----------------------------------------------------------------
    // Connections to GrinNodeManager (mgr)
    // -----------------------------------------------------------------
    Connections {
        target: mgr

        function onNodeStarted(kind) {
            console.log("QML: nodeStarted signal received, kind=", kind)
            homeRoot.nodeState =
                    (kind === GrinNodeManager.Rust) ? "rust" : "grinpp"
            bootTimer.restart()
            homeRoot.controllerError = false
            controllerErrorOverlay.active = false
            homeRoot.requestInFlight = false
        }

        function onNodeRestarted(kind) {
            homeRoot.nodeState =
                    (kind === GrinNodeManager.Rust) ? "rust" : "grinpp"
            bootTimer.restart()
            homeRoot.controllerError = false
            controllerErrorOverlay.active = false
            homeRoot.requestInFlight = false
        }

        function onNodeStopped(kind) {
            homeRoot.nodeState = "none"
            stopStatusAndPeersPolling()
            homeRoot.requestInFlight = false
        }

        function onStatusReceived(statusObj) {
            applyControllerStatus(statusObj)
        }

        function onErrorOccurred(msg) {
            console.log("QML: errorOccurred", msg)
            controllerErrorMessage = msg
            controllerError = true
            if (homeRoot.nodeState === "rustStarting"
                    || homeRoot.nodeState === "grinppStarting")
                homeRoot.nodeState = "none"
            homeRoot.requestInFlight = false
        }

        function onLastResponseChanged() {
            if (!mgr || !mgr.lastResponse || mgr.lastResponse === "")
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
}
