#if os(macOS)
import AppKit
import Combine
import Foundation
import SwiftUI

final class TerminalTab: Identifiable, ObservableObject {
    let id: UUID
    let session: TerminalSession
    @Published var title: String
    @Published var isPinned: Bool
    @Published var isCommandRunning = false
    @Published var commandDraft = ""
    @Published var commandQueue: [QueuedCommand] = []
    var onStateChange: (() -> Void)?

    private var isAwaitingCompletion = false
    private var completionFallback: DispatchWorkItem?

    init(id: UUID = UUID(), workingDirectory: String? = nil, isPinned: Bool = false) {
        self.id = id
        self.isPinned = isPinned
        session = TerminalSession(workingDirectory: workingDirectory)
        title = Self.title(for: workingDirectory, shellPath: session.shellPath)
        session.onWorkingDirectoryChange = { [weak self] directory in
            guard let self else { return }
            self.title = Self.title(for: directory, shellPath: self.session.shellPath)
            self.onStateChange?()
        }
        session.onCommandRunningChange = { [weak self] running in
            self?.handleCommandRunningChange(running)
        }
    }

    func removeQueuedCommand(_ id: UUID) {
        commandQueue.removeAll { $0.id == id }
    }

    func submitCommand(_ command: String) {
        if isCommandRunning || isAwaitingCompletion || !commandQueue.isEmpty {
            commandQueue.append(QueuedCommand(text: command))
            return
        }
        startCommand(command)
    }

    private func handleCommandRunningChange(_ running: Bool) {
        isCommandRunning = running
        if running {
            isAwaitingCompletion = true
            completionFallback?.cancel()
            return
        }
        if isAwaitingCompletion {
            finishCurrentAndRunNext()
        }
    }

    private func startCommand(_ command: String) {
        isAwaitingCompletion = true
        session.sendCommand(command)
        scheduleCompletionFallback()
    }

    private func scheduleCompletionFallback() {
        completionFallback?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isAwaitingCompletion, !self.isCommandRunning else { return }
            self.finishCurrentAndRunNext()
        }
        completionFallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func finishCurrentAndRunNext() {
        isAwaitingCompletion = false
        completionFallback?.cancel()
        completionFallback = nil
        while !commandQueue.isEmpty {
            let next = commandQueue.removeFirst()
            let text = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                startCommand(text)
                return
            }
        }
    }

    static func title(for directory: String?, shellPath: String) -> String {
        if let directory, !directory.isEmpty {
            let name = URL(fileURLWithPath: directory).lastPathComponent
            if !name.isEmpty {
                return name
            }
        }
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
        return shellName.isEmpty ? "zsh" : shellName
    }
}

final class QueuedCommand: Identifiable {
    let id = UUID()
    var text: String

    init(text: String) {
        self.text = text
    }
}

final class TabManager: NSObject, ObservableObject {
    @Published private(set) var tabs: [TerminalTab]
    @Published var selectedID: UUID
    var onCloseWindow: (() -> Void)?
    var allowNextWindowClose = false

    var selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedID }
    }

    override init() {
        if let restored = Self.restore() {
            tabs = restored.tabs
            selectedID = restored.selectedID
        } else {
            let tab = TerminalTab()
            tabs = [tab]
            selectedID = tab.id
        }
        super.init()
        sortPinned()
        bindPersistence()
        persist()
    }

    func createTab(at directory: String? = nil) {
        let path: String?
        if let directory, !directory.isEmpty {
            path = FavouritePathsStore.expandedPath(directory)
        } else {
            selectedTab?.session.updateWorkingDirectory(selectedTab?.session.resolvedWorkingDirectory())
            path = selectedTab?.session.resolvedWorkingDirectory()
        }
        let tab = TerminalTab(workingDirectory: path)
        tabs.append(tab)
        selectedID = tab.id
        sortPinned()
        bindPersistence()
        persist()
    }

    func togglePin(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isPinned.toggle()
        sortPinned()
        persist()
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
    }

    func selectIndex(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedID = tabs[index].id
    }

    func selectNext() {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        selectIndex((index + 1) % tabs.count)
    }

    func selectPrevious() {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        selectIndex((index - 1 + tabs.count) % tabs.count)
    }

    func close(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.isPinned, !CloseConfirmation.confirmClosePinnedTab(title: tab.title) {
            return
        }
        if tab.session.isBusy, !CloseConfirmation.confirmCloseTab(title: tab.title, session: tab.session) {
            return
        }
        forceClose(id)
    }

    func shouldAllowWindowClose() -> Bool {
        if allowNextWindowClose || CloseConfirmation.isTerminating {
            allowNextWindowClose = false
            return true
        }
        let busy = tabs.filter(\.session.isBusy)
        guard !busy.isEmpty else { return true }
        return CloseConfirmation.confirmCloseWindow(tabs: busy)
    }

    private func forceClose(_ id: UUID) {
        if tabs.count <= 1 {
            persist()
            allowNextWindowClose = true
            tabs.first?.session.stop()
            onCloseWindow?()
            return
        }

        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        tab.session.stop()
        if selectedID == id {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
        bindPersistence()
        persist()
    }

    func closeSelected() {
        close(selectedID)
    }

    func closeAll() {
        let unpinned = tabs.filter { !$0.isPinned }
        guard !unpinned.isEmpty else { return }
        guard CloseConfirmation.confirmCloseAllTabs(
            count: unpinned.count,
            hasBusy: unpinned.contains(where: \.session.isBusy)
        ) else { return }

        if unpinned.count == tabs.count {
            allowNextWindowClose = true
            tabs.forEach { $0.session.stop() }
            persistEmpty()
            onCloseWindow?()
            return
        }

        unpinned.forEach { $0.session.stop() }
        tabs.removeAll { !$0.isPinned }
        if !tabs.contains(where: { $0.id == selectedID }) {
            selectedID = tabs[0].id
        }
        bindPersistence()
        persist()
    }

    func shutdown() {
        persist()
        tabs.forEach { $0.session.stop() }
    }

    private func sortPinned() {
        let selected = selectedID
        tabs = tabs.filter(\.isPinned) + tabs.filter { !$0.isPinned }
        selectedID = selected
    }

    private func bindPersistence() {
        for tab in tabs {
            tab.onStateChange = { [weak self] in
                self?.persist()
            }
        }
    }

    private func persist() {
        let snapshot = PersistedTabsState(
            tabs: tabs.map { tab in
                PersistedTab(
                    id: tab.id,
                    workingDirectory: tab.session.resolvedWorkingDirectory() ?? tab.session.workingDirectory,
                    isPinned: tab.isPinned
                )
            },
            selectedID: selectedID
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func persistEmpty() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    private static func restore() -> (tabs: [TerminalTab], selectedID: UUID)? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(PersistedTabsState.self, from: data),
              !snapshot.tabs.isEmpty else {
            return nil
        }

        let restored = snapshot.tabs.map { record in
            TerminalTab(
                id: record.id,
                workingDirectory: Self.restoredDirectory(record.workingDirectory),
                isPinned: record.isPinned
            )
        }
        let selectedID = restored.contains(where: { $0.id == snapshot.selectedID })
            ? snapshot.selectedID
            : restored[0].id
        return (restored, selectedID)
    }

    private static func restoredDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let expanded = FavouritePathsStore.expandedPath(path)
        if FileManager.default.fileExists(atPath: expanded) {
            return expanded
        }
        return NSHomeDirectory()
    }

    private static let defaultsKey = "SmartTerminal.openTabs"
}

private struct PersistedTab: Codable {
    var id: UUID
    var workingDirectory: String?
    var isPinned: Bool

    init(id: UUID, workingDirectory: String?, isPinned: Bool) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

private struct PersistedTabsState: Codable {
    var tabs: [PersistedTab]
    var selectedID: UUID
}

enum WindowTabManagers {
    private static let map = NSMapTable<NSWindow, TabManager>.weakToStrongObjects()

    static func bind(_ manager: TabManager, to window: NSWindow) {
        map.setObject(manager, forKey: window)
    }

    static var all: [TabManager] {
        (map.objectEnumerator()?.allObjects as? [TabManager]) ?? []
    }

    static var keyWindowManager: TabManager? {
        if let keyWindow = NSApp.keyWindow, let manager = map.object(forKey: keyWindow) {
            return manager
        }
        if let mainWindow = NSApp.mainWindow, let manager = map.object(forKey: mainWindow) {
            return manager
        }
        return nil
    }
}

struct WindowTabManagerBinder: NSViewRepresentable {
    let manager: TabManager

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.manager = manager
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        var manager: TabManager
        let closeGuard = WindowCloseGuard()

        init(manager: TabManager) {
            self.manager = manager
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                WindowTabManagers.bind(self.manager, to: window)
                self.closeGuard.attach(to: window, manager: self.manager)
            }
        }
    }
}
#endif
