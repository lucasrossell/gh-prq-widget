import AppKit
import SwiftUI

@main
struct PRQueueApp: App {
    @StateObject private var model = QueueModel()

    init() {
        // Info.plist sets LSUIElement for the bundled app; this covers `swift run` too.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            QueuePopover()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// The menu bar item: an icon, with the count beside it when something needs you.
struct MenuBarLabel: View {
    @ObservedObject var model: QueueModel

    var body: some View {
        if model.errorText != nil {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityLabel("PR Queue: couldn't load the queue")
        } else if model.actionableCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.pull")
                Text(model.actionableCount > 99 ? "99+" : "\(model.actionableCount)")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("PR Queue: \(model.actionableCount) need you")
        } else {
            Image(systemName: "arrow.triangle.pull")
                .accessibilityLabel(model.loaded ? "PR Queue: nothing needs you" : "PR Queue: loading")
        }
    }
}
