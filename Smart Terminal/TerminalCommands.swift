#if os(macOS)
import SwiftUI

struct TerminalCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                WindowTabManagers.keyWindowManager?.createTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                WindowTabManagers.keyWindowManager?.closeSelected()
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                WindowTabManagers.keyWindowManager?.selectedTab?.session.copySelection()
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                WindowTabManagers.keyWindowManager?.selectedTab?.session.pasteClipboard()
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Select All") {
                WindowTabManagers.keyWindowManager?.selectedTab?.session.selectAllText()
            }
            .keyboardShortcut("a", modifiers: .command)
        }

        CommandMenu("Tabs") {
            Button("Show Next Tab") {
                WindowTabManagers.keyWindowManager?.selectNext()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Show Previous Tab") {
                WindowTabManagers.keyWindowManager?.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") {
                    WindowTabManagers.keyWindowManager?.selectIndex(number - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }
    }
}
#endif
