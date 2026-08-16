#if os(macOS)
import AppKit
import SwiftUI
import SwiftTerm

final class HostedTerminalView: LocalProcessTerminalView {
    var onReady: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onReady?()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize.width > 1, newSize.height > 1 {
            onReady?()
        }
    }
}

struct TerminalView: NSViewRepresentable {
    let session: TerminalSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> HostedTerminalView {
        let view = HostedTerminalView(frame: .zero)
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.processDelegate = context.coordinator
        view.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        view.getTerminal().changeHistorySize(5_000)
        session.attach(view)
        view.onReady = { [session] in
            view.window?.makeFirstResponder(view)
            session.startIfNeeded()
        }
        return view
    }

    func updateNSView(_ nsView: HostedTerminalView, context: Context) {
        session.startIfNeeded()
    }

    final class Coordinator: LocalProcessTerminalViewDelegate {
        let session: TerminalSession

        init(session: TerminalSession) {
            self.session = session
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            source.window?.title = title.isEmpty ? "Smart Terminal" : title
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            let code = exitCode.map(String.init) ?? "?"
            let message = "\r\n[Process completed with code \(code)]\r\n"
            source.feed(text: message)
        }
    }
}
#endif
