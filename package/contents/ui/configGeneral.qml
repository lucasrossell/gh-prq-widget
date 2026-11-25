import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_command: commandField.text
    property alias cfg_refreshMinutes: refreshSpin.value
    property alias cfg_showWaiting: showWaitingBox.checked
    property alias cfg_openOnClick: openOnClickBox.checked

    Kirigami.FormLayout {
        QQC2.TextField {
            id: commandField
            Kirigami.FormData.label: i18n("Command:")
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 22
            font.family: "monospace"
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Runs like a line typed in a terminal, but without your shell aliases. If gh lives in a distrobox, prefix it, e.g. \"distrobox enter fedora -- gh prq --json --envelope\". Older gh-prq without --envelope is detected and handled.")
        }

        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh every:")
            from: 1
            to: 120
            textFromValue: (value) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text) => parseInt(text)
        }

        QQC2.CheckBox {
            id: showWaitingBox
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("PRs waiting on someone else")
        }
        QQC2.CheckBox {
            id: openOnClickBox
            text: i18n("Open a PR in the browser when clicked")
        }
    }
}
