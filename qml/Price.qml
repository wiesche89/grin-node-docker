import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCharts 2.5

Item {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true

    property bool compactLayout: false
    property var i18n: null
    property var priceSource: null

    property int fallbackTimespanMs: 1000 * 60 * 60 * 24
    property real chartMinTs: Date.now() - fallbackTimespanMs
    property real chartMaxTs: Date.now()
    property real chartMinPrice: 0
    property real chartMaxPrice: 1
    property bool chartHasData: false
    property real candleStickWidthMs: 12 * 60 * 60 * 1000
    property real dailyHighPrice: NaN
    property real dailyLowPrice: NaN
    property real chartPaddingPct: 0.05
    property real axisLabelFontSize: 11
    property bool pageActive: false

    function tr(key, fallback) {
        if (i18n && typeof i18n.t === "function") {
            var translated = i18n.t(key)
            if (translated && translated.length)
                return translated
        }
        return fallback || key
    }

    function formatPrice(val) {
        if (typeof val !== "number" || isNaN(val))
            return tr("price_unknown_value", "-")
        return val.toFixed(4) + "$"
    }

    function formatVolume(val) {
        if (typeof val !== "number" || isNaN(val))
            return tr("price_unknown_value", "-")
        return val.toFixed(2) + "$"
    }

    function formatLatestUpdate(val) {
        if (!val)
            return ""
        var date = new Date(val)
        if (isNaN(date.getTime()))
            return ""
        var format = compactLayout ? "h:mm" : "MMM d - h:mm"
        return Qt.formatDateTime(date, format)
    }

    function toNumber(value) {
        if (typeof value === "number")
            return isFinite(value) ? value : NaN
        if (value === undefined || value === null)
            return NaN
        var attempt = Number(value)
        return isFinite(attempt) ? attempt : NaN
    }

    function updateChart() {
        if (!priceSource || !timeAxis || !valueAxis || !priceCandles)
            return

        var data = priceSource.history || []
        console.log("priceChart history:", data.length,
                    priceSource && priceSource.loading ? "loading" : "idle")
        priceCandles.clear()

        var desiredCandles = 150
        var rawPoints = []
        var minRawTs = Number.MAX_VALUE
        var maxRawTs = 0

        for (var i = 0; i < data.length; ++i) {
            var entry = data[i]
            if (!entry)
                continue
            var parsed = Date.parse(entry.timestamp)
            if (isNaN(parsed))
                continue

            var priceValue = toNumber(entry.price)
            if (isNaN(priceValue)) {
                console.warn("priceChart invalid price entry", entry)
                continue
            }

            rawPoints.push({ timestamp: parsed, price: priceValue })
            minRawTs = Math.min(minRawTs, parsed)
            maxRawTs = Math.max(maxRawTs, parsed)
        }

        rawPoints.sort(function(a, b) { return a.timestamp - b.timestamp })

        var bucketOrigin = minRawTs !== Number.MAX_VALUE ? minRawTs : (Date.now() - fallbackTimespanMs)
        var observedRange = Math.max(maxRawTs - bucketOrigin, fallbackTimespanMs)
        var dayWindowStart = maxRawTs > 0 ? Math.max(maxRawTs - fallbackTimespanMs, minRawTs) : Date.now() - fallbackTimespanMs
        var dayHigh = -Number.MAX_VALUE
        var dayLow = Number.MAX_VALUE
        for (var idx = 0; idx < rawPoints.length; ++idx) {
            var pt = rawPoints[idx]
            if (pt.timestamp >= dayWindowStart) {
                dayHigh = Math.max(dayHigh, pt.price)
                dayLow = Math.min(dayLow, pt.price)
            }
        }
        if (dayHigh === -Number.MAX_VALUE)
            dayHigh = NaN
        if (dayLow === Number.MAX_VALUE)
            dayLow = NaN
        dailyHighPrice = dayHigh
        dailyLowPrice = dayLow
        var bucketSizeMs = Math.max(1, Math.floor(observedRange / desiredCandles))
        var buckets = {}
        var bucketKeys = []

        for (var j = 0; j < rawPoints.length; ++j) {
            var point = rawPoints[j]
            var bucketKey = bucketOrigin + Math.floor((point.timestamp - bucketOrigin) / bucketSizeMs) * bucketSizeMs
            if (!buckets[bucketKey]) {
                buckets[bucketKey] = {
                    timestamp: bucketKey,
                    open: point.price,
                    high: point.price,
                    low: point.price,
                    close: point.price
                }
                bucketKeys.push(bucketKey)
            } else {
                var bucket = buckets[bucketKey]
                bucket.high = Math.max(bucket.high, point.price)
                bucket.low = Math.min(bucket.low, point.price)
                bucket.close = point.price
            }
        }

        bucketKeys.sort(function(a, b) { return a - b })
        if (bucketKeys.length > desiredCandles)
            bucketKeys = bucketKeys.slice(bucketKeys.length - desiredCandles)
        console.log("priceChart buckets:", bucketKeys.length, "bucketSizeMs:", bucketSizeMs)

        var candleEntries = []
        for (var k = 0; k < bucketKeys.length; ++k) {
            var key2 = bucketKeys[k]
            if (buckets[key2])
                candleEntries.push(buckets[key2])
        }

        if (candleEntries.length === 0) {
            console.log("priceChart has no API buckets, waiting for data")
        }

        priceCandles.clear()
        for (var m = 0; m < candleEntries.length; ++m) {
            var candle = candleEntries[m]
            var set = Qt.createQmlObject(
                        'import QtCharts 2.5; CandlestickSet {}',
                        priceCandles,
                        'candlestickSet_' + m)
            if (set) {
                set.timestamp = candle.timestamp
                set.open = candle.open
                set.high = candle.high
                set.low = candle.low
                set.close = candle.close
                priceCandles.append(set)
            }
        }

        var minTs = Number.MAX_VALUE
        var maxTs = 0
        var minPrice = Number.MAX_VALUE
        var maxPrice = -Number.MAX_VALUE
        for (var n = 0; n < candleEntries.length; ++n) {
            var candle = candleEntries[n]
            minTs = Math.min(minTs, candle.timestamp)
            maxTs = Math.max(maxTs, candle.timestamp)
            minPrice = Math.min(minPrice, candle.low)
            maxPrice = Math.max(maxPrice, candle.high)
        }

        var appendedPoints = candleEntries.length
        console.log("priceChart appendedPoints:", appendedPoints, "minPrice:", minPrice, "maxPrice:", maxPrice)
        chartHasData = appendedPoints > 0

        if (chartHasData && maxTs <= minTs)
            maxTs = minTs + fallbackTimespanMs

        if (!chartHasData || minTs === Number.MAX_VALUE) {
            var now = Date.now()
            minTs = now - fallbackTimespanMs
            maxTs = now
            minPrice = 0
            maxPrice = 1
        }

        if (Math.abs(maxPrice - minPrice) < 0.000001) {
            var adjustment = Math.max(0.5, Math.abs(minPrice) * 0.1)
            minPrice = Math.max(0, minPrice - adjustment)
            maxPrice = minPrice + adjustment * 2
        }

        var priceRange = Math.max(0.000001, maxPrice - minPrice)
        minPrice = Math.max(0, minPrice)
        maxPrice = Math.max(maxPrice, minPrice + priceRange)

        // only apply padding to the time axis so the Y axis stays tight to the data
        var tsRange = Math.max(1, maxTs - minTs)
        var tsPad = Math.max(1, tsRange * chartPaddingPct)
        minTs -= tsPad
        maxTs += tsPad

        chartMinTs = minTs
        chartMaxTs = maxTs
        chartMinPrice = minPrice
        chartMaxPrice = maxPrice

        if (chartHasData) {
            console.log("priceChart bounds:",
                        appendedPoints,
                        chartMinPrice.toFixed(6),
                        chartMaxPrice.toFixed(6),
                        new Date(chartMinTs).toISOString(),
                        new Date(chartMaxTs).toISOString())
        }
    }

    Timer {
        id: refreshTimer
        interval: 10 * 60 * 1000
        repeat: true
        running: false
        onTriggered: {
            if (priceSource)
                priceSource.refresh()
        }
    }

    onPageActiveChanged: {
        if (pageActive) {
            refreshTimer.restart()
            if (priceSource)
                priceSource.refresh()
        } else {
            refreshTimer.stop()
        }
    }


    Flickable {
        id: priceScroll
        anchors.fill: parent
        clip: true

        // vertikal scrollen
        contentWidth: width
        contentHeight: contentItemRoot.implicitHeight

        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        // optional: Mausrad (Windows) – smooth
        WheelHandler {
            id: wheel
            target: priceScroll
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        }

        Item {
            width: priceScroll.width
            implicitHeight: priceContent.implicitHeight + 40
            height: implicitHeight

            ColumnLayout {
                id: priceContent
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20
                Layout.fillWidth: true

                Label {
                    text: tr("price_title", "Price analysis")
                    font.pixelSize: compactLayout ? 24 : 28
                    font.bold: true
                    color: "white"
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    BusyIndicator {
                        running: priceSource ? priceSource.loading : false
                        visible: running
                        width: 20
                        height: 20
                    }

                    Label {
                        visible: priceSource && priceSource.errorString.length > 0
                        text: priceSource ? priceSource.errorString : ""
                        color: "#ff5555"
                        font.pixelSize: 13
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 12
                    color: "transparent"
                    border.color: "#333"
                    border.width: 1
                    anchors.margins: 16
                    Layout.preferredHeight: 420
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Label {
                                text: tr("price_chart_symbol", "GRIN-USDT")
                                color: "#bbbbbb"
                                font.pixelSize: 14
                                Layout.leftMargin: 10
                            }

                            Label {
                                visible: priceSource && priceSource.latestTimestamp
                                text: tr("price_latest_update_label", "Latest update:") + " "+formatLatestUpdate(priceSource.latestTimestamp)
                                color: "#999"
                                font.pixelSize: 12
                                Layout.alignment: Qt.AlignRight
                                Layout.fillWidth: true
                            }
                        }

                        ChartView {
                            id: priceChart
                            Layout.fillWidth: true
                            Layout.preferredHeight: 360
                            Layout.minimumHeight: 360
                            anchors.margins: 10

                            antialiasing: true
                            legend.visible: false

                            // Wichtig: KEIN Dark-Theme, das setzt sonst wieder Brushes/Background.
                            theme: ChartView.ChartThemeLight

                            // QML-Farben (alle transparent)
                            backgroundColor: "transparent"
                            plotAreaColor: "transparent"

                            Component.onCompleted: {
                                // 1) Sichtbarkeit der Hintergründe komplett aus
                                priceChart.chart.backgroundVisible = false
                                priceChart.chart.plotAreaBackgroundVisible = false

                                // 2) Zusätzlich: Brushes knallhart transparent setzen (Theme überschreibt gerne Farben)
                                // (QChart properties in QML)
                                priceChart.chart.backgroundBrush = Qt.rgba(0, 0, 0, 0)
                                priceChart.chart.plotAreaBackgroundBrush = Qt.rgba(0, 0, 0, 0)
                            }

                            DateTimeAxis {
                                id: timeAxis
                                format: compactLayout ? "MMM d" : "MMM d - h:mm"
                                tickCount: 5
                                min: chartMinTs > 0 ? new Date(chartMinTs) : new Date()
                                max: chartMaxTs > 0 ? new Date(chartMaxTs) : new Date()
                                labelsFont.pixelSize: axisLabelFontSize
                                titleFont.pixelSize: axisLabelFontSize

                                // Lesbar auf deinem Logo-Background
                                labelsColor: "white"
                                gridLineColor: "#33ffffff"
                            }

                            ValueAxis {
                                id: valueAxis
                                labelFormat: "%.4f"
                                tickCount: 4
                                minorTickCount: 0     // <-- killt genau diese kleinen Striche
                                // optional:
                                gridVisible: true
                                minorGridVisible: false
                                min: chartMinPrice
                                max: chartMaxPrice
                                labelsFont.pixelSize: axisLabelFontSize
                                titleFont.pixelSize: axisLabelFontSize

                                labelsColor: "white"
                                gridLineColor: "#33ffffff"
                            }
                            
                            CandlestickSeries {
                                id: priceCandles
                                axisX: timeAxis
                                axisY: valueAxis
                                increasingColor: "#4caf50"
                                decreasingColor: "#ff6f61"
                                bodyOutlineVisible: true
                                useOpenGL: false
                                visible: chartHasData
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 12
                    color: "transparent"
                    border.color: "#333"
                    border.width: 1
                    Layout.preferredHeight: grid.implicitHeight + 32   // passt sich an
                    clip: true

                    // "Padding" innen
                    Item {
                        anchors.fill: parent
                        anchors.margins: 16

                        // responsive Spaltenanzahl
                        property int columns: width >= 900 ? 4 : (width >= 560 ? 2 : 1)

                        GridLayout {
                            id: grid
                            anchors.fill: parent
                            columns: parent.columns
                            columnSpacing: 16
                            rowSpacing: 16

                            // Hilfs-Komponente: eine Kennzahl-Box
                            component StatBox: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 80
                                radius: 10
                                color: "transparent"          // <-- transparent
                                border.color: "#2a2a2a"
                                border.width: 1

                                property string title: ""
                                property string value: ""
                                property color valueColor: "white"
                                property int valueSize: 26

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6                  // etwas mehr Abstand allgemein

                                    Label {
                                        text: title
                                        color: "#bbbbbb"
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: value
                                        color: valueColor
                                        font.pixelSize: valueSize
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // zusätzlicher Raum unter dem Wert
                                    Item {
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 8
                                    }
                                }
                            }

                            StatBox {
                                title: tr("price_latest_title", "Latest price")
                                value: formatPrice(priceSource ? priceSource.latestPriceUsd : NaN)
                                valueColor: "white"
                                valueSize: compactLayout ? 24 : 28
                            }

                            StatBox {
                                title: tr("price_volume_label", "Volume (USD)")
                                value: formatVolume(priceSource ? priceSource.latestVolumeUsd : NaN)
                                valueColor: "#8cd9ff"
                                valueSize: compactLayout ? 20 : 24
                            }

                            StatBox {
                                title: tr("price_daily_high_label", "Highest daily price")
                                value: formatPrice(dailyHighPrice)
                                valueColor: "#4caf50"
                                valueSize: compactLayout ? 24 : 28
                            }

                            StatBox {
                                title: tr("price_daily_low_label", "Lowest daily price")
                                value: formatPrice(dailyLowPrice)
                                valueColor: "#f44336"
                                valueSize: compactLayout ? 24 : 28
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: priceSource
        function onHistoryChanged() { updateChart() }
        function onLoadingChanged() { updateChart() }
        function onErrorStringChanged() { updateChart() }
    }

    onPriceSourceChanged: updateChart()
}
