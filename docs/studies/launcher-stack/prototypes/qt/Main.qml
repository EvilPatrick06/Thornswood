import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    width: 1220; height: 800
    color: "#14110e"
    Image { anchors.fill: parent; source: artUrl; fillMode: Image.PreserveAspectCrop }
    Column {
        x: 48; anchors.bottom: parent.bottom; anchors.bottomMargin: 48; spacing: 12
        Text { text: "THORNSWOOD"; font.pixelSize: 40; color: "#eadfc8" }
        Button { text: "Play"; width: 220; height: 56; font.pixelSize: 20; onClicked: proto.play() }
        Text { text: proto.state; color: "white" }
    }
}
