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
            return tr("price_unknown_value", "n/a")
        return "$" + val.toFixed(3)
    }

    function toNumber(value) {
        if (typeof value === "number")
            return isFinite(value) ? value : NaN
        if (value === undefined || value === null)
            return NaN
        var attempt = Number(value)
        return isFinite(attempt) ? attempt : NaN
    }

    function createDummyCandles(bucketSizeMs) {
        var template = [
            {open: 0.03545, high: 0.03585, low: 0.03495, close: 0.03525},
            {open: 0.03520, high: 0.03560, low: 0.03490, close: 0.03540},
            {open: 0.03540, high: 0.03590, low: 0.03510, close: 0.03565},
            {open: 0.03565, high: 0.03605, low: 0.03530, close: 0.03585},
            {open: 0.03585, high: 0.03610, low: 0.03555, close: 0.03595},
            {open: 0.03595, high: 0.03620, low: 0.03565, close: 0.03575}
        ]

        var now = Date.now()
        var list = []
        for (var i = 0; i < template.length; ++i) {
            var idxFromEnd = template.length - 1 - i
            var ts = now - idxFromEnd * bucketSizeMs
            var sample = template[i]
            list.push({
                timestamp: ts,
                open: sample.open,
                high: sample.high,
                low: sample.low,
                close: sample.close
            })
        }
        return list
    }

    function updateChart() {
        if (!priceSource || !timeAxis || !valueAxis || !priceCandles)
            return

        var data = priceSource.history || []
        console.log("priceChart history:", data.length,
                    priceSource && priceSource.loading ? "loading" : "idle")
        priceCandles.clear()
        priceLine.clear()

        var desiredCandles = 100
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
            console.log("priceChart falling back to dummy candles")
            candleEntries = createDummyCandles(bucketSizeMs)
        }

        priceCandles.clear()
        priceLine.clear()
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
            priceLine.append(candle.timestamp, candle.close)
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

    ScrollView {
        id: priceScroll
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.Never

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

                    Button {
                        text: tr("headerbar_btn_refresh", "Refresh")
                        enabled: priceSource !== null
                        onClicked: priceSource.refresh()
                    }

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
                    color: "#1f1f1f"
                    border.color: "#333"
                    border.width: 1
                    anchors.margins: 16
                    Layout.preferredHeight: 320

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        Label {
                            text: tr("price_history_title", "Recent price points")
                            font.pixelSize: 16
                            color: "#ffffff"
                        }

                        ChartView {
                            id: priceChart
                            Layout.fillWidth: true
                            Layout.preferredHeight: 260
                            anchors.margins: 10
                            antialiasing: true
                            legend.visible: false
                            backgroundColor: "#1f1f1fcc"
                            plotAreaColor: "#111215"
                            theme: ChartView.ChartThemeDark

                            DateTimeAxis {
                                id: timeAxis
                                format: compactLayout ? "MMM d" : "MMM d - h:mm"
                                tickCount: 5
                                min: chartMinTs > 0 ? new Date(chartMinTs) : new Date()
                                max: chartMaxTs > 0 ? new Date(chartMaxTs) : new Date()
                            }

                            ValueAxis {
                                id: valueAxis
                                labelFormat: "%.2f"
                                tickCount: 4
                                min: chartMinPrice
                                max: chartMaxPrice
                            }

                            CandlestickSeries {
                                id: priceCandles
                                axisX: timeAxis
                                axisY: valueAxis
                                increasingColor: "#4ec1ff"
                                decreasingColor: "#ff6f61"
                                useOpenGL: false
                                visible: chartHasData
                            }

                            LineSeries {
                                id: priceLine
                                axisX: timeAxis
                                axisY: valueAxis
                                color: "#8cd9ff"
                                useOpenGL: false
                                visible: chartHasData
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                visible: !chartHasData && !(priceSource && priceSource.loading)

                                Label {
                                    anchors.centerIn: parent
                                    text: tr("price_history_empty", "No data available")
                                    color: "#888"
                                    font.pixelSize: 14
                                }
                            }

                            Component.onCompleted: updateChart()
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: priceSource ? priceSource.recentHistory : []
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    color: "#121212"
                                    radius: 6
                                    border.color: "#333"
                                    border.width: 1
                                    anchors.margins: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        Label {
                                            text: model && model.timestamp ? model.timestamp : ""
                                            color: "#cccccc"
                                            font.pixelSize: 12
                                        }

                                        Label {
                                            text: formatPrice(model.price)
                                            color: "#ffffff"
                                            font.pixelSize: 14
                                            Layout.alignment: Qt.AlignRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            Label {
                                visible: !(priceSource && priceSource.recentHistory && priceSource.recentHistory.length)
                                text: tr("price_history_empty", "No data available")
                                color: "#999"
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: 12
                    color: "#2a2a2a"
                    border.color: "#444"
                    border.width: 1
                    anchors.margins: 16

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 6

                        Label {
                            text: tr("price_latest_title", "Latest price")
                            color: "#bbbbbb"
                            font.pixelSize: 14
                        }

                        Label {
                            text: formatPrice(priceSource ? priceSource.latestPriceUsd : NaN)
                            color: "white"
                            font.pixelSize: compactLayout ? 34 : 48
                            font.bold: true
                        }

                        Label {
                            text: priceSource ? priceSource.latestTimestamp : ""
                            color: "#777"
                            font.pixelSize: 14
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        radius: 10
                        color: "#222"
                        border.color: "#333"
                        border.width: 1
                        anchors.margins: 12

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            Label {
                                text: tr("price_high_label", "Highest price")
                                color: "#bbbbbb"
                                font.pixelSize: 13
                            }
                            Label {
                                text: formatPrice(priceSource ? priceSource.highestPriceUsd : NaN)
                                color: "#4caf50"
                                font.pixelSize: 22
                                font.bold: true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120
                        radius: 10
                        color: "#222"
                        border.color: "#333"
                        border.width: 1
                        anchors.margins: 12

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            Label {
                                text: tr("price_low_label", "Lowest price")
                                color: "#bbbbbb"
                                font.pixelSize: 13
                            }
                            Label {
                                text: formatPrice(priceSource ? priceSource.lowestPriceUsd : NaN)
                                color: "#f44336"
                                font.pixelSize: 22
                                font.bold: true
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
