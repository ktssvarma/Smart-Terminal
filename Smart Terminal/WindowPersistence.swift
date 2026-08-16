import SwiftUI

#if os(macOS)
import AppKit

struct PersistentWindowDimensions: NSViewRepresentable {
    var autosaveName: String = "SmartTerminal.MainWindow"

    func makeCoordinator() -> Coordinator {
        Coordinator(autosaveName: autosaveName)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        private let autosaveName: String
        private var didRestore = false
        private var observers: [NSObjectProtocol] = []

        init(autosaveName: String) {
            self.autosaveName = autosaveName
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                self.configure(window)
            }
        }

        private func configure(_ window: NSWindow) {
            applyGlassChrome(to: window)

            if !didRestore {
                didRestore = true
                window.setFrameUsingName(autosaveName)
                window.setFrameAutosaveName(autosaveName)
            }

            guard observers.isEmpty else { return }

            let center = NotificationCenter.default
            let save: (Notification) -> Void = { [autosaveName] notification in
                (notification.object as? NSWindow)?.saveFrame(usingName: autosaveName)
            }

            observers = [
                center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main, using: save),
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save),
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: save)
            ]
        }

        private func applyGlassChrome(to window: NSWindow) {
            window.appearance = NSAppearance(named: .darkAqua)
            window.isOpaque = true
            window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.titleVisibility = .hidden
            window.toolbarStyle = .unifiedCompact
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

struct HiddenWindowToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content.toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}

struct GlassWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
    }
}
#endif
