import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Mirrors BUCKET_LABELS / ACTIONABLE_BUCKETS / WAITING_BUCKETS in gh-prq's src/core/types.ts.
    readonly property var bucketLabels: ({
        NEEDS_REREVIEW: i18n("Needs Re-review"),
        NEEDS_INITIAL_REVIEW: i18n("Needs Review"),
        MY_PR_ACTION_NEEDED: i18n("My PRs — Action Needed"),
        MY_PR_READY: i18n("My PRs — Ready to Merge"),
        WAITING_ON_AUTHOR: i18n("Waiting on Author"),
        MY_PR_WAITING: i18n("My PRs — Waiting"),
    })
    readonly property var actionableBuckets: ["NEEDS_REREVIEW", "NEEDS_INITIAL_REVIEW", "MY_PR_ACTION_NEEDED", "MY_PR_READY"]
    readonly property var waitingBuckets: ["WAITING_ON_AUTHOR", "MY_PR_WAITING"]

    readonly property string command: Plasmoid.configuration.command
    readonly property bool showWaiting: Plasmoid.configuration.showWaiting
    readonly property bool openOnClick: Plasmoid.configuration.openOnClick

    property var allItems: []
    property int actionableCount: 0
    property int waitingCount: 0
    property string fetchedAt: ""
    property string staleReason: ""
    property string errorText: ""
    property bool loaded: false
    property bool busy: false
    property real busySince: 0
    // Set once a gh-prq without --envelope rejects the flag; reset when the command changes.
    property bool legacyJson: false
    property real now: Date.now()

    ListModel { id: prModel }

    Plasmoid.icon: "vcs-merge-request"
    Plasmoid.status: actionableCount > 0 || errorText !== "" ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: i18n("PR Queue")
    toolTipSubText: {
        if (errorText !== "") return i18n("Couldn't load the queue");
        if (!loaded) return i18n("Loading…");
        return actionableCount > 0 ? i18np("%1 PR needs you", "%1 PRs need you", actionableCount) : i18n("Nothing needs you");
    }

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 10

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh Now")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    function effectiveCommand() {
        return legacyJson ? command.replace(/\s--envelope\b/, "") : command;
    }

    function refresh() {
        if (busy || command.trim() === "") return;
        busy = true;
        busySince = Date.now();
        executable.connectSource(effectiveCommand());
    }

    function relativeTime(iso) {
        const t = Date.parse(iso);
        if (isNaN(t)) return "";
        const s = Math.max(0, Math.round((now - t) / 1000));
        if (s < 60) return i18n("just now");
        if (s < 3600) return i18n("%1m ago", Math.floor(s / 60));
        if (s < 86400) return i18n("%1h ago", Math.floor(s / 3600));
        return i18n("%1d ago", Math.floor(s / 86400));
    }

    function rebuildModel() {
        prModel.clear();
        let actionable = 0;
        let waiting = 0;
        for (const pr of allItems) {
            const isActionable = actionableBuckets.indexOf(pr.bucket) !== -1;
            const isWaiting = waitingBuckets.indexOf(pr.bucket) !== -1;
            if (isActionable) actionable++;
            if (isWaiting) waiting++;
            if (!isActionable && !(showWaiting && isWaiting)) continue;
            prModel.append({
                bucketLabel: bucketLabels[pr.bucket] || pr.bucket,
                repo: pr.repo,
                number: pr.number,
                title: pr.title,
                url: pr.url,
                reason: pr.reason || "",
                ciState: pr.ciState || "NONE",
                badges: (pr.badges || []).join(" · "),
                actionSince: pr.actionSince || pr.updatedAt || "",
            });
        }
        actionableCount = actionable;
        waitingCount = waiting;
    }

    function handleResult(sourceName, data) {
        const exitCode = data["exit code"];
        const stdout = data["stdout"] || "";
        const stderr = data["stderr"] || "";

        if (exitCode !== 0 && !legacyJson && /--envelope/.test(stderr)) {
            legacyJson = true;
            busy = false;
            refresh();
            return;
        }
        if (exitCode !== 0) {
            const lines = stderr.trim().split("\n");
            errorText = lines[lines.length - 1] || i18n("Command exited with code %1", exitCode);
            return;
        }

        let parsed;
        try {
            parsed = JSON.parse(stdout);
        } catch (e) {
            errorText = i18n("Output wasn't JSON. Does the command include --json?");
            return;
        }
        if (Array.isArray(parsed)) {
            // Plain --json: no fetch time, so stamp it with when we read it.
            allItems = parsed;
            fetchedAt = new Date().toISOString();
            const stale = stderr.match(/stale cache \((.*)\)/);
            staleReason = stale ? stale[1] : "";
        } else {
            allItems = parsed.items || [];
            fetchedAt = parsed.fetchedAt || new Date().toISOString();
            staleReason = parsed.staleReason || "";
        }
        errorText = "";
        loaded = true;
        now = Date.now();
        rebuildModel();
    }

    onShowWaitingChanged: rebuildModel()
    onCommandChanged: {
        legacyJson = false;
        refresh();
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.busy = false;
            root.handleResult(sourceName, data);
        }
    }

    Timer {
        interval: Math.max(1, Plasmoid.configuration.refreshMinutes) * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now();
            // A stuck distrobox or gh would otherwise block every later refresh.
            if (root.busy && root.now - root.busySince > 120 * 1000) {
                for (const source of executable.connectedSources) executable.disconnectSource(source);
                root.busy = false;
                root.errorText = i18n("The command timed out after 2 minutes");
            }
        }
    }

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}
}
