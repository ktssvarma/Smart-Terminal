#if os(macOS)
import AppKit
import Combine
import Foundation
import SwiftUI

final class TerminalTab: Identifiable, ObservableObject {
    let id = UUID()
    let session: TerminalSession
    @Published var title: String

    init(workingDirectory: String? = nil) {
        session = TerminalSession(workingDirectory: workingDirectory)
        title = Self.title(for: workingDirectory, shellPath: session.shellPath)
        session.onWorkingDirectoryChange = { [weak self] directory in
            guard let self else { return }
            self.title = Self.title(for: directory, shellPath: self.session.shellPath)
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

final class TabManager: NSObject, ObservableObject {
    @Published private(set) var tabs: [TerminalTab]
    @Published var selectedID: UUID
    var onCloseWindow: (() -> Void)?

    var selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedID }
    }

    override init() {
        let tab = TerminalTab()
        tabs = [tab]
        selectedID = tab.id
        super.init()
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
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
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
        if tabs.count <= 1 {
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
    }

    func closeSelected() {
        close(selectedID)
    }

    func shutdown() {
        tabs.forEach { $0.session.stop() }
    }
}

enum WindowTabManagers {
    private static let map = NSMapTable<NSWindow, TabManager>.weakToStrongObjects()

    static func bind(_ manager: TabManager, to window: NSWindow) {
        map.setObject(manager, forKey: window)
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

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WindowTabManagers.bind(manager, to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                WindowTabManagers.bind(manager, to: window)
            }
        }
    }
}
#endif
