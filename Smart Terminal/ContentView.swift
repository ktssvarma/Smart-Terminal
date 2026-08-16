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
    @State private var focusToken = 0
    @State private var showFavourites = false
    @State private var focusAfterFavouritesClose = false
    @State private var isFieldDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space1) {
            if !tab.commandQueue.isEmpty {
                ScrollView {
                    VStack(spacing: AppTheme.space1) {
                        ForEach(tab.commandQueue) { command in
                            QueuedCommandRow(
                                command: command,
                                onDelete: {
                                    DispatchQueue.main.async {
                                        tab.removeQueuedCommand(command.id)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            HStack(spacing: AppTheme.space2) {
                HStack(spacing: AppTheme.space2) {
                    Text("$")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)

                    CommandLineTextField(
                        text: $tab.commandDraft,
                        placeholder: placeholder,
                        focusToken: focusToken,
                        onSubmit: submit
                    )
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let command = items.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !command.isEmpty,
                          UUID(uuidString: command) == nil else { return false }
                    tab.commandDraft = command
                    return true
                } isTargeted: { isFieldDropTarget = $0 }

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
                .popover(isPresented: $showFavourites, arrowEdge: .top) {
                    FavouriteCommandsPopover(tab: tab, path: currentPath, onFilled: fillFavourite)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .fill(isFieldDropTarget ? AppTheme.fillActive : AppTheme.header)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .strokeBorder(isFieldDropTarget ? Color.white.opacity(0.35) : AppTheme.border, lineWidth: isFieldDropTarget ? 2 : 1)
            )
        }
        .onChange(of: showFavourites) { _, showing in
            guard !showing, focusAfterFavouritesClose else { return }
            focusAfterFavouritesClose = false
            CommandFieldFocus.isActive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focusToken += 1
            }
        }
    }

    private var currentPath: String {
        tab.session.resolvedWorkingDirectory()
            ?? tab.session.workingDirectory
            ?? NSHomeDirectory()
    }

    private var hasFavourites: Bool {
        !commandFavourites.commands(for: currentPath).isEmpty
    }

    private var placeholder: String {
        if tab.isCommandRunning || !tab.commandQueue.isEmpty {
            return "Queue next command"
        }
        return "Enter a command"
    }

    private func fillFavourite(_ command: String) {
        tab.commandDraft = command
        focusAfterFavouritesClose = true
        showFavourites = false
    }

    private func submit() {
        let command = tab.commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        tab.submitCommand(command)
        tab.commandDraft = ""
        CommandFieldFocus.isActive = true
        focusToken += 1
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

private struct CommandLineTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        field.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            CommandFieldFocus.claim(nsView)
            for delay in [0.0, 0.05, 0.15, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    CommandFieldFocus.restoreIfNeeded()
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var focusToken = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            CommandFieldFocus.isActive = true
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                CommandFieldFocus.isActive = true
                onSubmit()
                if let field = control as? NSTextField {
                    field.stringValue = ""
                    text.wrappedValue = ""
                }
                return true
            }
            return false
        }
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
