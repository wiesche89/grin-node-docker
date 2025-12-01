import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ------------------------------------------------------------------
// ErrorOverlay
// Reusable overlay for controller / network errors.
// - Shows a short title and description
// - "Retry" and "Dismiss" via signals
// - Fully i18n-aware via injected i18n object
// ------------------------------------------------------------------
Item {
    id: root

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------
    // Aktiviert / deaktiviert das Overlay
    property bool active: false

    // Titel- und Nachrichtentext, können von außen überschrieben werden
    property string titleText: ""
    property string messageText: ""

    // i18n-Objekt (QtObject mit t(key)-Funktion), von außen gesetzt
    property var i18n: null

    // Signale für Buttons
    signal retry()
    signal ignore()

    // ------------------------------------------------------------------
    // Geometry / visual state
    // ------------------------------------------------------------------
    width: parent ? parent.width * 0.6 : 400
    height: 150
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    anchors.bottomMargin: 20
    visible: active
    z: 99

    // ------------------------------------------------------------------
    // Local translation helper
    // ------------------------------------------------------------------
    function tr(key, fallback) {
        if (i18n && typeof i18n.t === "function")
            return i18n.t(key)
        return fallback || key
    }

    // ------------------------------------------------------------------
    // Background card
    // ------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#050000"
        radius: 12
        opacity: 0.95
        border.color: "#660000"
        border.width: 1
    }

    // ------------------------------------------------------------------
    // Content layout: title, description, buttons
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        // Titel
        Label {
            id: titleLabel
            text: titleText.length > 0
                  ? titleText
                  : tr("error_overlay_controller_title", "Controller-API not available")
            font.pixelSize: 18
            color: "white"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        // Beschreibung
        Label {
            id: descLabel
            text: messageText.length > 0
                  ? messageText
                  : tr("error_overlay_controller_desc", "Retry when the controller API is running.")
            font.pixelSize: 13
            color: "#ccc"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        // Buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Button {
                text: tr("error_overlay_btn_dismiss", "Dismiss")
                onClicked: {
                    root.active = false
                    root.ignore()
                }
            }
        }
    }
}
