import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 2.15

Item {
    anchors.fill: parent

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // 🔹 scrollbarer Editor füllt alles außer Platz für Buttons
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            TextArea {
                id: editor
                width: parent.width
                wrapMode: TextArea.NoWrap
                text: config.text
                onTextChanged: config.text = text
                font.family: "Consolas"
                font.pointSize: 11

                background: Rectangle {
                    color: "#111"
                    radius: 6
                    border.color: "#444"
                }
                color: "#e6e6e6"
                selectionColor: "#355c7d"
                selectedTextColor: "white"
                cursorDelegate: Rectangle { width: 2; color: "#66ccff" }
            }
        }

        // 🔹 Button-Leiste unten rechts
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Label {
                text: "Datei: " + config.path
                color: "#bbb"
                elide: Label.ElideRight
                Layout.fillWidth: true
            }

            Button {
                text: "Neu laden"
                onClicked: {
                    if (!config.load()) {
                        toast.text = "Fehler: " + config.errorString
                        toast.color = "crimson"
                        toast.open()
                    } else {
                        toast.text = "Neu geladen."
                        toast.color = "darkseagreen"
                        toast.open()
                    }
                }
            }

            Button {
                text: "Speichern"
                onClicked: {
                    if (!config.save()) {
                        toast.text = "Speichern fehlgeschlagen: " + config.errorString
                        toast.color = "crimson"
                        toast.open()
                    } else {
                        toast.text = "Gespeichert."
                        toast.color = "darkseagreen"
                        toast.open()
                    }
                }
            }
        }
    }

    // 🔹 Toast mittig im Fenster
    Popup {
        id: toast
        modal: false
        focus: false
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        contentItem: Rectangle {
            radius: 10
            color: toast.color
            border.color: "#333"
            border.width: 1

            Text {
                id: toastText
                text: toast.text
                color: "white"
                font.pixelSize: 18
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                anchors.centerIn: parent
            }

            implicitWidth: Math.max(300, toastText.implicitWidth + 40)
            implicitHeight: toastText.implicitHeight + 30
        }

        property string text: ""
        property color color: "#444"

        function show(message, c) {
            text = message
            color = c
            open()
            Qt.createQmlObject(
                "import QtQuick 2.15; Timer { interval: 2000; running: true; repeat: false; onTriggered: toast.close() }",
                toast, "autoCloseTimer"
            )
        }
    }
}
