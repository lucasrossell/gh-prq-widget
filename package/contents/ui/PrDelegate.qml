import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmaComponents3.ItemDelegate {
    id: delegate

    required property string repo
    required property int number
    required property string title
    required property string url
    required property string reason
    required property string ciState
    required property string badges
    required property string actionSince

    hoverEnabled: root.openOnClick
    down: root.openOnClick && pressed
    onClicked: if (root.openOnClick) Qt.openUrlExternally(url)

    readonly property color ciColor: {
        switch (ciState) {
        case "SUCCESS": return Kirigami.Theme.positiveTextColor;
        case "FAILURE":
        case "ERROR": return Kirigami.Theme.negativeTextColor;
        case "PENDING": return Kirigami.Theme.neutralTextColor;
        default: return "transparent";
        }
    }

    PlasmaComponents3.ToolTip.text: title
    PlasmaComponents3.ToolTip.visible: hovered && titleLabel.truncated
    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing * 2

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: (titleLabel.implicitHeight - height) / 2
            implicitWidth: Kirigami.Units.smallSpacing * 2
            implicitHeight: implicitWidth
            radius: width / 2
            color: delegate.ciColor
            border.width: delegate.ciState === "NONE" ? 1 : 0
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.3)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                id: titleLabel
                Layout.fillWidth: true
                text: delegate.title
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: [
                    `${delegate.repo}#${delegate.number}`,
                    delegate.reason,
                    delegate.badges,
                    root.relativeTime(delegate.actionSince),
                ].filter((part) => part !== "").join(" · ")
                elide: Text.ElideRight
                maximumLineCount: 1
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }
    }
}
