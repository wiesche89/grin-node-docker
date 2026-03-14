import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "QRGen.js" as QR

Item {
    id: walletRoot
    Layout.fillWidth: true
    Layout.fillHeight: true

    property bool compactLayout: false
    property var nodeManager: null
    property var i18n: null

    // Quiet-Zone in QR-Modulen (üblich: 4)
    property int quietZoneModules: 4

    property bool testnet: {
        if (typeof config !== "undefined" && config) {
            var chainType = String(config.value("chain_type", "")).toLowerCase()
            if (!chainType.length)
                chainType = String(config.value("server.chain_type", "")).toLowerCase()
            if (chainType.indexOf("test") !== -1 || chainType.indexOf("floonet") !== -1)
                return true
        }

        if (typeof controllerBaseUrl === "object" && controllerBaseUrl && controllerBaseUrl.port)
            return controllerBaseUrl.port() === 13416

        return false
    }

    property string defaultIpPort: testnet
        ? "http://umbrel.local:13416"
        : "http://umbrel.local:3416"

    property string defaultSecret: {
        if (typeof config !== "undefined" && config) {
            var secret = config.value("owner_api.secret", "")
            if (secret && secret.length) return secret
            secret = config.value("owner_api_secret", "")
            if (secret && secret.length) return secret
        }
        return ""
    }

    property var qrModules: []
    property string qrPayload: ""
    property bool qrReady: false

    function escapeJsonString(value) {
        return String(value)
            .replace(/\\/g, "\\\\")
            .replace(/"/g, "\\\"")
            .replace(/\//g, "\\/")
            .replace(/\n/g, "\\n")
            .replace(/\r/g, "\\r")
            .replace(/\t/g, "\\t")
    }

    function walletJson() {
        var ipPort = ipPortField ? ipPortField.text.trim() : ""
        var secret = secretField ? secretField.text : ""
        return "{\"ipPort\":\"" + escapeJsonString(ipPort)
            + "\", \"username\":\"grin\", \"secret\":\""
            + escapeJsonString(secret) + "\"}"
    }

    function rebuildQr() {
        qrPayload = walletJson()

        if (!qrPayload || qrPayload.length === 0) {
            qrModules = []
            qrReady = false
            qrCanvas.requestPaint()
            return
        }

        try {
            // UTF-8 aktivieren (für Umlaute etc.)
            QR.setUtf8Enabled(true)

            var qr = QR.create(0, "M")
            qr.addData(qrPayload, "Byte")
            qr.make()

            var count = qr.getModuleCount()
            var matrix = []
            for (var r = 0; r < count; ++r) {
                matrix[r] = []
                for (var c = 0; c < count; ++c)
                    matrix[r][c] = qr.isDark(r, c)
            }

            qrModules = matrix
            qrReady = true
        } catch (err) {
            console.warn("Wallet QR generation failed:", err)
            qrModules = []
            qrReady = false
        }

        qrCanvas.requestPaint()
    }

    Component.onCompleted: rebuildQr()

    ScrollView {
        id: walletScroll
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        contentWidth: width
        contentHeight: walletContent.implicitHeight + 40

        ColumnLayout {
            id: walletContent
            width: walletScroll.width - 40
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: 20
            spacing: 24

            Label {
                text: i18n ? i18n.t("wallet_title") : "Wallet QR"
                color: "white"
                font.pixelSize: compactLayout ? 24 : 28
                font.bold: true
                Layout.fillWidth: true
            }

            Label {
                text: i18n ? i18n.t("wallet_description") : "Share the connection details via a QR code."
                color: "#bbbbbb"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 8
                color: "#252525"
                border.color: "#3a3a3a"
                border.width: 1
                implicitHeight: formBox.implicitHeight + 32

                ColumnLayout {
                    id: formBox
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    Label {
                        text: i18n ? i18n.t("wallet_ip_port_label") : "Controller host:port"
                        color: "#dddddd"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    TextField {
                        id: ipPortField
                        Layout.fillWidth: true
                        placeholderText: "http://umbrel.local:3416"
                        text: defaultIpPort
                        onTextChanged: rebuildQr()
                    }

                    Label {
                        text: i18n ? i18n.t("wallet_secret_label") : "Secret"
                        color: "#dddddd"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    TextField {
                        id: secretField
                        Layout.fillWidth: true
                        placeholderText: i18n ? i18n.t("wallet_secret_label") : "Secret"
                        echoMode: TextInput.Password
                        text: defaultSecret
                        onTextChanged: rebuildQr()
                    }
                }
            }

            Rectangle {
                id: qrCard
                Layout.fillWidth: true
                radius: 8
                color: "#252525"
                border.color: "#3a3a3a"
                border.width: 1

                // wichtig gegen Overlap
                implicitHeight: qrBox.implicitHeight + 32

                property int qrCanvasSize: Math.max(140, Math.min(width - 32, 360))

                ColumnLayout {
                    id: qrBox
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Label {
                        text: i18n ? i18n.t("wallet_qr_label") : "Wallet QR"
                        color: "#dddddd"
                        font.pixelSize: 16
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: qrCard.qrCanvasSize
                        height: qrCard.qrCanvasSize

                        Canvas {
                            id: qrCanvas
                            width: qrCard.qrCanvasSize
                            height: qrCard.qrCanvasSize
                            anchors.centerIn: parent
                            antialiasing: false

                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.setTransform(1, 0, 0, 1, 0, 0)

                                if (ctx.imageSmoothingEnabled !== undefined)
                                    ctx.imageSmoothingEnabled = false

                                ctx.clearRect(0, 0, width, height)

                                // weißer Hintergrund (Quiet Zone ist automatisch weiß)
                                ctx.fillStyle = "#ffffff"
                                ctx.fillRect(0, 0, width, height)

                                if (!qrReady || !qrModules || qrModules.length === 0)
                                    return

                                var moduleCount = qrModules.length
                                var totalModules = moduleCount + (quietZoneModules * 2)

                                var size = Math.min(width, height)
                                var moduleSize = Math.floor(size / totalModules)
                                if (moduleSize <= 0)
                                    return

                                var drawSize = moduleSize * totalModules
                                var margin = Math.floor((size - drawSize) / 2)

                                ctx.fillStyle = "#1e1e1e"

                                for (var row = 0; row < moduleCount; ++row) {
                                    for (var col = 0; col < moduleCount; ++col) {
                                        if (qrModules[row][col]) {
                                            var x = margin + (col + quietZoneModules) * moduleSize
                                            var y = margin + (row + quietZoneModules) * moduleSize
                                            ctx.fillRect(x, y, moduleSize, moduleSize)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
