import SwiftUI
#if os(macOS)
import AppKit
#endif
#if canImport(Playgrounds)
import Playgrounds
#endif

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .containerBackground(for: .window) {
                    GlassWindowBackground()
                }
                .modifier(HiddenWindowToolbarBackground())
                .background(PersistentWindowDimensions())
                #endif
        }
        .defaultSize(width: 800, height: 500)
        #if os(macOS)
        .commands {
            TerminalCommands()
        }
        #endif
    }
}

struct ContentView: View {
    #if os(macOS)
    @StateObject private var tabs = TabManager()
    #endif

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            TerminalTabBar(manager: tabs)
            Divider()
            ZStack {
                ForEach(tabs.tabs) { tab in
                    TerminalView(session: tab.session, isActive: tab.id == tabs.selectedID)
                        .opacity(tab.id == tabs.selectedID ? 1 : 0)
                        .allowsHitTesting(tab.id == tabs.selectedID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview {
    ContentView()
}

#if canImport(Playgrounds)
#Playground {
    _ = 1 + 2
}
#endif
