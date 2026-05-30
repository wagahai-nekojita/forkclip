import Foundation

struct ClipboardFolder: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var color: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        color: String = "#4A90E2",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum HistoryFolderSelection: Hashable, Sendable {
    case all
    case unfiled
    case folder(UUID)
}
