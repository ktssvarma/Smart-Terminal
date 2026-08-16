#if os(macOS)
import Combine
import Foundation

struct FavouriteCommand: Identifiable, Codable, Hashable {
    var id: UUID
    var command: String

    init(id: UUID = UUID(), command: String) {
        self.id = id
        self.command = command
    }
}

final class FavouriteCommandsStore: ObservableObject {
    static let shared = FavouriteCommandsStore()

    @Published private var commandsByPath: [String: [FavouriteCommand]] = [:]

    private let defaultsKey = "SmartTerminal.favouriteCommands"

    private init() {
        load()
    }

    func commands(for path: String) -> [FavouriteCommand] {
        commandsByPath[Self.normalizedPath(path)] ?? []
    }

    func add(command: String, to path: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.normalizedPath(path)
        guard !trimmed.isEmpty, !key.isEmpty else { return }
        var list = commandsByPath[key] ?? []
        guard !list.contains(where: { $0.command == trimmed }) else { return }
        list.append(FavouriteCommand(command: trimmed))
        commandsByPath[key] = list
        persist()
    }

    func remove(_ id: UUID, from path: String) {
        let key = Self.normalizedPath(path)
        commandsByPath[key]?.removeAll { $0.id == id }
        if commandsByPath[key]?.isEmpty == true {
            commandsByPath[key] = nil
        }
        persist()
    }

    func move(id: UUID, before targetID: UUID, path: String) {
        let key = Self.normalizedPath(path)
        guard var list = commandsByPath[key],
              id != targetID,
              let from = list.firstIndex(where: { $0.id == id }),
              list.contains(where: { $0.id == targetID }) else { return }
        let item = list.remove(at: from)
        let insertAt = list.firstIndex(where: { $0.id == targetID }) ?? list.count
        list.insert(item, at: insertAt)
        commandsByPath[key] = list
        persist()
    }

    static func normalizedPath(_ path: String) -> String {
        FavouritePathsStore.expandedPath(path)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [FavouriteCommand]].self, from: data) else {
            return
        }
        commandsByPath = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commandsByPath) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
#endif
