import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ----------------------------------------------------------------------
// HeaderBar
// Top toolbar for pages that require a title + refresh button.
// Fully internationalized via an injected i18n object.
// Emits "refreshClicked" when the refresh button is pressed.
// ----------------------------------------------------------------------
ToolBar {
    id: root

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------
    signal refreshClicked()
    property var i18n: null        // global translation object injected from Main.qml

    // ------------------------------------------------------------------
    // Local i18n helper
    // ------------------------------------------------------------------
    function tr(key, fallback) {
        if (i18n && typeof i18n.t === "function")
            return i18n.t(key)
        return fallback || key
    }

    // ------------------------------------------------------------------
    // Background styling
    // ------------------------------------------------------------------
    background: Rectangle {
        color: "#212121"
        border.color: "#333"
    }

    // Main content wrapper
    Item {
        anchors.fill: parent
        anchors.margins: 12   // inner padding

        RowLayout {
            anchors.fill: parent
            spacing: 20

            // ----------------------------------------------------------
            // Page title
            // (replaceable via translation keys)
            // ----------------------------------------------------------
            Label {
                text: tr("headerbar_title_dashboard", "Grin Node Dashboard")
                font.pixelSize: 22
                font.bold: true
                color: "white"
                Layout.alignment: Qt.AlignVCenter
            }

            // Flexible space between title and buttons
            Item { Layout.fillWidth: true }

            // ----------------------------------------------------------
            // Refresh button
            // ----------------------------------------------------------
            Button {
                text: "🔄 " + tr("headerbar_btn_refresh", "Refresh")
                font.pixelSize: 16
                onClicked: root.refreshClicked()
            }
        }
    }
}
