import SwiftUI
#if os(macOS)
import AppKit
#endif
#if canImport(Playgrounds)
import Playgrounds
#endif

@main struct MyApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(TerminalAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .containerBackground(for: .window) {
                    AppTheme.window
                }
                .modifier(HiddenWindowToolbarBackground())
                .background(PersistentWindowDimensions())
                .preferredColorScheme(.dark)
                #endif
        }
        .defaultSize(width: 800, height: 500)
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            TerminalCommands()
        }
        #endif
    }
}

struct ContentView: View {
    #if os(macOS)
    @StateObject private var tabs = TabManager()
    @AppStorage("SmartTerminal.sidebarCollapsed") private var isCollapsed = false
    @State private var isTerminalDropTarget = false
    #endif

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TerminalTabBar(manager: tabs)

                VStack(spacing: AppTheme.space2) {
                    ZStack {
                        AppTheme.terminal
                        ForEach(tabs.tabs) { tab in
                            TerminalView(session: tab.session, isActive: tab.id == tabs.selectedID)
                                .opacity(tab.id == tabs.selectedID ? 1 : 0)
                                .allowsHitTesting(tab.id == tabs.selectedID)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.terminalCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.terminalCorner, style: .continuous)
                            .strokeBorder(isTerminalDropTarget ? Color.white.opacity(0.35) : AppTheme.border, lineWidth: isTerminalDropTarget ? 2 : 1)
                    )
                    .dropDestination(for: String.self) { items, _ in
                        guard let tab = tabs.selectedTab,
                              let command = items.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !command.isEmpty else { return false }
                        tab.submitCommand(command)
                        return true
                    } isTargeted: { isTerminalDropTarget = $0 }

                    if let tab = tabs.selectedTab {
                        TerminalCommandField(tab: tab)
                    }
                }
                .padding(AppTheme.space2)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

            if let tab = tabs.selectedTab {
                WindowStatusBar(tab: tab)
                    .id(tab.id)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(AppTheme.window)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        isCollapsed.toggle()
                    } label: {
                        Image(systemName: isCollapsed ? "sidebar.right" : "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Expand Sidebar" : "Collapse Sidebar")

                    if let tab = tabs.selectedTab {
                        ActiveTerminalTitle(tab: tab)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
            }
        }
        .background(WindowTabManagerBinder(manager: tabs))
        .onAppear {
            tabs.onCloseWindow = {
                NSApp.keyWindow?.performClose(nil)
            }
            DispatchQueue.main.async {
                CommandFieldFocus.isActive = false
                tabs.selectedTab?.session.focus()
            }
        }
        .onChange(of: tabs.selectedID) { _, _ in
            DispatchQueue.main.async {
                CommandFieldFocus.isActive = false
                tabs.selectedTab?.session.focus()
            }
        }
        .onDisappear {
            tabs.shutdown()
        }
        #else
        Text("Smart Terminal is available on macOS.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#if os(macOS)
private struct TerminalCommandField: View {
    @ObservedObject var tab: TerminalTab
    @ObservedObject private var commandFavourites = FavouriteCommandsStore.shared
    @State private var showFavourites = false
    @State private var fillCommand = ""
    @State private var isFieldDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space1) {
            if tab.isQueuePaused, !tab.commandQueue.isEmpty {
                Text("Queue paused")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if !tab.commandQueue.isEmpty {
                ScrollView {
                    VStack(spacing: AppTheme.space1) {
                        ForEach(tab.commandQueue) { command in
                            QueuedCommandRow(command: command) {
                                tab.removeQueuedCommand(command.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            CommandFlowEditor(tab: tab, fillCommand: $fillCommand) {
                favouritesButton
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .fill(isFieldDropTarget ? AppTheme.fillActive : AppTheme.header)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .strokeBorder(isFieldDropTarget ? Color.white.opacity(0.35) : AppTheme.border, lineWidth: isFieldDropTarget ? 2 : 1)
            )
            .dropDestination(for: String.self) { items, _ in
                guard let command = items.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !command.isEmpty,
                      UUID(uuidString: command) == nil else { return false }
                fillCommand = command
                return true
            } isTargeted: { isFieldDropTarget = $0 }
        }
    }

    private var favouritesButton: some View {
        Button {
            showFavourites.toggle()
        } label: {
            Image(systemName: hasFavourites ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasFavourites ? Color.yellow.opacity(0.85) : AppTheme.textSecondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help("Command favourites")
        .background(
            AnchoredPopover(isPresented: $showFavourites) {
                FavouriteCommandsPopover(
                    tab: tab,
                    path: currentPath,
                    onFilled: fillFavourite,
                    onRun: runFavourite
                )
            }
            .frame(width: 20, height: 20)
        )
    }

    private var currentPath: String {
        tab.session.resolvedWorkingDirectory()
            ?? tab.session.workingDirectory
            ?? NSHomeDirectory()
    }

    private var hasFavourites: Bool {
        !commandFavourites.commands(for: currentPath).isEmpty
    }

    private func fillFavourite(_ command: String) {
        fillCommand = command
        showFavourites = false
    }

    private func runFavourite(_ command: String) {
        showFavourites = false
        DispatchQueue.main.async {
            tab.submitCommand(command)
        }
    }
}

private struct QueuedCommandRow: View {
    let command: QueuedCommand
    var onDelete: () -> Void
    @State private var draft: String

    init(command: QueuedCommand, onDelete: @escaping () -> Void) {
        self.command = command
        self.onDelete = onDelete
        _draft = State(initialValue: command.text)
    }

    var body: some View {
        HStack(spacing: AppTheme.space2) {
            Text("Queued")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            if let hint = command.continueHint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            TextField("Command", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .onChange(of: draft) { _, newValue in
                    command.text = newValue
                }
                .onSubmit {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        onDelete()
                    } else {
                        draft = text
                        command.text = text
                    }
                }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .help("Remove from queue")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .fill(AppTheme.header)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct ActiveTerminalTitle: View {
    @ObservedObject var tab: TerminalTab

    var body: some View {
        Text(tab.title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 48, maxWidth: 220, minHeight: 16, alignment: .leading)
    }
}
#endif

#Preview {
    ContentView()
}

#if canImport(Playgrounds)
#Playground {
    _ = 1 + 2
}
#endif
