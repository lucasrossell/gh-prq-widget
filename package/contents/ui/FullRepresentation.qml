import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: full

    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredHeight: Kirigami.Units.gridUnit * 22
    Layout.minimumWidth: Kirigami.Units.gridUnit * 14
    Layout.minimumHeight: Kirigami.Units.gridUnit * 10

    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                Layout.leftMargin: Kirigami.Units.smallSpacing
                level: 3
                text: root.actionableCount > 0 ? i18n("PR Queue (%1)", root.actionableCount) : i18n("PR Queue")
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                visible: root.fetchedAt !== ""
                text: root.staleReason !== "" ? i18n("offline · %1", root.relativeTime(root.fetchedAt)) : root.relativeTime(root.fetchedAt)
                color: root.staleReason !== "" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                opacity: root.staleReason !== "" ? 1 : 0.6
                font: Kirigami.Theme.smallFont

                PlasmaComponents3.ToolTip.text: root.staleReason !== "" ? i18n("Showing a cached queue: %1", root.staleReason) : ""
                PlasmaComponents3.ToolTip.visible: root.staleReason !== "" && staleHover.hovered
                HoverHandler { id: staleHover }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: !root.busy
                onClicked: root.refresh()
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18n("Refresh")
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                PlasmaComponents3.BusyIndicator {
                    anchors.fill: parent
                    visible: root.busy
                    running: visible
                }
            }
        }
    }

    PlasmaComponents3.ScrollView {
        anchors.fill: parent
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        contentItem: ListView {
            id: list
            model: prModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 0

            section.property: "bucketLabel"
            section.criteria: ViewSection.FullString
            section.delegate: PlasmaExtras.ListSectionHeader {
                required property string section
                width: ListView.view.width
                text: section
            }

            delegate: PrDelegate {
                width: ListView.view.width
            }
        }
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: list.count === 0
        iconName: root.errorText !== "" ? "dialog-error" : (root.loaded ? "checkmark" : "")
        text: {
            if (root.errorText !== "") return i18n("Couldn't load the queue");
            if (!root.loaded) return i18n("Loading…");
            return i18n("Nothing needs you");
        }
        explanation: {
            if (root.errorText !== "") return root.errorText;
            if (root.loaded && root.waitingCount > 0 && !root.showWaiting)
                return i18np("%1 PR is waiting on someone else", "%1 PRs are waiting on someone else", root.waitingCount);
            return "";
        }
    }
}
