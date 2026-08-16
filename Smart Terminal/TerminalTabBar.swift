#if os(macOS)
import AppKit
import SwiftUI

struct TerminalTabBar: View {
    @ObservedObject var manager: TabManager
    @ObservedObject private var favourites = FavouritePathsStore.shared
    @AppStorage("SmartTerminal.sidebarCollapsed") private var isCollapsed = false
    @State private var isAddingFavourite = false

    private var sidebarWidth: CGFloat {
        isCollapsed ? AppTheme.sidebarCollapsedWidth : AppTheme.sidebarWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.space1) {
                    ForEach(manager.tabs) { tab in
                        TerminalTabChip(
                            tab: tab,
                            isCollapsed: isCollapsed,
                            isSelected: tab.id == manager.selectedID,
                            onSelect: { manager.select(tab.id) },
                            onPin: { manager.togglePin(tab.id) },
                            onClose: { manager.close(tab.id) },
                            onCloseAll: { manager.closeAll() },
                            canCloseAll: manager.tabs.contains { !$0.isPinned }
                        )
                    }
                }
                .padding(.horizontal, AppTheme.space2)
                .padding(.top, AppTheme.space2)
                .padding(.bottom, AppTheme.space1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            newTabMenu
                .padding(.horizontal, AppTheme.space2)
                .padding(.top, AppTheme.space1)
                .padding(.bottom, AppTheme.space2)
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(AppTheme.sidebar)
        .animation(AppTheme.motion, value: isCollapsed)
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

    private var newTabMenu: some View {
        Button(action: showNewTabMenu) {
            NewTabButton(isCollapsed: isCollapsed)
        }
        .buttonStyle(.plain)
        .help("New Tab")
    }

    private func showNewTabMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let home = menu.addItem(withTitle: "Home", action: nil, keyEquivalent: "")
        home.target = NewTabMenuActions.shared
        home.representedObject = NewTabMenuActions.Handler { [manager] in
            manager.createTab(at: NSHomeDirectory())
        }

        if !favourites.favourites.isEmpty {
            menu.addItem(.separator())
            for favourite in favourites.favourites {
                let item = menu.addItem(withTitle: favourite.name, action: nil, keyEquivalent: "")
                item.target = NewTabMenuActions.shared
                item.representedObject = NewTabMenuActions.Handler { [manager] in
                    manager.createTab(at: favourite.path)
                }
            }
        }

        menu.addItem(.separator())
        let add = menu.addItem(withTitle: "Add Favourite…", action: nil, keyEquivalent: "")
        add.target = NewTabMenuActions.shared
        add.representedObject = NewTabMenuActions.Handler {
            isAddingFavourite = true
        }

        if !favourites.favourites.isEmpty {
            let deleteMenu = NSMenu()
            for favourite in favourites.favourites {
                let item = deleteMenu.addItem(withTitle: favourite.name, action: nil, keyEquivalent: "")
                item.target = NewTabMenuActions.shared
                item.representedObject = NewTabMenuActions.Handler { [favourites] in
                    guard CloseConfirmation.confirmDeleteFavourite(name: favourite.name) else { return }
                    favourites.remove(favourite.id)
                }
            }
            let delete = menu.addItem(withTitle: "Delete Favourite", action: nil, keyEquivalent: "")
            delete.submenu = deleteMenu
        }

        NewTabMenuActions.shared.install(on: menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class NewTabMenuActions: NSObject {
    static let shared = NewTabMenuActions()

    final class Handler {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    func install(on menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                install(on: submenu)
            }
            guard item.representedObject is Handler else { continue }
            item.target = self
            item.action = #selector(invoke(_:))
        }
    }

    @objc func invoke(_ sender: NSMenuItem) {
        (sender.representedObject as? Handler)?.run()
    }
}

private struct NewTabButton: View {
    let isCollapsed: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppTheme.space2) {
            Text("+")
                .font(.system(size: 13, weight: .medium))
            if !isCollapsed {
                Text("New Tab")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, isCollapsed ? AppTheme.space1 : 10)
        .frame(maxWidth: .infinity, minHeight: AppTheme.newTabHeight, alignment: isCollapsed ? .center : .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .fill(isHovering ? AppTheme.fillUtilityHover : AppTheme.fillUtility)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
        .onHover { hovering in
            withAnimation(AppTheme.motion) {
                isHovering = hovering
            }
        }
    }
}

private struct TerminalTabChip: View {
    @ObservedObject var tab: TerminalTab
    let isCollapsed: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onPin: () -> Void
    let onClose: () -> Void
    let onCloseAll: () -> Void
    let canCloseAll: Bool

    @State private var isHovering = false
    @State private var isCloseHovering = false

    private var displayTitle: String {
        if isCollapsed {
            let letter = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).first
            return letter.map { String($0).uppercased() } ?? "?"
        }
        return tab.title
    }

    var body: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: AppTheme.space1) {
            HStack(spacing: AppTheme.space2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
                    .help(tab.title)

                if !isCollapsed {
                    if isHovering || tab.isPinned {
                        Button(action: onPin) {
                            Image(systemName: tab.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: AppTheme.closeSize, height: AppTheme.closeSize)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.textSecondary)
                        .help(tab.isPinned ? "Unpin Tab" : "Pin Tab")
                    }

                    if !tab.isPinned, isHovering || isSelected {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: AppTheme.closeSize, height: AppTheme.closeSize)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isCloseHovering ? Color(red: 1, green: 0.38, blue: 0.38) : AppTheme.textSecondary)
                        .onHover { isCloseHovering = $0 }
                    }
                }
            }

            if tab.isCommandRunning {
                TabCommandProgressBar()
            }
        }
        .padding(.horizontal, isCollapsed ? AppTheme.space1 : 10)
        .padding(.vertical, AppTheme.space2)
        .frame(maxWidth: .infinity, minHeight: AppTheme.tabHeight, alignment: isCollapsed ? .center : .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .fill(isSelected ? AppTheme.fillActive : (isHovering ? AppTheme.fillHover : AppTheme.fillIdle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                .strokeBorder(isSelected ? AppTheme.border : Color.clear, lineWidth: 1)
        )
        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
        .animation(AppTheme.motion, value: isHovering)
        .animation(AppTheme.motion, value: isSelected)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", action: onPin)
            Button("Close Tab", action: onClose)
            Button("Close All Tabs", action: onCloseAll)
                .disabled(!canCloseAll)
        }
        .background(MiddleClickCatcher(action: onClose))
        .background(TabNameTooltip(text: tab.title))
        .help(tab.title)
    }
}

private struct TabCommandProgressBar: View {
    @State private var travel = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width * 0.38, 16)
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: width, height: 2)
                .offset(x: travel ? geo.size.width - width : 0)
        }
        .frame(height: 2)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .clipShape(Capsule())
        .onAppear {
            travel = false
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                travel = true
            }
        }
    }
}

private struct TabNameTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipView {
        let view = TooltipView()
        view.text = text
        return view
    }

    func updateNSView(_ nsView: TooltipView, context: Context) {
        nsView.text = text
    }
}

private final class TooltipView: NSView {
    var text: String = "" {
        didSet { toolTip = text }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
        toolTip = text
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
