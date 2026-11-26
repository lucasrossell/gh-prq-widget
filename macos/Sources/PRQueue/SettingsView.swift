import AppKit
import PRQueueCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: QueueModel
    // The command applies on Return or when the window closes, not on every keystroke.
    @State private var draftCommand = ""

    var body: some View {
        Form {
            Section {
                TextField("Command", text: $draftCommand)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(applyCommand)
                Text("Runs through your login shell, so PATH from ~/.zprofile applies and Homebrew's bin folders are always included. Aliases from ~/.zshrc aren't loaded, so use the full command. Add flags like --org acme as needed; an older gh-prq without --envelope is detected and handled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Reset to Default") {
                        draftCommand = QueueCommand.defaultCommand
                        applyCommand()
                    }
                    .disabled(draftCommand == QueueCommand.defaultCommand)
                    Spacer()
                    Button("Apply", action: applyCommand)
                        .disabled(draftCommand == model.command)
                }
            }

            Section {
                Stepper(value: $model.refreshMinutes, in: 1...120) {
                    Text(model.refreshMinutes == 1 ? "Refresh every minute" : "Refresh every \(model.refreshMinutes) minutes")
                }
                Toggle("Show PRs waiting on someone else", isOn: $model.showWaiting)
                Toggle("Open a PR in the browser when clicked", isOn: $model.openOnClick)
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            draftCommand = model.command
            // A menu bar app isn't frontmost, so without this the window opens behind everything.
            NSApp.activate()
        }
        .onDisappear(perform: applyCommand)
    }

    private func applyCommand() {
        let trimmed = draftCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftCommand = model.command
            return
        }
        model.command = trimmed
    }
}
