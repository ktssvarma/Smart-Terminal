#if os(macOS)
import AppKit
import SwiftUI

struct AddFavouriteSheet: View {
    var onCancel: () -> Void
    var onSave: (String, String) -> Void
    var onSaveAndNavigate: (String, String) -> Void

    @State private var name = ""
    @State private var path = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var expandedPath: String {
        FavouritePathsStore.expandedPath(path)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !expandedPath.isEmpty
    }

    private var canSaveAndNavigate: Bool {
        canSave && FileManager.default.fileExists(atPath: expandedPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Favourite")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Projects", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("~/Documents", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        choosePath()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Select folder in Finder")
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(trimmedName, expandedPath)
                }
                .disabled(!canSave)
                Button("Save and Navigate") {
                    onSaveAndNavigate(trimmedName, expandedPath)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveAndNavigate)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: expandedPath.isEmpty ? NSHomeDirectory() : expandedPath, isDirectory: true)
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let selected = panel.url?.path else { return }
        path = selected
        if trimmedName.isEmpty {
            name = URL(fileURLWithPath: selected).lastPathComponent
        }
    }
}
#endif
