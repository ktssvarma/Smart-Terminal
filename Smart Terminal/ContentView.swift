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
    #endif

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            TerminalTabBar(manager: tabs)

            AppTheme.border.frame(width: 1)

            ZStack {
                AppTheme.terminal
                ForEach(tabs.tabs) { tab in
                    TerminalView(session: tab.session, isActive: tab.id == tabs.selectedID)
                        .opacity(tab.id == tabs.selectedID ? 1 : 0)
                        .allowsHitTesting(tab.id == tabs.selectedID)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
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
                tabs.selectedTab?.session.focus()
            }
        }
        .onChange(of: tabs.selectedID) { _, _ in
            DispatchQueue.main.async {
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
