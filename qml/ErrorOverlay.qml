import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property bool active: false
    property alias title: titleLabel.text
    property alias message: descLabel.text
    property var onRetry: null
    property var onIgnore: null

    width: parent ? parent.width * 0.6 : 400
    height: 150
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    anchors.bottomMargin: 20
    visible: active
    z: 99

    Rectangle {
        anchors.fill: parent
        color: "#050000"
        radius: 12
        opacity: 0.95
        border.color: "#660000"
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Label {
            id: titleLabel
            text: "Controller-API not available"
            font.pixelSize: 18
            color: "white"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        Label {
            id: descLabel
            text: "Retry if Controller-Api runs"
            font.pixelSize: 13
            color: "#ccc"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Button {
                text: "Reconnect"
                onClicked: {
                    root.visible = false
                    if (typeof root.onRetry === "function")
                        root.onRetry()
                }
            }

            Button {
                text: "Dismiss"
                onClicked: {
                    root.visible = false
                    if (typeof root.onIgnore === "function")
                        root.onIgnore()
                }
            }
        }
    }
}
