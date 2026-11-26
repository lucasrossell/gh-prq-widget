import AppKit
import PRQueueCore
import SwiftUI

/// The panel that opens from the menu bar: the macOS take on the Plasma full representation.
struct QueuePopover: View {
    @EnvironmentObject private var model: QueueModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 380, height: 440)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.actionableCount > 0 ? "PR Queue (\(model.actionableCount))" : "PR Queue")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if let fetchedAt = model.fetchedAt {
                let ago = RelativeTime.string(since: fetchedAt, now: model.now)
                if let stale = model.staleReason {
                    Label("offline · \(ago)", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Showing a cached queue: \(stale)")
                } else {
                    Text(ago)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                model.refresh()
            } label: {
                if model.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 18, height: 18)
            .disabled(model.busy)
            .help("Refresh")
            .keyboardShortcut("r")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        if model.summary.sections.isEmpty {
            placeholder
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.summary.sections) { section in
                        Section {
                            ForEach(section.items) { pr in
                                PRRow(pr: pr)
                            }
                        } header: {
                            Text(section.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.bar)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let error = model.errorText {
            ContentUnavailableView {
                Label("Couldn't load the queue", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).textSelection(.enabled)
            } actions: {
                SettingsLink { Text("Check the command…") }
            }
        } else if !model.loaded {
            ProgressView("Loading…")
        } else {
            ContentUnavailableView {
                Label("Nothing needs you", systemImage: "checkmark.circle")
            } description: {
                if model.summary.waitingCount > 0 && !model.showWaiting {
                    let n = model.summary.waitingCount
                    Text(n == 1 ? "1 PR is waiting on someone else" : "\(n) PRs are waiting on someone else")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct PRRow: View {
    @EnvironmentObject private var model: QueueModel
    let pr: PullRequest
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            CIDot(state: pr.ciState)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(pr.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(pr.subtitle(now: model.now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if hovering && model.openOnClick {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .padding(.horizontal, 5)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.open(pr) }
        .help(pr.title)
        .contextMenu {
            if let url = pr.webURL {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(model.openOnClick ? .isLink : [])
    }
}

struct CIDot: View {
    let state: CIState

    var body: some View {
        Group {
            switch state {
            case .success: Circle().fill(.green)
            case .failure, .error: Circle().fill(.red)
            case .pending: Circle().fill(.orange)
            case .none: Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch state {
        case .success: "CI passing"
        case .failure, .error: "CI failing"
        case .pending: "CI running"
        case .none: "No CI"
        }
    }
}
