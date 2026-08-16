#if os(macOS)
import AppKit
import SwiftUI

struct TerminalTabBar: View {
    @ObservedObject var manager: TabManager
    @ObservedObject private var favourites = FavouritePathsStore.shared
    @State private var isAddingFavourite = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(manager.tabs) { tab in
                TerminalTabChip(
                    tab: tab,
                    isSelected: tab.id == manager.selectedID,
                    onSelect: { manager.select(tab.id) },
                    onClose: { manager.close(tab.id) }
                )
            }

            Menu {
                Button("Home") {
                    manager.createTab(at: NSHomeDirectory())
                }

                if !favourites.favourites.isEmpty {
                    Divider()
                    ForEach(favourites.favourites) { favourite in
                        Button(favourite.name) {
                            manager.createTab(at: favourite.path)
                        }
                    }
                }

                Divider()

                Button("Add Favourite…") {
                    isAddingFavourite = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
            .foregroundStyle(.secondary)
            .help("New Tab")

            Spacer(minLength: 0)
        }
        .padding(.leading, 78)
        .padding(.trailing, 8)
        .frame(height: 30)
        .sheet(isPresented: $isAddingFavourite) {
            AddFavouriteSheet(
                onCancel: { isAddingFavourite = false },
                onSave: { name, path in
                    favourites.add(name: name, path: path)
                    isAddingFavourite = false
                },
                onSaveAndNavigate: { name, path in
                    favourites.add(name: name, path: path)
                    isAddingFavourite = false
                    manager.createTab(at: FavouritePathsStore.expandedPath(path))
                }
            )
        }
    }
}

private struct TerminalTabChip: View {
    @ObservedObject var tab: TerminalTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.14) : Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .background(MiddleClickCatcher(action: onClose))
        .help(tab.title)
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        MiddleClickView(action: action)
    }

    func updateNSView(_ nsView: MiddleClickView, context: Context) {
        nsView.action = action
    }
}

private final class MiddleClickView: NSView {
    var action: () -> Void
    private var monitor: Any?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitor()
        }
    }

    deinit {
        removeMonitor()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, event.window == self.window, event.buttonNumber == 2 else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }
            self.action()
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
#endif
