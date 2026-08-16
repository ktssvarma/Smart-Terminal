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
    var body: some View {
        Text("Hello, world!")
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
