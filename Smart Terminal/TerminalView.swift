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
    var onExitCode: ((Int) -> Void)?
    var onOutput: ((String) -> Void)?
    private var clickMonitor: Any?
    private let exitScanner = ExitMarkerScanner()

    override func dataReceived(slice: ArraySlice<UInt8>) {
        let result = exitScanner.ingest(slice)
        if let code = result.code {
            DispatchQueue.main.async { [weak self] in
                self?.onExitCode?(code)
            }
        }
        if let text = String(bytes: result.visible, encoding: .utf8), !text.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onOutput?(text)
            }
        }
        super.dataReceived(slice: result.visible[...])
    }

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
        view.onExitCode = { [session] code in
            session.acceptExitCode(code)
        }
        view.onOutput = { [session] text in
            session.appendCapturedOutput(text)
        }
        view.onReady = { [session] in
            session.startIfNeeded()
        }
        return view
    }

    func updateNSView(_ nsView: HostedTerminalView, context: Context) {
        context.coordinator.session = session
        nsView.processDelegate = context.coordinator
        nsView.onExitCode = { [session] code in
            session.acceptExitCode(code)
        }
        nsView.onOutput = { [session] text in
            session.appendCapturedOutput(text)
        }
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

final class ExitMarkerScanner {
    private var buffer: [UInt8] = []
    private let start = Array("__ST_EXIT:".utf8)
    private let end = Array("__".utf8)

    func ingest(_ slice: ArraySlice<UInt8>) -> (visible: [UInt8], code: Int?) {
        buffer.append(contentsOf: slice)
        var visible: [UInt8] = []
        var code: Int?
        var index = 0
        while index < buffer.count {
            if match(start, at: index) {
                let numberStart = index + start.count
                if let markerEnd = completeMarkerEnd(from: numberStart) {
                    let digits = buffer[numberStart..<markerEnd - end.count]
                    if let parsed = Int(String(bytes: digits, encoding: .utf8) ?? "") {
                        code = parsed
                    }
                    index = markerEnd
                    continue
                }
                if isPossiblyIncomplete(from: numberStart) {
                    buffer = Array(buffer[index...])
                    return (visible, code)
                }
            }
            if buffer.count - index < start.count, isPrefix(Array(buffer[index...]), of: start) {
                buffer = Array(buffer[index...])
                return (visible, code)
            }
            visible.append(buffer[index])
            index += 1
        }
        buffer.removeAll(keepingCapacity: true)
        return (visible, code)
    }

    private func match(_ pattern: [UInt8], at index: Int) -> Bool {
        guard index + pattern.count <= buffer.count else { return false }
        return zip(buffer[index..<index + pattern.count], pattern).allSatisfy { $0 == $1 }
    }

    private func completeMarkerEnd(from numberStart: Int) -> Int? {
        var index = numberStart
        if index < buffer.count, buffer[index] == 45 {
            index += 1
        }
        let digitsStart = index
        while index < buffer.count, buffer[index] >= 48, buffer[index] <= 57 {
            index += 1
        }
        guard index > digitsStart, match(end, at: index) else { return nil }
        return index + end.count
    }

    private func isPossiblyIncomplete(from numberStart: Int) -> Bool {
        if numberStart >= buffer.count { return true }
        var index = numberStart
        if buffer[index] == 45 {
            index += 1
            if index >= buffer.count { return true }
        }
        while index < buffer.count, buffer[index] >= 48, buffer[index] <= 57 {
            index += 1
        }
        if index >= buffer.count { return true }
        return isPrefix(Array(buffer[index...]), of: end)
    }

    private func isPrefix(_ value: [UInt8], of pattern: [UInt8]) -> Bool {
        zip(value, pattern).allSatisfy { $0 == $1 }
    }
}
#endif
