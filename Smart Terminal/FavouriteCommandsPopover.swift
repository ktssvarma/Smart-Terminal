#if os(macOS)
import SwiftUI

struct FavouriteCommandsPopover: View {
    @ObservedObject var tab: TerminalTab
    @ObservedObject private var store = FavouriteCommandsStore.shared

    var path: String
    var onFilled: (String) -> Void = { _ in }

    private var commands: [FavouriteCommand] {
        store.commands(for: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space2) {
            HStack {
                Text(pathDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button(action: addCurrentCommand) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textPrimary)
                .disabled(currentCommand.isEmpty)
                .help("Save current command")
            }

            if commands.isEmpty {
                Text("No saved commands for this path.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppTheme.space2)
            } else {
                ScrollView {
                    VStack(spacing: AppTheme.space1) {
                        ForEach(commands) { command in
                            FavouriteCommandRow(
                                command: command,
                                onFill: { onFilled(command.command) },
                                onRun: { tab.submitCommand(command.command) },
                                onDelete: {
                                    guard CloseConfirmation.confirmDeleteFavouriteCommand(command.command) else { return }
                                    store.remove(command.id, from: path)
                                },
                                onReorder: { draggedID in
                                    store.move(id: draggedID, before: command.id, path: path)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(AppTheme.space3)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(AppTheme.window)
    }

    private var currentCommand: String {
        tab.commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pathDisplay: String {
        if path.hasPrefix(NSHomeDirectory()) {
            return "~" + path.dropFirst(NSHomeDirectory().count)
        }
        return path
    }

    private func addCurrentCommand() {
        store.add(command: currentCommand, to: path)
    }
}

private struct FavouriteCommandRow: View {
    let command: FavouriteCommand
    var onFill: () -> Void
    var onRun: () -> Void
    var onDelete: () -> Void
    var onReorder: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 14)
                .draggable(command.id.uuidString)

            Text(command.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .draggable(command.command) {
                    Text(command.command)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                                .fill(AppTheme.header)
                        )
                }

            Button(action: onFill) {
                Image(systemName: "text.insert")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .help("Fill input field")

            Button(action: onRun) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .help("Run or queue command")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .help("Delete command")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .fill(AppTheme.fillActive)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value) else { return false }
            onReorder(id)
            return true
        }
    }
}
#endif
