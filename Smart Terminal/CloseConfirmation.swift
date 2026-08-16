#if os(macOS)
import AppKit

enum CloseConfirmation {
    static var isTerminating = false

    static func confirmCloseTab(title: String, session: TerminalSession) -> Bool {
        let command = session.isForegroundCommandRunning()
        let port = session.hasListeningPort()
        guard command || port else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Close “\(title)”?"
        alert.informativeText = message(command: command, port: port, plural: false)
        alert.addButton(withTitle: "Close Tab")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmCloseWindow(tabs: [TerminalTab]) -> Bool {
        let command = tabs.contains { $0.session.isForegroundCommandRunning() }
        let port = tabs.contains { $0.session.hasListeningPort() }
        guard command || port else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Close Window?"
        alert.informativeText = message(command: command, port: port, plural: tabs.count > 1)
        alert.addButton(withTitle: "Close Window")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmDeleteFavourite(name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "This favourite will be removed from the New Tab menu. Open tabs are not affected."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmApplicationQuit() -> NSApplication.TerminateReply {
        let busy = WindowTabManagers.all.flatMap(\.tabs).filter(\.session.isBusy)
        guard !busy.isEmpty else { return .terminateNow }

        let command = busy.contains { $0.session.isForegroundCommandRunning() }
        let port = busy.contains { $0.session.hasListeningPort() }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit Smart Terminal?"
        alert.informativeText = message(command: command, port: port, plural: true)
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }
        isTerminating = true
        return .terminateNow
    }

    private static func message(command: Bool, port: Bool, plural: Bool) -> String {
        switch (command, port, plural) {
        case (true, true, false):
            return "This tab has a running command and an open port. Closing it will stop that process."
        case (true, false, false):
            return "This tab has a command still running. Closing it will stop that process."
        case (false, true, false):
            return "This tab has an open port. Closing it will stop that process."
        case (true, true, true):
            return "One or more tabs have a running command or an open port. Closing will stop those processes."
        case (true, false, true):
            return "One or more tabs have a command still running. Closing will stop those processes."
        case (false, true, true):
            return "One or more tabs have an open port. Closing will stop those processes."
        default:
            return ""
        }
    }
}

final class TerminalAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        CloseConfirmation.confirmApplicationQuit()
    }
}

final class WindowCloseGuard: NSObject, NSWindowDelegate {
    weak var manager: TabManager?
    weak var original: NSWindowDelegate?

    func attach(to window: NSWindow, manager: TabManager) {
        self.manager = manager
        if window.delegate !== self {
            original = window.delegate
            window.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let manager, manager.shouldAllowWindowClose() else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector) -> Any? {
        original
    }
}
#endif
