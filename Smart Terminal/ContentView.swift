import SwiftUI
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
    }
}

struct ContentView: View {
    #if os(macOS)
    @State private var session = TerminalSession()
    #endif

    var body: some View {
        #if os(macOS)
        TerminalView(session: session)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDisappear {
                session.stop()
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
