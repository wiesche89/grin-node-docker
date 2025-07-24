import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: homeRoot
    Layout.fillWidth: true
    Layout.fillHeight: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // Kopfzeile
        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            Label {
                text: "GrinMesh Dashboard"
                color: "white"
                font.pixelSize: 28
                font.bold: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }
        }

        // StatusView
        StatusView {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
        }

        // PeerListView
        PeerListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
