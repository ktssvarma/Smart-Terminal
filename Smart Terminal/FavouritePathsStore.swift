#if os(macOS)
import Combine
import Foundation

struct FavouritePath: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

final class FavouritePathsStore: ObservableObject {
    static let shared = FavouritePathsStore()

    @Published private(set) var favourites: [FavouritePath] = []

    private let defaultsKey = "SmartTerminal.favouritePaths"

    private init() {
        load()
    }

    func add(name: String, path: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let expandedPath = Self.expandedPath(path)
        guard !trimmedName.isEmpty, !expandedPath.isEmpty else { return }
        favourites.append(FavouritePath(name: trimmedName, path: expandedPath))
        persist()
    }

    static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([FavouritePath].self, from: data) else {
            return
        }
        favourites = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favourites) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
#endif
