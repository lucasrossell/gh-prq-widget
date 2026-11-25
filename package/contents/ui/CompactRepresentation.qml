import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    hoverEnabled: true
    onClicked: root.expanded = !root.expanded

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        source: Plasmoid.icon
        active: compact.containsMouse
        opacity: root.loaded && root.actionableCount === 0 && root.errorText === "" ? 0.6 : 1
    }

    Rectangle {
        visible: root.actionableCount > 0 || root.errorText !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(Kirigami.Units.iconSizes.small * 0.8, badgeLabel.implicitHeight)
        width: Math.max(height, badgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2)
        radius: height / 2
        color: root.errorText !== "" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor

        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: root.errorText !== "" ? "!" : (root.actionableCount > 99 ? "99+" : root.actionableCount)
            color: Kirigami.Theme.highlightedTextColor
            font.pixelSize: Math.round(compact.height * 0.32)
            font.bold: true
        }
    }
}
