#if os(macOS)
import AppKit
import SwiftUI
import SwiftTerm

enum CommandFieldFocus {
    static var isActive = false
    static weak var field: NSTextField?

    static func claim(_ field: NSTextField) {
        isActive = true
        self.field = field
        guard let window = field.window, window.isVisible else { return }
        window.makeFirstResponder(field)
    }

    static func restoreIfNeeded() {
        guard isActive, let field, let window = field.window, window.isVisible else { return }
        if window.firstResponder !== field, window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
    }
}

final class HostedTerminalView: LocalProcessTerminalView {
    var onReady: (() -> Void)?
    private var clickMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeClickMonitor()
        } else {
            installClickMonitor()
            DispatchQueue.main.async { [weak self] in
                self?.onReady?()
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize.width > 1, newSize.height > 1 {
            onReady?()
        }
    }

    deinit {
        removeClickMonitor()
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window == self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) {
                CommandFieldFocus.isActive = false
            }
            return event
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}

struct TerminalView: NSViewRepresentable {
    let session: TerminalSession
    var isActive: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> HostedTerminalView {
        let view = HostedTerminalView(frame: .zero)
        view.font = NSFont(name: "SF Mono", size: 14)
            ?? NSFont(name: "Menlo", size: 14)
            ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        view.wantsLayer = true
        view.layer?.cornerRadius = AppTheme.terminalCorner
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.processDelegate = context.coordinator
        view.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        view.getTerminal().changeHistorySize(5_000)
        session.attach(view)
        view.onReady = { [session] in
            session.startIfNeeded()
        }
        return view
    }

    func updateNSView(_ nsView: HostedTerminalView, context: Context) {
        context.coordinator.session = session
        nsView.processDelegate = context.coordinator
        session.attach(nsView)
        session.startIfNeeded()

        if isActive, !context.coordinator.isActive, !CommandFieldFocus.isActive {
            nsView.window?.makeFirstResponder(nsView)
        }
        context.coordinator.isActive = isActive
    }

    final class Coordinator: LocalProcessTerminalViewDelegate {
        var session: TerminalSession
        var isActive = true

        init(session: TerminalSession) {
            self.session = session
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            session.updateWorkingDirectory(directory)
        }

        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            let code = exitCode.map(String.init) ?? "?"
            source.feed(text: "\r\n[Process completed with code \(code)]\r\n")
        }
    }
}
#endif
